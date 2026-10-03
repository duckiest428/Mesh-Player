//
//  WordLyrics.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  Experimental: word-synced lyrics (each word lights up as it's sung, like Apple Music),
//  from NetEase Cloud Music's public "yrc" lyrics. Results, including "none found", are
//  cached on disk per song.
//

import Foundation

nonisolated final class WordLyricsService: @unchecked Sendable {
    static let shared = WordLyricsService()

    private struct Entry: Codable {
        var yrc: String?
        var checked: Date
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private let cacheURL: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        cacheURL = caches.appendingPathComponent("word-lyrics.json")
        if let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = decoded
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    /// Word-synced lines for a song, or nil when none were found.
    func lines(title: String, artist: String, duration: TimeInterval) async -> [SyncedLyricLine]? {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        let cached = lock.withLock { cache[key] }
        let yrc: String?
        // Found lyrics are kept; misses are retried after a week.
        if let cached, cached.yrc != nil || Date().timeIntervalSince(cached.checked) < 7 * 86_400 {
            yrc = cached.yrc
        } else {
            yrc = await lookUp(title: title, artist: artist, duration: duration)
            lock.withLock { cache[key] = Entry(yrc: yrc, checked: Date()) }
            persist()
        }
        guard let yrc else { return nil }
        let parsed = Self.parse(yrc)
        return parsed.isEmpty ? nil : LyricsEngine.withBreaks(parsed)
    }

    // MARK: Lookup

    private func lookUp(title: String, artist: String, duration: TimeInterval) async -> String? {
        let cleanTitle = Self.strip(title)
        var search = URLComponents(string: "https://music.163.com/api/search/get")!
        search.queryItems = [
            URLQueryItem(name: "s", value: "\(cleanTitle) \(artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let json = await get(search.url),
              let songs = (json["result"] as? [String: Any])?["songs"] as? [[String: Any]] else { return nil }

        let wanted = Self.key(cleanTitle)
        let candidates = songs.filter { song in
            guard let name = song["name"] as? String, Self.key(Self.strip(name)) == wanted else { return false }
            let artists = (song["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            guard AnimatedArtworkService.artistsMatch(artists, artist) else { return false }
            // Same recording: within a few seconds of the local file's length.
            if duration > 0, let ms = song["duration"] as? Double, abs(ms / 1000 - duration) > 6 { return false }
            return true
        }
        for song in candidates.prefix(3) {
            guard let id = song["id"] as? Int else { continue }
            let url = URL(string: "https://music.163.com/api/song/lyric/v1?id=\(id)&lv=1&yv=1&tv=0")
            if let lyric = await get(url), let yrc = (lyric["yrc"] as? [String: Any])?["lyric"] as? String, yrc.contains("](") {
                return yrc
            }
        }
        return nil
    }

    private func get(_ url: URL?) async -> [String: Any]? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(AnimatedArtworkService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func persist() {
        let snapshot = lock.withLock { cache }
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: cacheURL, options: .atomic) }
    }

    // MARK: Parsing

    private static let lineRegex = try! NSRegularExpression(pattern: "^\\[(\\d+),(\\d+)\\](.*)$")
    private static let wordRegex = try! NSRegularExpression(pattern: "\\((\\d+),(\\d+),\\d+\\)([^(]*)")

    /// "[10950,2520](10950,450,0)Say (11400,570,0)baby…" → timed lines. Credit lines (JSON) are skipped.
    static func parse(_ yrc: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        for raw in yrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let ns = line as NSString
            guard let match = lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let start = Double(ns.substring(with: match.range(at: 1))),
                  let length = Double(ns.substring(with: match.range(at: 2))) else { continue }
            let body = ns.substring(with: match.range(at: 3)) as NSString
            var words: [TimedWord] = []
            for w in wordRegex.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
                guard let ws = Double(body.substring(with: w.range(at: 1))), let wl = Double(body.substring(with: w.range(at: 2))) else { continue }
                let text = body.substring(with: w.range(at: 3))
                    .replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
                if text.isEmpty { continue }
                words.append(TimedWord(text: text, start: ws / 1000, end: (ws + wl) / 1000))
            }
            // NetEase drops the space after words ending in an apostrophe ("catchin'you").
            for i in words.indices.dropLast() where words[i].text.hasSuffix("'") || words[i].text.hasSuffix("’") {
                if words[i + 1].text.first?.isLetter == true {
                    words[i] = TimedWord(text: words[i].text + " ", start: words[i].start, end: words[i].end)
                }
            }
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(SyncedLyricLine(timestamp: start / 1000, text: text, endTime: (start + length) / 1000, words: words))
        }
        return lines
    }

    /// Drops "(feat. …)", "[Remix]" and similar from titles for matching.
    static func strip(_ title: String) -> String {
        title.replacingOccurrences(of: "\\s*[\\(\\[](feat|ft|with|from)[^\\)\\]]*[\\)\\]]", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    static func key(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}
