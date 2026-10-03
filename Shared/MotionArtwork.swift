//
//  MotionArtwork.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  Apple Music "motion" album art. Videos saved next to the album's files win; otherwise the
//  album is looked up in the Apple Music catalog (the same public web-player API music.apple.com
//  uses) and its square / tall motion artwork is streamed. Results — including "no video" — are
//  cached per album so each album is only looked up once.
//

import Foundation

nonisolated final class AnimatedArtworkService: @unchecked Sendable {
    static let shared = AnimatedArtworkService()

    private struct Entry: Codable {
        var square: URL?
        var tall: URL?
        var checked: Date
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var inflight: [String: Task<Entry, Never>] = [:]
    private let cacheURL: URL
    private let session: URLSession

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        cacheURL = caches.appendingPathComponent("animated-artwork-v2.json")
        if let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
    }

    /// Square and tall (3:4) motion artwork for an album. `key` identifies the album in the cache;
    /// `localFolder` is checked first for videos saved next to the album's files.
    func videos(key: String, album: String, artist: String, localFolder: URL?) async -> (square: URL?, tall: URL?) {
        let local: (square: URL?, tall: URL?) = localFolder.map(Self.localVideos(in:)) ?? (nil, nil)
        if local.square != nil && local.tall != nil { return local }
        let remote = await entry(key: key, album: album, artist: artist)
        return (local.square ?? remote.square, local.tall ?? remote.tall)
    }

    private func entry(key: String, album: String, artist: String) async -> Entry {
        let task: Task<Entry, Never> = lock.withLock {
            if let cached = entries[key] {
                // Found videos are kept; "nothing found" is retried after two weeks.
                if cached.square != nil || Date().timeIntervalSince(cached.checked) < 14 * 86_400 {
                    return Task { cached }
                }
            }
            if let running = inflight[key] { return running }
            let newTask = Task.detached(priority: .utility) { [self] () -> Entry in
                let found = await self.lookUp(album: album, artist: artist)
                return Entry(square: found?.square, tall: found?.tall, checked: Date())
            }
            inflight[key] = newTask
            return newTask
        }
        let result = await task.value
        lock.withLock {
            inflight[key] = nil
            entries[key] = result
        }
        persist()
        return result
    }

    private func persist() {
        let snapshot = lock.withLock { entries }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    /// Motion artwork saved next to the album (e.g. by am-dl's "save animated artwork").
    static func localVideos(in folder: URL) -> (square: URL?, tall: URL?) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return (nil, nil) }
        let named = files.filter { url in
            guard videoExtensions.contains(url.pathExtension.lowercased()) else { return false }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains("animated") || name.contains("motion") || name == "cover" || name == "artwork" || name.contains("square") || name.contains("tall")
        }
        let tall = named.first { $0.lastPathComponent.lowercased().contains("tall") }
        let square = named.first { !$0.lastPathComponent.lowercased().contains("tall") }
        return (square, tall)
    }

    // MARK: Apple Music catalog

    private func lookUp(album: String, artist: String) async -> (square: URL?, tall: URL?)? {
        guard let token = await developerToken() else { return nil }
        let storefront = (Locale.current.region?.identifier ?? "us").lowercased()
        let cleanAlbum = Self.normalize(album)
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(storefront)/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(cleanAlbum) \(artist)"),
            URLQueryItem(name: "types", value: "albums"),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "extend", value: "editorialVideo")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            UserDefaults.standard.removeObject(forKey: "appleMusicWebToken")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let albums = (results["albums"] as? [String: Any])?["data"] as? [[String: Any]] else { return nil }

        var fallback: (URL?, URL?)?
        for item in albums {
            guard let attributes = item["attributes"] as? [String: Any],
                  let name = attributes["name"] as? String,
                  Self.normalize(name).caseInsensitiveCompare(cleanAlbum) == .orderedSame else { continue }
            guard Self.artistsMatch(attributes["artistName"] as? String ?? "", artist) else { continue }
            guard let video = attributes["editorialVideo"] as? [String: Any] else { continue }
            func stream(_ key: String) -> URL? {
                ((video[key] as? [String: Any])?["video"] as? String).flatMap(URL.init(string:))
            }
            let square = stream("motionDetailSquare") ?? stream("motionSquareVideo1x1")
            let tall = stream("motionDetailTall") ?? stream("motionTallVideo3x4")
            if square != nil { return (square, tall) }
            if fallback == nil { fallback = (square, tall) }
        }
        return fallback.map { ($0.0, $0.1) }
    }

    /// The individual artists in a credit like "Bruno Mars, Anderson .Paak & Silk Sonic".
    static func artistNames(_ credit: String) -> Set<String> {
        let folded = credit.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let separated = folded.replacingOccurrences(of: "\\s*(,|&|\\+|/|\\bfeat\\.?|\\bft\\.?|\\bfeaturing\\b|\\bwith\\b|\\band\\b|\\bx\\b)\\s*", with: "|", options: .regularExpression)
        return Set(separated.split(separator: "|").map { name in
            var n = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if n.hasPrefix("the ") { n.removeFirst(4) }
            return n
        }.filter { !$0.isEmpty })
    }

    /// True when two credits share an artist, so "Silk Sonic, Bruno Mars & Anderson .Paak" matches
    /// "Bruno Mars, Anderson .Paak & Silk Sonic", and "Kanye West" matches "Kanye West & Jay-Z".
    static func artistsMatch(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        if x.contains(y) || y.contains(x) { return true }
        return !artistNames(a).isDisjoint(with: artistNames(b))
    }

    /// Strips edition suffixes so "Graduation (Deluxe) - Single" style names still match.
    static func normalize(_ name: String) -> String {
        var text = name
        for suffix in [" - Single", " - EP"] where text.hasSuffix(suffix) { text = String(text.dropLast(suffix.count)) }
        text = text.replacingOccurrences(of: "\\s*[\\(\\[](Deluxe|Explicit|Clean|Remastered|Expanded|Bonus)[^\\)\\]]*[\\)\\]]", with: "", options: [.regularExpression, .caseInsensitive])
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The public token music.apple.com's web player ships in its JavaScript bundle.
    func developerToken() async -> String? {
        let defaults = UserDefaults.standard
        if let cached = defaults.string(forKey: "appleMusicWebToken"),
           let expiry = Self.expiry(of: cached), expiry.timeIntervalSinceNow > 86_400 {
            return cached
        }
        var request = URLRequest(url: URL(string: "https://music.apple.com/us/browse")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (pageData, _) = try? await session.data(for: request),
              let html = String(data: pageData, encoding: .utf8),
              let scriptRange = html.range(of: "/assets/index[^\"']*\\.js", options: .regularExpression),
              let scriptURL = URL(string: "https://music.apple.com" + html[scriptRange]) else { return nil }
        var scriptRequest = URLRequest(url: scriptURL)
        scriptRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (scriptData, _) = try? await session.data(for: scriptRequest),
              let script = String(data: scriptData, encoding: .utf8),
              let tokenRange = script.range(of: "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}", options: .regularExpression) else { return nil }
        let token = String(script[tokenRange])
        defaults.set(token, forKey: "appleMusicWebToken")
        return token
    }

    private static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
