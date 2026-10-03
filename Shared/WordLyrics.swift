//
//  WordLyrics.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  Experimental: word-synced lyrics (each word lights up as it's sung, like Apple Music),
//  timed from NetEase Cloud Music's public "yrc" lyrics. Results, including "none found",
//  are cached on disk per song.
//

import Foundation

nonisolated final class WordLyricsService: @unchecked Sendable {
    static let shared = WordLyricsService()

    /// One NetEase recording of the song that has word timing.
    private struct Candidate: Codable {
        var yrc: String
        var duration: TimeInterval
    }

    private struct Entry: Codable {
        var candidates: [Candidate]
        var checked: Date
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private let cacheURL: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        // v2: keeps every candidate recording, so the one matching your file's lyrics can be picked.
        cacheURL = caches.appendingPathComponent("word-lyrics-v2.json")
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("word-lyrics.json"))
        if let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = decoded
        }
        // No cookies: once NetEase has set its session cookie, its search ignores the query and
        // returns trending songs, so only the first lookup after launch ever worked.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    /// Word-synced lines for a song, or nil when none were found.
    ///
    /// When the file has lyrics, its own text and line breaks are kept (they're usually Apple
    /// Music's, which are better than NetEase's) and NetEase's word timings are mapped onto its
    /// words. Without lyrics in the file, NetEase's lines are used as they are.
    func lines(title: String, artist: String, duration: TimeInterval, fileLyrics: String) async -> [SyncedLyricLine]? {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        let cached = lock.withLock { cache[key] }
        let candidates: [Candidate]
        // Found lyrics are kept; misses are retried after a day.
        if let cached, !cached.candidates.isEmpty || Date().timeIntervalSince(cached.checked) < 86_400 {
            candidates = cached.candidates
        } else {
            candidates = await lookUp(title: title, artist: artist, duration: duration)
            lock.withLock { cache[key] = Entry(candidates: candidates, checked: Date()) }
            persist()
        }
        let timed = candidates
            .map { (lines: Self.parse($0.yrc), duration: $0.duration) }
            .filter { !$0.lines.isEmpty }
        guard !timed.isEmpty else { return nil }

        let fileLines = LyricsEngine.parse(lyricsText: fileLyrics, duration: duration).filter { !$0.isBreak && $0.text != "♫" }
        if !fileLines.isEmpty {
            let synced = LyricsEngine.isTimed(fileLyrics)
            let best = timed
                .map { Self.align(file: fileLines, fileIsSynced: synced, to: $0.lines) }
                .max { $0.matched < $1.matched }
            // Most of the file's words have to be found, or it's a different song or version.
            guard let best, best.matched >= 0.55 else { return nil }
            return LyricsEngine.withBreaks(best.lines)
        }

        // No lyrics in the file: NetEase's own lines, if it's the same recording.
        guard let closest = timed.min(by: { abs($0.duration - duration) < abs($1.duration - duration) }),
              duration <= 0 || abs(closest.duration - duration) <= 8 else { return nil }
        return LyricsEngine.withBreaks(closest.lines)
    }

    // MARK: Lookup

    private func lookUp(title: String, artist: String, duration: TimeInterval) async -> [Candidate] {
        let cleanTitle = Self.strip(title)
        var search = URLComponents(string: "https://music.163.com/api/search/get")!
        search.queryItems = [
            URLQueryItem(name: "s", value: "\(cleanTitle) \(artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "15")
        ]
        guard let json = await get(search.url),
              let songs = (json["result"] as? [String: Any])?["songs"] as? [[String: Any]] else { return [] }

        let wanted = Self.key(cleanTitle)
        let matches = songs.filter { song in
            guard let name = song["name"] as? String, Self.key(Self.strip(name)) == wanted else { return false }
            let artists = (song["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            return AnimatedArtworkService.artistsMatch(artists, artist)
        }
        // Closest in length first: most likely the same recording.
        let ordered = matches.sorted { a, b in
            let da = abs(((a["duration"] as? Double) ?? 0) / 1000 - duration)
            let db = abs(((b["duration"] as? Double) ?? 0) / 1000 - duration)
            return da < db
        }
        var found: [Candidate] = []
        for song in ordered.prefix(5) {
            guard let id = song["id"] as? Int else { continue }
            let url = URL(string: "https://music.163.com/api/song/lyric/v1?id=\(id)&lv=1&yv=1&tv=0")
            if let lyric = await get(url), let yrc = (lyric["yrc"] as? [String: Any])?["lyric"] as? String, yrc.contains("](") {
                found.append(Candidate(yrc: yrc, duration: ((song["duration"] as? Double) ?? 0) / 1000))
                if found.count == 3 { break }
            }
        }
        return found
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

    // MARK: Aligning to the file's lyrics

    /// Gives the file's lines NetEase's word timings, matching the two word sequences in order.
    /// `matched` is the share of the file's words that were found.
    static func align(file: [SyncedLyricLine], fileIsSynced: Bool, to timed: [SyncedLyricLine]) -> (lines: [SyncedLyricLine], matched: Double) {
        // The file's words, keeping their spacing, and which line each belongs to.
        var fileWords: [(line: Int, text: String, norm: String)] = []
        for (index, line) in file.enumerated() {
            let pieces = line.text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            for (i, piece) in pieces.enumerated() {
                fileWords.append((index, i < pieces.count - 1 ? piece + " " : piece, normalize(piece)))
            }
        }
        let source = timed.flatMap { $0.words ?? [] }
            .flatMap { word in
                // A NetEase "word" occasionally holds two ("up,we").
                word.text.split(separator: " ").map { (norm: normalize(String($0)), start: word.start, end: word.end) }
            }
            .filter { !$0.norm.isEmpty }

        let a = fileWords.indices.filter { !fileWords[$0].norm.isEmpty }
        let b = Array(source.indices)
        guard !a.isEmpty, !b.isEmpty else { return (file, 0) }

        // Longest common subsequence of the two word lists.
        let n = a.count, m = b.count
        var table = [UInt16](repeating: 0, count: (n + 1) * (m + 1))
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i * (m + 1) + j] = fileWords[a[i]].norm == source[b[j]].norm
                    ? table[(i + 1) * (m + 1) + j + 1] + 1
                    : max(table[(i + 1) * (m + 1) + j], table[i * (m + 1) + j + 1])
            }
        }
        var timing: [Int: (start: TimeInterval, end: TimeInterval)] = [:]
        var i = 0, j = 0
        while i < n && j < m {
            if fileWords[a[i]].norm == source[b[j]].norm {
                timing[a[i]] = (source[b[j]].start, source[b[j]].end)
                i += 1; j += 1
            } else if table[(i + 1) * (m + 1) + j] >= table[i * (m + 1) + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        let matched = Double(timing.count) / Double(n)

        // Per-line word ranges.
        var ranges: [Int: Range<Int>] = [:]
        for (k, word) in fileWords.enumerated() {
            if let r = ranges[word.line] { ranges[word.line] = r.lowerBound..<(k + 1) } else { ranges[word.line] = k..<(k + 1) }
        }

        // A different master can start a little earlier or later than the file. Where the file is
        // synced, nearby lines' differences say by how much; a running median ignores odd lines.
        var lineShift: [Int: TimeInterval] = [:]
        if fileIsSynced {
            for (index, line) in file.enumerated() {
                guard let r = ranges[index], let first = r.first(where: { timing[$0] != nil }), first == r.lowerBound,
                      let t = timing[first] else { continue }
                lineShift[index] = line.timestamp - t.start
            }
        }
        func shift(near index: Int) -> TimeInterval {
            let nearby = (max(0, index - 4)...min(file.count - 1, index + 4)).compactMap { lineShift[$0] }.sorted()
            if nearby.isEmpty { return 0 }
            return nearby[nearby.count / 2]
        }

        var result: [SyncedLyricLine] = []
        var previousEnd: TimeInterval = 0
        for (index, line) in file.enumerated() {
            guard let r = ranges[index], r.contains(where: { timing[$0] != nil }) else {
                // Nothing matched on this line: keep it as a plain line.
                let start = fileIsSynced ? line.timestamp : previousEnd
                result.append(SyncedLyricLine(timestamp: start, text: line.text))
                continue
            }
            let offset = fileIsSynced ? shift(near: index) : 0
            let known = r.filter { timing[$0] != nil }
            var words: [TimedWord] = []
            for k in r {
                if let t = timing[k] {
                    words.append(TimedWord(text: fileWords[k].text, start: t.start + offset, end: t.end + offset))
                    continue
                }
                // Unmatched words share the time between their matched neighbours.
                let before = known.last { $0 < k }, after = known.first { $0 > k }
                let from: TimeInterval, to: TimeInterval, slot: Int, slots: Int
                if let before, let after {
                    from = timing[before]!.end; to = max(from, timing[after]!.start)
                    slot = k - before - 1; slots = after - before - 1
                } else if let after {
                    to = timing[after]!.start; from = to - 0.25 * Double(after - r.lowerBound)
                    slot = k - r.lowerBound; slots = after - r.lowerBound
                } else {
                    from = timing[before!]!.end; to = from + 0.25 * Double(r.upperBound - before! - 1)
                    slot = k - before! - 1; slots = r.upperBound - before! - 1
                }
                let step = (to - from) / Double(max(slots, 1))
                words.append(TimedWord(text: fileWords[k].text, start: from + step * Double(slot) + offset, end: from + step * Double(slot + 1) + offset))
            }
            let start = fileIsSynced ? min(line.timestamp, words[0].start) : words[0].start
            let end = max(words.last!.end, start + 0.5)
            previousEnd = end
            result.append(SyncedLyricLine(timestamp: start, text: line.text, endTime: end, words: words))
        }
        return (result, matched)
    }

    /// "Goin'" and "going" or "Don't" and "dont" compare equal.
    private static func normalize(_ word: String) -> String {
        var w = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        if w.count > 3 && w.hasSuffix("ing") { w.removeLast() }
        return w
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
            // Skip empty lines and section headers like "[Verse 1: Mick Jenkins]".
            guard !text.isEmpty, !(text.hasPrefix("[") && text.hasSuffix("]")) else { continue }
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
