//
//  LibraryImporter.swift
//  Mesh Player
//
//  Imports music from the Apple Music (Music.app) library, from folders, and from
//  dropped files. All file and metadata work happens off the main thread and results
//  are merged into the library in batches so the UI fills in while an import runs.
//

import AppKit
import AVFoundation
import Combine
import iTunesLibrary

// MARK: - Paths

nonisolated enum MeshPaths {
    /// The user's real home folder (inside the sandbox `NSHomeDirectory()` points at the container).
    static let realHome: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    static var musicFolder: URL { realHome.appendingPathComponent("Music", isDirectory: true) }
    static var meshLibraryFolder: URL { musicFolder.appendingPathComponent("Mesh Player", isDirectory: true) }

    /// Root of Music.app's media folder (contains Music/, "Automatically Add to Music", …).
    static var appleMusicMediaRoot: URL? {
        let candidates = ["Music/Media.localized", "Music/Media", "iTunes/iTunes Media"]
            .map { musicFolder.appendingPathComponent($0, isDirectory: true) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Where Music.app keeps its local song files, when it exists.
    static var appleMusicMediaFolder: URL? {
        guard let root = appleMusicMediaRoot else { return nil }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        return FileManager.default.fileExists(atPath: music.path) ? music : root
    }

    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "flac", "alac", "caf", "mp4"]

    static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// True when the app can read the file on future launches without a new user grant.
    static func isInsideMusicFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let music = musicFolder.resolvingSymlinksInPath().standardizedFileURL.path
        return path == music || path.hasPrefix(music + "/")
    }
}

// MARK: - Metadata

nonisolated struct CodecInfo: Sendable {
    var codec = ""
    var isAtmos = false
    var isLossless = false
    var sampleRate: Double?
    var channels: Int?
    var bitDepth: Int?
    var bitRate: Int?
}

nonisolated enum TrackMetadataReader {
    static func probeCodec(_ asset: AVURLAsset) async -> CodecInfo? {
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        var info = CodecInfo()
        if let (descriptions, dataRate) = try? await audioTrack.load(.formatDescriptions, .estimatedDataRate) {
            if dataRate > 0 { info.bitRate = Int((Double(dataRate) / 1000).rounded()) }
            for desc in descriptions {
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                info.codec = fourCC(subType)
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    if asbd.mSampleRate > 0 { info.sampleRate = asbd.mSampleRate }
                    if asbd.mChannelsPerFrame > 0 { info.channels = Int(asbd.mChannelsPerFrame) }
                    if asbd.mBitsPerChannel > 0 { info.bitDepth = Int(asbd.mBitsPerChannel) }
                    if subType == kAudioFormatAppleLossless {
                        switch asbd.mFormatFlags {
                        case 1: info.bitDepth = 16
                        case 2: info.bitDepth = 20
                        case 3: info.bitDepth = 24
                        case 4: info.bitDepth = 32
                        default: break
                        }
                    }
                }
            }
        }
        let codec = info.codec
        info.isAtmos = ["ec-3", "ac-3", "ac-4", "mlpa", "ec+3"].contains(codec)
        info.isLossless = ["alac", "flac", "lpcm", "sowt", "twos", "in24", "in32", "fl32"].contains(codec)
        return info
    }

    static func formatLabel(_ info: CodecInfo?, fileExtension ext: String) -> String {
        guard let info else {
            if ["flac", "wav", "aif", "aiff", "alac"].contains(ext) { return "Lossless" }
            return ext == "mp3" ? "MP3" : "AAC"
        }
        if info.isAtmos { return "Dolby Atmos" }
        if info.isLossless {
            let hiRes = (info.sampleRate ?? 44_100) > 48_000 || (info.bitDepth ?? 16) >= 24
            return hiRes ? "Hi-Res Lossless" : "Lossless"
        }
        let name = info.codec == ".mp3" || ext == "mp3" ? "MP3" : "AAC"
        if let kbps = info.bitRate, kbps > 0 {
            let standard = [96, 128, 160, 192, 256, 320].min(by: { abs($0 - kbps) < abs($1 - kbps) }) ?? kbps
            return "\(name) \(standard)kbps"
        }
        return name
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    }

    private static func year(from string: String?) -> Int? {
        guard let string, string.count >= 4, let y = Int(string.prefix(4)), y > 1000 else { return nil }
        return y
    }

    /// Parses "3", "3/12" strings or the 8-byte iTunes `trkn`/`disk` payload.
    private static func indexNumber(_ item: AVMetadataItem) async -> Int? {
        if let data = try? await item.load(.dataValue), data.count >= 4 {
            let value = Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
            if value > 0 { return value }
        }
        if let number = try? await item.load(.numberValue), number.intValue > 0 { return number.intValue }
        if let string = try? await item.load(.stringValue),
           let first = string.split(separator: "/").first,
           let value = Int(first.trimmingCharacters(in: .whitespaces)), value > 0 {
            return value
        }
        return nil
    }

    /// Strips "01 ", "1-01 ", "01. " prefixes from file names.
    static func titleFromFileName(_ url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        let pattern = "^\\s*(\\d+[-_.]\\d+|\\d+)\\s*[-_.]?\\s+"
        let cleaned = raw.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return cleaned.isEmpty ? raw : cleaned
    }

    static func read(url: URL, covers: CoverFinder? = nil) async -> LocalTrack {
        let asset = AVURLAsset(url: url)
        let ext = url.pathExtension.lowercased()

        // Folder layout hints: .../Artist/Album/NN Title.ext
        let albumFolder = url.deletingLastPathComponent()
        let artistFolder = albumFolder.deletingLastPathComponent()
        var title = titleFromFileName(url)
        var artist = artistFolder.lastPathComponent.isEmpty ? "Unknown Artist" : artistFolder.lastPathComponent
        var album = albumFolder.lastPathComponent.isEmpty ? "Unknown Album" : albumFolder.lastPathComponent
        if ["Music", "Media", "Media.localized", "Downloads", "Desktop"].contains(artist) { artist = "Unknown Artist" }
        if ["Music", "Media", "Media.localized", "Downloads", "Desktop"].contains(album) { album = "Unknown Album" }

        var albumArtist: String?
        var genre = ""
        var yearValue: Int?
        var trackNumber = 0
        var discNumber = 1
        var copyright: String?
        var publisher: String?
        var lyrics = ""
        var explicit = false

        let items = (try? await asset.load(.metadata)) ?? []
        for item in items {
            guard let identifier = item.identifier else { continue }
            switch identifier {
            case .commonIdentifierTitle, .iTunesMetadataSongName, .id3MetadataTitleDescription, .quickTimeMetadataTitle:
                if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
            case .commonIdentifierArtist, .iTunesMetadataArtist, .id3MetadataLeadPerformer, .quickTimeMetadataArtist:
                if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
            case .commonIdentifierAlbumName, .iTunesMetadataAlbum, .id3MetadataAlbumTitle, .quickTimeMetadataAlbum:
                if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
            case .iTunesMetadataAlbumArtist, .id3MetadataBand:
                if let v = try? await item.load(.stringValue), !v.isEmpty { albumArtist = v }
            case .iTunesMetadataUserGenre, .id3MetadataContentType, .quickTimeMetadataGenre:
                if let v = try? await item.load(.stringValue), !v.isEmpty { genre = v }
            case .iTunesMetadataReleaseDate, .id3MetadataYear, .id3MetadataRecordingTime, .commonIdentifierCreationDate, .quickTimeMetadataYear:
                if yearValue == nil { yearValue = year(from: try? await item.load(.stringValue)) }
            case .iTunesMetadataTrackNumber, .id3MetadataTrackNumber:
                if let n = await indexNumber(item) { trackNumber = n }
            case .iTunesMetadataDiscNumber, .id3MetadataPartOfASet:
                if let n = await indexNumber(item) { discNumber = n }
            case .iTunesMetadataCopyright, .id3MetadataCopyright, .commonIdentifierCopyrights:
                if copyright == nil, let v = try? await item.load(.stringValue), !v.isEmpty { copyright = v }
            case .iTunesMetadataPublisher, .id3MetadataPublisher, .commonIdentifierPublisher:
                if let v = try? await item.load(.stringValue), !v.isEmpty { publisher = v }
            case .iTunesMetadataLyrics, .id3MetadataUnsynchronizedLyric:
                if let v = try? await item.load(.stringValue), !v.isEmpty { lyrics = v }
            case .iTunesMetadataContentRating:
                explicit = await isExplicitRating(item)
            default:
                break
            }
        }

        // Companion .lrc / .txt lyrics next to the audio file win over embedded plain lyrics.
        for sidecarExt in ["lrc", "txt"] {
            let sidecar = url.deletingPathExtension().appendingPathExtension(sidecarExt)
            if let content = try? String(contentsOf: sidecar, encoding: .utf8), !content.isEmpty {
                lyrics = content
                break
            }
        }

        var duration = (try? await asset.load(.duration).seconds) ?? 0
        if duration.isNaN || duration.isInfinite { duration = 0 }
        let codec = await probeCodec(asset)

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .addedToDirectoryDateKey])
        let fileSize = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Unknown"
        let dateAdded = values?.addedToDirectoryDate ?? values?.creationDate ?? Date()

        var track = LocalTrack(
            title: title,
            artist: artist,
            album: album,
            genre: genre.isEmpty ? "Unknown Genre" : genre,
            duration: duration,
            fileURL: url,
            coverImageName: codec?.isAtmos == true ? "sparkles" : "music.note",
            localCoverURL: covers?.cover(in: albumFolder),
            dateAdded: dateAdded,
            isAtmos: codec?.isAtmos ?? false,
            fileSize: fileSize,
            lyrics: lyrics,
            format: formatLabel(codec, fileExtension: ext)
        )
        track.discNumber = max(1, discNumber)
        track.trackNumber = trackNumber
        track.copyright = copyright
        track.publisher = publisher
        track.isExplicit = explicit
        track.year = yearValue
        track.albumArtist = albumArtist
        track.bitRate = codec?.bitRate
        track.sampleRate = codec?.sampleRate
        track.channels = codec?.channels
        track.bitDepth = codec?.bitDepth
        return track
    }
}

extension TrackMetadataReader {
    /// iTunes' "rtng" atom: 1 (and 4, used by older files) is explicit, 2 is clean.
    static func isExplicitRating(_ item: AVMetadataItem) async -> Bool {
        if let n = try? await item.load(.numberValue) { return n.intValue == 1 || n.intValue == 4 }
        if let data = try? await item.load(.dataValue), let first = data.first { return first == 1 || first == 4 }
        return false
    }

    /// Whether a file is tagged explicit.
    static func isExplicit(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return false }
        for item in items where item.identifier == .iTunesMetadataContentRating {
            return await isExplicitRating(item)
        }
        return false
    }

    /// Reads just the copyright / ℗ line from a file's tags.
    static func copyright(of url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return nil }
        for item in items {
            guard let id = item.identifier,
                  id == .iTunesMetadataCopyright || id == .id3MetadataCopyright || id == .commonIdentifierCopyrights || id == .quickTimeMetadataCopyright else { continue }
            if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
        }
        return nil
    }
}

/// Finds an album's copyright line: the files' own tags first, then the iTunes catalog.
nonisolated final class CopyrightResolver: @unchecked Sendable {
    static let shared = CopyrightResolver()
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var missing = Set<String>()

    func copyright(for rep: LocalTrack, in tracks: [LocalTrack]) async -> String? {
        let key = rep.artworkKey
        if let hit = lock.withLock({ cache[key] }) { return hit }
        if lock.withLock({ missing.contains(key) }) { return nil }

        for track in tracks.prefix(3) {
            if let url = track.fileURL, let found = await TrackMetadataReader.copyright(of: url) {
                lock.withLock { cache[key] = found }
                return found
            }
        }
        if let found = await Self.lookUpOnline(album: rep.album, artist: rep.albumArtist ?? rep.artist) {
            lock.withLock { cache[key] = found }
            return found
        }
        lock.withLock { _ = missing.insert(key) }
        return nil
    }

    private static func lookUpOnline(album: String, artist: String) async -> String? {
        let cleanAlbum = AnimatedArtworkService.normalize(album)
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(cleanAlbum) \(artist)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        let wantedArtist = artist.lowercased()
        let exact = results.first { item in
            let name = AnimatedArtworkService.normalize(item["collectionName"] as? String ?? "")
            let itemArtist = (item["artistName"] as? String ?? "").lowercased()
            return name.caseInsensitiveCompare(cleanAlbum) == .orderedSame && (itemArtist.contains(wantedArtist) || wantedArtist.contains(itemArtist))
        }
        let byArtist = results.first { item in
            let itemArtist = (item["artistName"] as? String ?? "").lowercased()
            return itemArtist.contains(wantedArtist) || wantedArtist.contains(itemArtist)
        }
        return (exact ?? byArtist)?["copyright"] as? String
    }

    /// Reads the explicit tag of songs that haven't been checked yet (libraries imported before
    /// it was read), off the main thread, and stores the results in one update.
    @MainActor func backfillExplicit(_ state: AppStateManager) {
        let pending = state.tracks.compactMap { t in t.isExplicit == nil ? t.fileURL.map { (t.id, $0) } : nil }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .background) {
            var flags: [UUID: Bool] = [:]
            for chunkStart in stride(from: 0, to: pending.count, by: 24) {
                let chunk = pending[chunkStart..<min(chunkStart + 24, pending.count)]
                await withTaskGroup(of: (UUID, Bool).self) { group in
                    for (id, url) in chunk { group.addTask { (id, await TrackMetadataReader.isExplicit(url)) } }
                    for await (id, value) in group { flags[id] = value }
                }
            }
            let result = flags
            await MainActor.run { state.setExplicitFlags(result) }
        }
    }

    /// Reads copyright tags for albums that don't have one yet, off the main thread, and
    /// stores them in one library update. Runs after launch and after imports.
    @MainActor func backfillFromTags(_ state: AppStateManager) {
        var seen = Set<String>()
        var reps: [(album: String, url: URL)] = []
        for track in state.tracks where (track.copyright ?? "").isEmpty {
            guard let url = track.fileURL, seen.insert(track.album).inserted else { continue }
            reps.append((track.album, url))
        }
        guard !reps.isEmpty else { return }
        Task.detached(priority: .background) {
            var found: [String: String] = [:]
            for chunkStart in stride(from: 0, to: reps.count, by: 16) {
                let chunk = reps[chunkStart..<min(chunkStart + 16, reps.count)]
                await withTaskGroup(of: (String, String?).self) { group in
                    for rep in chunk {
                        group.addTask { (rep.album, await TrackMetadataReader.copyright(of: rep.url)) }
                    }
                    for await (album, value) in group {
                        if let value { found[album] = value }
                    }
                }
            }
            let result = found
            guard !result.isEmpty else { return }
            await MainActor.run { state.setCopyrights(result) }
        }
    }
}

/// Finds `cover.jpg` style images in album folders, caching one lookup per folder.
nonisolated final class CoverFinder: @unchecked Sendable {
    private var cache: [String: URL?] = [:]
    private let lock = NSLock()
    private static let names = ["cover", "folder", "front", "artwork", "albumart", "album"]
    private static let exts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]

    func cover(in folder: URL) -> URL? {
        if let hit = lock.withLock({ cache[folder.path] }) { return hit }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let images = files.filter { Self.exts.contains($0.pathExtension.lowercased()) }
        let preferred = images.first { Self.names.contains($0.deletingPathExtension().lastPathComponent.lowercased()) }
        let result = preferred ?? (images.count == 1 ? images.first : nil)
        lock.withLock { cache[folder.path] = result }
        return result
    }
}

// MARK: - File organisation

nonisolated enum LibraryFiles {
    static func sanitize(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        let illegal = CharacterSet(charactersIn: "/:\\?*\"<>|")
        let cleaned = trimmed.components(separatedBy: illegal).joined(separator: "_")
        return String(cleaned.prefix(120))
    }

    /// Copies (or moves) a file into ~/Music/Mesh Player/Media/Music/Artist/Album and returns the new URL.
    static func organize(_ source: URL, track: LocalTrack, move: Bool) throws -> URL {
        let fm = FileManager.default
        let media = MeshPaths.meshLibraryFolder.appendingPathComponent("Media/Music", isDirectory: true)
        let albumDir = media
            .appendingPathComponent(sanitize(track.albumArtist ?? track.artist, fallback: "Unknown Artist"), isDirectory: true)
            .appendingPathComponent(sanitize(track.album, fallback: "Unknown Album"), isDirectory: true)
        try fm.createDirectory(at: albumDir, withIntermediateDirectories: true)

        let number = track.trackNumber > 0 ? String(format: "%02d ", track.trackNumber) : ""
        let baseName = number + sanitize(track.title, fallback: "Unknown Track")
        let ext = source.pathExtension
        var destination = albumDir.appendingPathComponent(baseName).appendingPathExtension(ext)

        if destination.standardizedFileURL.path == source.standardizedFileURL.path { return source }

        let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            // Same file imported again: reuse the existing copy instead of duplicating it.
            let existingSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if existingSize != nil && existingSize == sourceSize {
                if move { try? fm.removeItem(at: source) }
                return destination
            }
            destination = albumDir.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(ext)
            counter += 1
        }

        if move {
            do {
                try fm.moveItem(at: source, to: destination)
            } catch {
                try fm.copyItem(at: source, to: destination)
                try? fm.removeItem(at: source)
            }
        } else {
            try fm.copyItem(at: source, to: destination)
        }

        // Bring sidecar lyrics along.
        for sidecarExt in ["lrc", "txt"] {
            let sidecar = source.deletingPathExtension().appendingPathExtension(sidecarExt)
            if fm.fileExists(atPath: sidecar.path) {
                try? fm.copyItem(at: sidecar, to: destination.deletingPathExtension().appendingPathExtension(sidecarExt))
            }
        }
        return destination
    }

    /// Motion artwork videos saved alongside albums (they are .mp4 files but not songs).
    static func isArtworkVideo(_ url: URL) -> Bool {
        guard ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) else { return false }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return name.contains("animated") || name.contains("motion") || name.contains("artwork")
            || name == "cover" || name == "square" || name == "tall" || name.hasPrefix("square_") || name.hasPrefix("tall_")
    }

    static func collectAudioFiles(in folder: URL, includeArtworkVideos: Bool = false) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where MeshPaths.isAudioFile(url) || (includeArtworkVideos && isArtworkVideo(url)) {
            if !includeArtworkVideos && isArtworkVideo(url) { continue }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }
}

// MARK: - Importer

/// What to bring over from the Music app. Persisted so the next import remembers the choices.
nonisolated struct AppleMusicImportOptions: Codable, Equatable, Sendable {
    var songs = true
    var musicVideos = false
    var playlists = true
    /// nil imports every playlist; otherwise only these names.
    var selectedPlaylists: Set<String>? = nil
    var lovedSongs = true
    var playCounts = true
    var dateAdded = true
    var scanMediaFolder = true
    var hideImportedPlaylistSongs = false

    static var saved: AppleMusicImportOptions {
        get {
            guard let data = UserDefaults.standard.data(forKey: "appleMusicImportOptions"),
                  let value = try? JSONDecoder().decode(AppleMusicImportOptions.self, from: data) else { return AppleMusicImportOptions() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "appleMusicImportOptions") }
        }
    }
}

/// A quick look at the Music library, shown in the import options sheet.
nonisolated struct AppleMusicPreview: Sendable {
    var downloadedSongs = 0
    var musicVideos = 0
    var cloudOnly = 0
    var protected = 0
    var lovedSongs = 0
    var playedSongs = 0
    var playlists: [(name: String, count: Int)] = []
    var error: String?
}

struct ImportSummary: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let isError: Bool
}

final class LibraryImporter: ObservableObject {
    static let shared = LibraryImporter()

    @Published private(set) var isRunning = false
    @Published private(set) var title = ""
    @Published private(set) var detail = ""
    @Published private(set) var processed = 0
    @Published private(set) var total = 0
    @Published var summary: ImportSummary?

    private var currentTask: Task<Void, Never>?
    private var autoAddInFlight = Set<String>()

    var progress: Double? {
        total > 0 ? min(1, Double(processed) / Double(total)) : nil
    }

    func cancel() {
        currentTask?.cancel()
    }

    private func begin(_ title: String, detail: String = "") {
        isRunning = true
        self.title = title
        self.detail = detail
        processed = 0
        total = 0
        summary = nil
    }

    private func finish(_ summary: ImportSummary) {
        isRunning = false
        total = 0
        processed = 0
        self.summary = summary
        currentTask = nil
    }

    // MARK: Folder import

    func chooseFolderAndImport(into state: AppStateManager) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .folder]
        panel.title = "Import Music"
        panel.prompt = "Import"
        panel.message = "Choose folders or audio files. Files inside your Music folder are added in place; anything else is copied into ~/Music/Mesh Player."
        panel.directoryURL = MeshPaths.appleMusicMediaRoot ?? MeshPaths.musicFolder
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated {
                self?.importURLs(urls, into: state)
            }
        }
    }

    func importURLs(_ urls: [URL], into state: AppStateManager, moveIntoLibrary: Bool = false) {
        guard !urls.isEmpty else { return }
        guard !isRunning else {
            summary = ImportSummary(title: "Import already running", message: "Wait for the current import to finish, then try again.", isError: true)
            return
        }
        let label = urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : "\(urls.count) items"
        begin("Importing \(label)", detail: "Scanning for audio files…")

        currentTask = Task { [weak self] in
            guard let self else { return }
            let scoped = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, didStart) in scoped where didStart { url.stopAccessingSecurityScopedResource() } }

            let files = await Task.detached(priority: .userInitiated) { () -> [URL] in
                var result: [URL] = []
                for url in urls {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        result.append(contentsOf: LibraryFiles.collectAudioFiles(in: url))
                    } else if MeshPaths.isAudioFile(url) {
                        result.append(url)
                    }
                }
                return result
            }.value

            guard !files.isEmpty else {
                self.finish(ImportSummary(title: "No music found", message: "No supported audio files were found in \(label). Supported: \(MeshPaths.audioExtensions.sorted().joined(separator: ", ")).", isError: true))
                return
            }

            let (added, updated, failed) = await self.processFiles(files, into: state, moveIntoLibrary: moveIntoLibrary)
            CopyrightResolver.shared.backfillFromTags(state)
            CopyrightResolver.shared.backfillExplicit(state)
            if Task.isCancelled {
                self.finish(ImportSummary(title: "Import cancelled", message: "Added \(added) songs before stopping.", isError: false))
            } else {
                var message = "\(added) new, \(updated) updated"
                if failed > 0 { message += ", \(failed) couldn't be read" }
                self.finish(ImportSummary(title: "Import complete", message: message, isError: added + updated == 0 && failed > 0))
            }
        }
    }

    /// Reads metadata concurrently and merges results into the library in batches.
    private func processFiles(_ files: [URL], into state: AppStateManager, moveIntoLibrary: Bool) async -> (Int, Int, Int) {
        total = files.count
        detail = "Reading tags…"
        let covers = CoverFinder()
        var added = 0, updated = 0, failed = 0
        var pending: [LocalTrack] = []
        let chunkSize = 32

        for start in stride(from: 0, to: files.count, by: chunkSize) {
            if Task.isCancelled { break }
            let chunk = Array(files[start..<min(start + chunkSize, files.count)])
            let results = await Task.detached(priority: .userInitiated) { () -> [LocalTrack?] in
                await withTaskGroup(of: (Int, LocalTrack?).self) { group in
                    for (i, file) in chunk.enumerated() {
                        group.addTask {
                            (i, await Self.importFile(file, covers: covers, moveIntoLibrary: moveIntoLibrary))
                        }
                    }
                    var ordered = [LocalTrack?](repeating: nil, count: chunk.count)
                    for await (i, track) in group { ordered[i] = track }
                    return ordered
                }
            }.value

            failed += results.filter { $0 == nil }.count
            pending.append(contentsOf: results.compactMap { $0 })
            processed = min(files.count, start + chunk.count)
            detail = "\(processed) of \(files.count) files"

            if pending.count >= 160 || processed == files.count {
                let result = state.mergeImportedTracks(pending)
                added += result.added
                updated += result.updated
                pending.removeAll(keepingCapacity: true)
            }
        }
        if !pending.isEmpty {
            let result = state.mergeImportedTracks(pending)
            added += result.added
            updated += result.updated
        }
        return (added, updated, failed)
    }

    nonisolated private static func importFile(_ url: URL, covers: CoverFinder, moveIntoLibrary: Bool) async -> LocalTrack? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        var track = await TrackMetadataReader.read(url: url, covers: covers)
        guard track.duration > 0 else { return nil }

        // Files outside ~/Music can't be re-opened after relaunch in the sandbox, so keep a copy.
        let needsCopy = moveIntoLibrary || !MeshPaths.isInsideMusicFolder(url)
        if needsCopy {
            do {
                let destination = try LibraryFiles.organize(url, track: track, move: moveIntoLibrary)
                track.fileURL = destination
                if let cover = track.localCoverURL, !MeshPaths.isInsideMusicFolder(cover) {
                    let copiedCover = destination.deletingLastPathComponent().appendingPathComponent("cover." + cover.pathExtension)
                    if !FileManager.default.fileExists(atPath: copiedCover.path) {
                        try? FileManager.default.copyItem(at: cover, to: copiedCover)
                    }
                    track.localCoverURL = FileManager.default.fileExists(atPath: copiedCover.path) ? copiedCover : nil
                }
            } catch {
                print("Mesh import: couldn't copy \(url.lastPathComponent) into the library: \(error.localizedDescription)")
            }
        }
        return track
    }

    // MARK: Downloads

    /// Imports finished am-dl downloads (moving them into the Mesh library), waiting for any
    /// running import to finish first. Returns the imported songs.
    func importDownloads(_ files: [URL], into state: AppStateManager) async -> [LocalTrack] {
        while isRunning { try? await Task.sleep(for: .milliseconds(400)) }
        isRunning = true
        title = "Adding downloaded music"
        detail = ""
        defer {
            isRunning = false
            total = 0
            processed = 0
        }
        let covers = CoverFinder()
        let tracks = await Task.detached(priority: .userInitiated) { () -> [LocalTrack] in
            await withTaskGroup(of: LocalTrack?.self) { group in
                for file in files { group.addTask { await Self.importFile(file, covers: covers, moveIntoLibrary: true) } }
                var result: [LocalTrack] = []
                for await track in group { if let track { result.append(track) } }
                return result
            }
        }.value
        guard !tracks.isEmpty else { return [] }
        state.mergeImportedTracks(tracks)
        CopyrightResolver.shared.backfillFromTags(state)
        summary = ImportSummary(title: "Added \(Fmt.songs(tracks.count))", message: tracks.count == 1 ? "\(tracks[0].title) — \(tracks[0].artist)" : "\(tracks[0].album) — \(tracks[0].albumArtist ?? tracks[0].artist)", isError: false)
        return tracks
    }

    // MARK: Automatically Add folder

    func importFromAutoAddFolder(_ urls: [URL], into state: AppStateManager) {
        let fresh = urls.filter { !autoAddInFlight.contains($0.path) }
        guard !fresh.isEmpty, !isRunning else { return }
        fresh.forEach { autoAddInFlight.insert($0.path) }
        currentTask = Task { [weak self] in
            guard let self else { return }
            let (added, _, _) = await self.processFiles(fresh, into: state, moveIntoLibrary: true)
            fresh.forEach { self.autoAddInFlight.remove($0.path) }
            self.isRunning = false
            self.total = 0
            if added > 0 {
                self.summary = ImportSummary(title: "Added \(added) song\(added == 1 ? "" : "s")", message: "From the Automatically Add to Mesh Player folder.", isError: false)
            }
        }
    }

    // MARK: Apple Music library

    nonisolated private struct AppleMusicSong: Sendable {
        let persistentID: String
        var track: LocalTrack
    }

    nonisolated private struct AppleMusicPayload: Sendable {
        var songs: [AppleMusicSong] = []
        var playlists: [(name: String, id: String, ids: [String])] = []
        var lovedIDs = Set<String>()
        var cloudOnly = 0
        var protected = 0
        var missing = 0
    }

    nonisolated private enum AppleMusicError: Error {
        case unavailable(String)
    }

    /// Reads the Music library just far enough to describe it (counts and playlist names).
    func previewAppleMusicLibrary() async -> AppleMusicPreview {
        await Task.detached(priority: .userInitiated) { () -> AppleMusicPreview in
            var preview = AppleMusicPreview()
            let library: ITLibrary
            do {
                library = try ITLibrary(apiVersion: "1.0")
            } catch {
                preview.error = "Mesh Player needs permission to read your Music library. Allow it in System Settings › Privacy & Security › Media & Apple Music."
                return preview
            }
            let fm = FileManager.default
            var songIDs = Set<String>()
            for item in library.allMediaItems where item.mediaKind == .kindSong || item.mediaKind == .kindMusicVideo {
                if item.isDRMProtected { preview.protected += 1; continue }
                guard item.locationType == .file, let location = item.location, fm.fileExists(atPath: location.path) else { preview.cloudOnly += 1; continue }
                guard MeshPaths.isAudioFile(location) else { preview.protected += 1; continue }
                if item.mediaKind == .kindMusicVideo { preview.musicVideos += 1 } else { preview.downloadedSongs += 1 }
                if item.playCount > 0 { preview.playedSongs += 1 }
                songIDs.insert(item.persistentID.stringValue)
            }
            for playlist in library.allPlaylists {
                if playlist.distinguishedKind == .kindLovedSongs {
                    preview.lovedSongs = playlist.items.filter { songIDs.contains($0.persistentID.stringValue) }.count
                    continue
                }
                guard !playlist.isPrimary, playlist.isVisible, playlist.distinguishedKind == .kindNone,
                      playlist.kind == .regular || playlist.kind == .smart else { continue }
                let count = playlist.items.filter { songIDs.contains($0.persistentID.stringValue) }.count
                if count > 0 { preview.playlists.append((playlist.name, count)) }
            }
            return preview
        }.value
    }

    func importAppleMusicLibrary(into state: AppStateManager, options: AppleMusicImportOptions = .saved) {
        guard !isRunning else { return }
        begin("Importing Apple Music Library", detail: "Opening your Music library…")

        currentTask = Task { [weak self] in
            guard let self else { return }
            var added = 0, updated = 0, unreadable = 0
            var notes: [String] = []
            var libraryError: String?

            // Phase 1: the Music app's own catalog (metadata, play counts, loved songs, playlists).
            let loaded: Result<AppleMusicPayload, Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try Self.readAppleMusicLibrary(options: options)) } catch { return .failure(error) }
            }.value

            switch loaded {
            case .failure(let error):
                if case AppleMusicError.unavailable(let text) = error { libraryError = text } else { libraryError = error.localizedDescription }
            case .success(var payload):
                if payload.cloudOnly > 0 { notes.append("\(payload.cloudOnly) cloud-only songs skipped") }
                if payload.protected > 0 { notes.append("\(payload.protected) DRM-protected songs skipped") }
                if payload.missing > 0 { notes.append("\(payload.missing) files missing on disk") }

                // Probe codecs (Atmos / lossless / bitrate) concurrently, merging as we go.
                self.total = payload.songs.count
                self.detail = "Analyzing audio formats…"
                let chunkSize = 64
                for start in stride(from: 0, to: payload.songs.count, by: chunkSize) {
                    if Task.isCancelled { break }
                    let range = start..<min(start + chunkSize, payload.songs.count)
                    let chunk = Array(payload.songs[range])
                    let probed = await Task.detached(priority: .userInitiated) { () -> [LocalTrack] in
                        await withTaskGroup(of: (Int, LocalTrack).self) { group in
                            for (i, song) in chunk.enumerated() {
                                group.addTask { (i, await Self.enrich(song.track)) }
                            }
                            var ordered = chunk.map(\.track)
                            for await (i, track) in group { ordered[i] = track }
                            return ordered
                        }
                    }.value
                    for (offset, track) in probed.enumerated() { payload.songs[start + offset].track = track }
                    let result = state.mergeImportedTracks(probed)
                    added += result.added
                    updated += result.updated
                    self.processed = range.upperBound
                    self.detail = "\(self.processed) of \(payload.songs.count) songs"
                }

                // Playlists, resolved against the (possibly pre-existing) library tracks.
                var byPersistentID: [String: LocalTrack] = [:]
                var byPath: [String: LocalTrack] = [:]
                for t in state.tracks {
                    if let pid = t.persistentID { byPersistentID[pid] = t }
                    if let p = t.fileURL?.path { byPath[p] = t }
                }
                let songPaths = Dictionary(payload.songs.map { ($0.persistentID, $0.track.fileURL?.path ?? "") }, uniquingKeysWith: { a, _ in a })
                let playlists: [Playlist] = payload.playlists.compactMap { entry in
                    let tracks = entry.ids.compactMap { id in byPersistentID[id] ?? songPaths[id].flatMap { byPath[$0] } }
                    guard !tracks.isEmpty else { return nil }
                    var playlist = Playlist(name: entry.name, description: "Imported from Apple Music", isImported: true, playlistTracks: tracks.map { PlaylistTrack(track: $0) })
                    playlist.appleMusicID = entry.id
                    playlist.dateCreated = Date()
                    if options.hideImportedPlaylistSongs { playlist.excludeFromLibrary = true }
                    return playlist
                }
                state.mergeImportedPlaylists(playlists)
                if !playlists.isEmpty { notes.insert("\(playlists.count) playlists", at: 0) }
            }

            // Phase 2: audio files in the Music media folder that the Music app doesn't list
            // (for example Dolby Atmos .mp4 files it refused to import).
            if !Task.isCancelled, options.scanMediaFolder, options.songs, let root = MeshPaths.appleMusicMediaRoot {
                self.total = 0
                self.processed = 0
                self.detail = "Checking your Music folder for other files…"
                let known = Set(state.tracks.compactMap { $0.fileURL?.standardizedFileURL.path })
                let extra = await Task.detached(priority: .userInitiated) {
                    LibraryFiles.collectAudioFiles(in: root).filter { !known.contains($0.standardizedFileURL.path) }
                }.value
                if !extra.isEmpty {
                    let (a, u, f) = await self.processFiles(extra, into: state, moveIntoLibrary: false)
                    added += a
                    updated += u
                    unreadable += f
                    if a > 0 { notes.append("\(a) found directly in your Music folder") }
                }
            }

            if unreadable > 0 { notes.append("\(unreadable) files couldn't be read") }
            CopyrightResolver.shared.backfillFromTags(state)
            let cancelled = Task.isCancelled
            if added + updated == 0, let libraryError, !cancelled {
                self.finish(ImportSummary(title: "Couldn't read your Apple Music library", message: libraryError, isError: true))
            } else if added + updated == 0 && !cancelled {
                let detail = notes.isEmpty ? "" : " (" + notes.joined(separator: ", ") + ")"
                self.finish(ImportSummary(title: "Nothing new to import", message: "No downloaded, DRM-free songs were found\(detail). Download songs in Music first, or use Import Folder for other music.", isError: true))
            } else {
                var message = "\(added) new, \(updated) updated"
                if !notes.isEmpty { message += " · " + notes.joined(separator: " · ") }
                if libraryError != nil { message += " · Music library access was denied, so only files in your Music folder were imported" }
                self.finish(ImportSummary(title: cancelled ? "Import cancelled" : "Apple Music library imported", message: message, isError: false))
            }
        }
    }

    nonisolated private static func readAppleMusicLibrary(options: AppleMusicImportOptions) throws -> AppleMusicPayload {
        let library: ITLibrary
        do {
            library = try ITLibrary(apiVersion: "1.0")
        } catch {
            throw AppleMusicError.unavailable("Mesh Player needs permission to read your Music library. Allow it in System Settings › Privacy & Security › Media & Apple Music, then try again. (\(error.localizedDescription))")
        }

        var payload = AppleMusicPayload()
        let fm = FileManager.default

        for item in library.allMediaItems {
            let wanted = (item.mediaKind == .kindSong && options.songs) || (item.mediaKind == .kindMusicVideo && options.musicVideos)
            guard wanted else { continue }
            let pid = item.persistentID.stringValue
            if item.isDRMProtected { payload.protected += 1; continue }
            guard item.locationType == .file, let location = item.location else {
                payload.cloudOnly += 1
                continue
            }
            guard fm.fileExists(atPath: location.path) else { payload.missing += 1; continue }
            guard MeshPaths.isAudioFile(location) else { payload.protected += 1; continue }

            let albumTitle = item.album.title ?? ""
            var track = LocalTrack(
                title: item.title.isEmpty ? TrackMetadataReader.titleFromFileName(location) : item.title,
                artist: item.artist?.name ?? item.album.albumArtist ?? "Unknown Artist",
                album: albumTitle.isEmpty ? "Unknown Album" : albumTitle,
                genre: item.genre.isEmpty ? "Unknown Genre" : item.genre,
                duration: Double(item.totalTime) / 1000.0,
                fileURL: location,
                coverImageName: "music.note",
                dateAdded: options.dateAdded ? (item.addedDate ?? Date()) : Date(),
                isAtmos: false,
                fileSize: ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file),
                lyrics: "",
                isFavorite: false,
                playCount: options.playCounts ? item.playCount : 0,
                lastPlayedDate: options.playCounts ? item.lastPlayedDate : nil,
                format: item.kind ?? "AAC"
            )
            track.trackNumber = item.trackNumber
            track.discNumber = max(1, item.album.discNumber)
            track.year = item.year > 0 ? item.year : nil
            track.bitRate = item.bitrate > 0 ? item.bitrate : nil
            track.sampleRate = item.sampleRate > 0 ? Double(item.sampleRate) : nil
            track.albumArtist = item.album.albumArtist
            track.persistentID = pid
            payload.songs.append(AppleMusicSong(persistentID: pid, track: track))
        }

        for playlist in library.allPlaylists {
            if playlist.distinguishedKind == .kindLovedSongs {
                if options.lovedSongs { payload.lovedIDs.formUnion(playlist.items.map { $0.persistentID.stringValue }) }
                continue
            }
            guard options.playlists, !playlist.isPrimary, playlist.isVisible,
                  playlist.distinguishedKind == .kindNone,
                  playlist.kind == .regular || playlist.kind == .smart else { continue }
            if let selected = options.selectedPlaylists, !selected.contains(playlist.name) { continue }
            let ids = playlist.items.filter { $0.mediaKind == .kindSong || $0.mediaKind == .kindMusicVideo }.map { $0.persistentID.stringValue }
            if !ids.isEmpty { payload.playlists.append((playlist.name, playlist.persistentID.stringValue, ids)) }
        }

        if !payload.lovedIDs.isEmpty {
            for i in payload.songs.indices where payload.lovedIDs.contains(payload.songs[i].persistentID) {
                payload.songs[i].track.isFavorite = true
            }
        }
        return payload
    }

    /// Adds codec details and sidecar lyrics to a track that came from the Music library.
    nonisolated private static func enrich(_ track: LocalTrack) async -> LocalTrack {
        guard let url = track.fileURL else { return track }
        var track = track
        let asset = AVURLAsset(url: url)
        let codec = await TrackMetadataReader.probeCodec(asset)
        track.format = TrackMetadataReader.formatLabel(codec, fileExtension: url.pathExtension.lowercased())
        track.isAtmos = codec?.isAtmos ?? false
        track.coverImageName = track.isAtmos ? "sparkles" : "music.note"
        track.channels = codec?.channels
        track.bitDepth = codec?.bitDepth
        if let rate = codec?.sampleRate { track.sampleRate = rate }
        if let kbps = codec?.bitRate { track.bitRate = kbps }

        // Tags the Music library doesn't expose: copyright, label and embedded lyrics.
        if let items = try? await asset.load(.metadata) {
            for item in items {
                switch item.identifier {
                case .some(.iTunesMetadataCopyright), .some(.id3MetadataCopyright), .some(.commonIdentifierCopyrights):
                    if (track.copyright ?? "").isEmpty, let v = try? await item.load(.stringValue), !v.isEmpty { track.copyright = v }
                case .some(.iTunesMetadataPublisher), .some(.id3MetadataPublisher), .some(.commonIdentifierPublisher):
                    if let v = try? await item.load(.stringValue), !v.isEmpty { track.publisher = v }
                case .some(.iTunesMetadataLyrics), .some(.id3MetadataUnsynchronizedLyric):
                    if track.lyrics.isEmpty, let v = try? await item.load(.stringValue), !v.isEmpty { track.lyrics = v }
                case .some(.iTunesMetadataContentRating):
                    track.isExplicit = await TrackMetadataReader.isExplicitRating(item)
                default:
                    break
                }
            }
        }
        for sidecarExt in ["lrc", "txt"] {
            let sidecar = url.deletingPathExtension().appendingPathExtension(sidecarExt)
            if let content = try? String(contentsOf: sidecar, encoding: .utf8), !content.isEmpty {
                track.lyrics = content
                break
            }
        }
        return track
    }
}
