//
//  AppleMusicCatalog.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  Album editor's notes, artist banners, bios and Essential Albums from the Apple Music catalog,
//  using the same public web-player API (and token) as the motion artwork lookup. Results are
//  cached on disk so each album / artist is looked up about once a week.
//

import Foundation

nonisolated struct CatalogAlbumInfo: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var artist: String
    var artworkTemplate: String?
    var releaseDate: String?
    var notesShort: String?
    var notesStandard: String?
    var url: String?
    var trackCount: Int?

    var year: String? { releaseDate.map { String($0.prefix(4)) } }
    func artworkURL(_ size: Int) -> URL? { AppleMusicCatalog.imageURL(artworkTemplate, size: size) }
}

nonisolated struct CatalogArtistInfo: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var artworkTemplate: String?
    var bannerTemplate: String?
    var bio: String?
    var url: String?
    var essentialAlbums: [CatalogAlbumInfo]

    func artworkURL(_ size: Int) -> URL? { AppleMusicCatalog.imageURL(artworkTemplate, size: size) }
    func bannerURL(width: Int) -> URL? { AppleMusicCatalog.imageURL(bannerTemplate, width: width, height: width * 9 / 32) }
}

nonisolated final class AppleMusicCatalog: @unchecked Sendable {
    static let shared = AppleMusicCatalog()

    private struct Cache: Codable {
        var albums: [String: Stamped<CatalogAlbumInfo>] = [:]
        var artists: [String: Stamped<CatalogArtistInfo>] = [:]
    }

    private struct Stamped<Value: Codable>: Codable {
        var value: Value?
        var checked: Date
        /// Found results are refreshed weekly, misses every three days.
        var isFresh: Bool { Date().timeIntervalSince(checked) < (value == nil ? 3 : 7) * 86_400 }
    }

    private let lock = NSLock()
    private var cache = Cache()
    private var inflight: [String: Task<Void, Never>] = [:]
    private let cacheURL: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        cacheURL = caches.appendingPathComponent("apple-music-catalog.json")
        if let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode(Cache.self, from: data) {
            cache = decoded
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
    }

    // MARK: Public

    /// Cached album info without a network request (nil when it was never looked up).
    func cachedAlbum(named album: String, artist: String) -> CatalogAlbumInfo? {
        lock.withLock { cache.albums[Self.albumKey(album, artist)]?.value }
    }

    func cachedArtist(named name: String) -> CatalogArtistInfo? {
        lock.withLock { cache.artists[Self.artistKey(name)]?.value }
    }

    func album(named album: String, artist: String) async -> CatalogAlbumInfo? {
        let key = Self.albumKey(album, artist)
        if let hit = lock.withLock({ cache.albums[key] }), hit.isFresh { return hit.value }
        await once("album:" + key) { [self] in
            let found = await lookUpAlbum(album, artist: artist)
            lock.withLock { cache.albums[key] = Stamped(value: found, checked: Date()) }
        }
        return lock.withLock { cache.albums[key]?.value }
    }

    func artist(named name: String) async -> CatalogArtistInfo? {
        let key = Self.artistKey(name)
        if let hit = lock.withLock({ cache.artists[key] }), hit.isFresh { return hit.value }
        await once("artist:" + key) { [self] in
            let found = await lookUpArtist(name)
            lock.withLock { cache.artists[key] = Stamped(value: found, checked: Date()) }
        }
        return lock.withLock { cache.artists[key]?.value }
    }

    /// Fills in an artwork URL template ("…/{w}x{h}bb.jpg").
    static func imageURL(_ template: String?, size: Int) -> URL? {
        imageURL(template, width: size, height: size)
    }

    static func imageURL(_ template: String?, width: Int, height: Int) -> URL? {
        guard let template else { return nil }
        let filled = template
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")
            .replacingOccurrences(of: "{c}", with: "")
            .replacingOccurrences(of: "{f}", with: "jpg")
        return URL(string: filled)
    }

    /// Editor's notes come as light HTML (<i>, <b>, <br>); this turns them into plain text.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Lookups

    private func lookUpAlbum(_ album: String, artist: String) async -> CatalogAlbumInfo? {
        let clean = AnimatedArtworkService.normalize(album)
        guard let json = await get("search", query: ["term": "\(clean) \(artist)", "types": "albums", "limit": "15"]),
              let results = json["results"] as? [String: Any],
              let items = (results["albums"] as? [String: Any])?["data"] as? [[String: Any]] else { return nil }
        let albums = items.compactMap(Self.album(from:))
        let wantedArtist = artist.lowercased()
        let sameArtist = albums.filter { item in
            let a = item.artist.lowercased()
            return a.contains(wantedArtist) || wantedArtist.contains(a)
        }
        // Exact title first, then the title without edition suffixes.
        return sameArtist.first { $0.name.caseInsensitiveCompare(album) == .orderedSame }
            ?? sameArtist.first { AnimatedArtworkService.normalize($0.name).caseInsensitiveCompare(clean) == .orderedSame }
    }

    private func lookUpArtist(_ name: String) async -> CatalogArtistInfo? {
        guard let json = await get("search", query: ["term": name, "types": "artists", "limit": "5", "extend": "editorialArtwork"]),
              let results = json["results"] as? [String: Any],
              let items = (results["artists"] as? [String: Any])?["data"] as? [[String: Any]],
              !items.isEmpty else { return nil }
        let match = items.first { (($0["attributes"] as? [String: Any])?["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }
        guard let item = match ?? (items.count == 1 ? items.first : nil),
              let id = item["id"] as? String else { return nil }

        var artist = Self.artist(from: item) ?? CatalogArtistInfo(id: id, name: name, essentialAlbums: [])
        if let detail = await get("artists/\(id)", query: ["views": "featured-albums", "extend": "artistBio,editorialArtwork"]),
           let data = (detail["data"] as? [[String: Any]])?.first {
            if let full = Self.artist(from: data) {
                artist.bio = full.bio ?? artist.bio
                artist.bannerTemplate = full.bannerTemplate ?? artist.bannerTemplate
                artist.artworkTemplate = full.artworkTemplate ?? artist.artworkTemplate
            }
            let views = data["views"] as? [String: Any]
            let featured = (views?["featured-albums"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
            artist.essentialAlbums = featured.compactMap(Self.album(from:))
        }
        return artist
    }

    private static func album(from item: [String: Any]) -> CatalogAlbumInfo? {
        guard let id = item["id"] as? String,
              let attributes = item["attributes"] as? [String: Any],
              let name = attributes["name"] as? String else { return nil }
        let notes = attributes["editorialNotes"] as? [String: Any]
        return CatalogAlbumInfo(
            id: id,
            name: name,
            artist: attributes["artistName"] as? String ?? "",
            artworkTemplate: (attributes["artwork"] as? [String: Any])?["url"] as? String,
            releaseDate: attributes["releaseDate"] as? String,
            notesShort: (notes?["short"] as? String).map(plainText),
            notesStandard: (notes?["standard"] as? String).map(plainText),
            url: attributes["url"] as? String,
            trackCount: attributes["trackCount"] as? Int
        )
    }

    private static func artist(from item: [String: Any]) -> CatalogArtistInfo? {
        guard let id = item["id"] as? String, let attributes = item["attributes"] as? [String: Any] else { return nil }
        let editorial = attributes["editorialArtwork"] as? [String: Any]
        let banner = ["bannerUber", "superHeroWide", "centeredFullscreenBackground", "subscriptionHero"]
            .lazy.compactMap { (editorial?[$0] as? [String: Any])?["url"] as? String }.first
        return CatalogArtistInfo(
            id: id,
            name: attributes["name"] as? String ?? "",
            artworkTemplate: (attributes["artwork"] as? [String: Any])?["url"] as? String,
            bannerTemplate: banner,
            bio: (attributes["artistBio"] as? String).map(plainText),
            url: attributes["url"] as? String,
            essentialAlbums: []
        )
    }

    // MARK: Plumbing

    private func get(_ path: String, query: [String: String]) async -> [String: Any]? {
        guard let token = await AnimatedArtworkService.shared.developerToken() else { return nil }
        let storefront = (Locale.current.region?.identifier ?? "us").lowercased()
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(storefront)/\(path)")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue(AnimatedArtworkService.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            UserDefaults.standard.removeObject(forKey: "appleMusicWebToken")
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Runs one lookup per key at a time; concurrent callers wait for the same result.
    private func once(_ key: String, _ work: @escaping @Sendable () async -> Void) async {
        let task: Task<Void, Never> = lock.withLock {
            if let running = inflight[key] { return running }
            let task = Task.detached(priority: .utility) { await work() }
            inflight[key] = task
            return task
        }
        await task.value
        lock.withLock { inflight[key] = nil }
        persist()
    }

    private func persist() {
        let snapshot = lock.withLock { cache }
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private static func albumKey(_ album: String, _ artist: String) -> String { "\(artist.lowercased())|\(album.lowercased())" }
    private static func artistKey(_ name: String) -> String { name.lowercased() }
}
