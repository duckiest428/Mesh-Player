//
//  AppState.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

// MARK: - Models

nonisolated struct LocalTrack: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: TimeInterval
    var fileURL: URL?
    var coverImageName: String // SF Symbol name or asset image
    var localCoverURL: URL? = nil // Local artwork image file URL (e.g. cover.jpg)
    /// Legacy inline artwork. Artwork now lives in `ArtworkStore` on disk; this is only
    /// read once to migrate old databases and is always nil afterwards.
    var embeddedArtData: Data? = nil
    var dateAdded: Date
    var isAtmos: Bool
    var fileSize: String
    var lyrics: String
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayedDate: Date? = nil
    var format: String = "AAC 256kbps"
    var discNumber: Int = 1
    var trackNumber: Int = 0
    var copyright: String? = nil
    var publisher: String? = nil
    var year: Int? = nil
    var artworkColors: [String]? = nil
    var bitRate: Int? = nil
    var sampleRate: Double? = nil
    var channels: Int? = nil
    var bitDepth: Int? = nil
    var albumArtist: String? = nil
    /// Apple Music persistent ID when the track came from the Music app library.
    var persistentID: String? = nil

    var yearRecorded: Int? {
        get { year }
        set { year = newValue }
    }

    var sortYear: Int { year ?? 0 }
    var favoriteRank: Int { isFavorite ? 1 : 0 }

    var parsedTrackNumber: Int {
        if trackNumber > 0 { return trackNumber }
        if let fileURL, let num = Self.leadingNumber(in: fileURL.deletingPathExtension().lastPathComponent) {
            return num
        }
        return Self.leadingNumber(in: title) ?? 9999
    }

    var cleanTitle: String {
        guard let first = title.first, first.isNumber || first == " " else { return title }
        let trimmed = title.drop(while: { $0 == " " }).drop(while: { $0.isNumber })
        let rest = trimmed.drop(while: { $0 == "-" || $0 == "_" || $0 == "." }).drop(while: { $0 == " " })
        return rest.isEmpty ? title : String(rest)
    }

    /// Stable key shared by every track of the same album so artwork is extracted once per album.
    var artworkKey: String {
        let albumName = album.trimmingCharacters(in: .whitespaces)
        if albumName.isEmpty || albumName == "Unknown Album" || albumName == "Single" {
            return "track-" + id.uuidString
        }
        let owner = (albumArtist?.isEmpty == false ? albumArtist! : artist).lowercased()
        return "album-" + ArtworkStore.stableHash("\(owner)|\(albumName.lowercased())")
    }

    private static func leadingNumber(in text: String) -> Int? {
        let digits = text.drop(while: { $0 == " " }).prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        return Int(digits)
    }
}

// MARK: - Continuous Immutable Play History Logging
nonisolated struct PlayLogEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var trackId: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: TimeInterval
    var timestamp: Date
}

nonisolated struct PlaylistTrack: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var track: LocalTrack
}

nonisolated struct Playlist: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var isImported: Bool
    var playlistTracks: [PlaylistTrack]
    /// When true, songs in this playlist are hidden from Songs, Albums, Artists, Genres and Home.
    var excludeFromLibrary: Bool? = nil
    /// Custom cover image file name inside the playlist artwork folder.
    var artworkFileName: String? = nil
    /// Non-nil for smart playlists: the rules that pick their songs.
    var smartRules: SmartPlaylistRules? = nil
    var dateCreated: Date? = nil
    var dateModified: Date? = nil
    /// Apple Music persistent ID of the playlist this one was imported from or exported to.
    var appleMusicID: String? = nil

    var tracks: [LocalTrack] {
        return playlistTracks.map { $0.track }
    }

    var isSmart: Bool { smartRules != nil }
    var hidesSongsFromLibrary: Bool { excludeFromLibrary ?? false }
    var isAppleMusicFavorites: Bool { isImported && name.contains("Favorites") && !isSmart }
}

// MARK: - Smart playlists

nonisolated struct SmartRule: Identifiable, Hashable, Codable {
    enum Field: String, Codable, CaseIterable, Identifiable {
        case title = "Title", artist = "Artist", album = "Album", genre = "Genre", year = "Year"
        case plays = "Plays", dateAdded = "Date Added", lastPlayed = "Last Played"
        case favorite = "Favorite", quality = "Quality", duration = "Time (minutes)"
        var id: String { rawValue }

        var kind: Kind {
            switch self {
            case .title, .artist, .album, .genre, .quality: return .text
            case .year, .plays, .duration: return .number
            case .dateAdded, .lastPlayed: return .date
            case .favorite: return .bool
            }
        }
        enum Kind { case text, number, date, bool }
    }

    enum Op: String, Codable, CaseIterable, Identifiable {
        case contains = "contains", notContains = "does not contain", equals = "is", notEquals = "is not", startsWith = "begins with"
        case greater = "is greater than", less = "is less than"
        case inLast = "is in the last", notInLast = "is not in the last"
        case isTrue = "is true", isFalse = "is false"
        var id: String { rawValue }

        static func options(for kind: Field.Kind) -> [Op] {
            switch kind {
            case .text: return [.contains, .notContains, .equals, .notEquals, .startsWith]
            case .number: return [.equals, .notEquals, .greater, .less]
            case .date: return [.inLast, .notInLast]
            case .bool: return [.isTrue, .isFalse]
            }
        }
    }

    var id: UUID = UUID()
    var field: Field = .genre
    var op: Op = .contains
    var text: String = ""
    var number: Double = 0

    func matches(_ t: LocalTrack, now: Date) -> Bool {
        switch field.kind {
        case .text:
            let value: String
            switch field {
            case .title: value = t.title
            case .artist: value = t.artist
            case .album: value = t.album
            case .genre: value = t.genre
            default: value = t.isAtmos ? "Dolby Atmos" : t.format
            }
            let needle = text.trimmingCharacters(in: .whitespaces)
            switch op {
            case .contains: return needle.isEmpty || value.localizedCaseInsensitiveContains(needle)
            case .notContains: return needle.isEmpty || !value.localizedCaseInsensitiveContains(needle)
            case .equals: return value.localizedCaseInsensitiveCompare(needle) == .orderedSame
            case .notEquals: return value.localizedCaseInsensitiveCompare(needle) != .orderedSame
            default: return value.lowercased().hasPrefix(needle.lowercased())
            }
        case .number:
            let value: Double
            switch field {
            case .year: value = Double(t.year ?? 0)
            case .plays: value = Double(t.playCount)
            default: value = t.duration / 60
            }
            switch op {
            case .equals: return value == number
            case .notEquals: return value != number
            case .greater: return value > number
            default: return value < number
            }
        case .date:
            let date = field == .dateAdded ? t.dateAdded : t.lastPlayedDate
            let cutoff = now.addingTimeInterval(-number * 86_400)
            guard let date else { return op == .notInLast }
            return op == .inLast ? date >= cutoff : date < cutoff
        case .bool:
            return op == .isTrue ? t.isFavorite : !t.isFavorite
        }
    }
}

nonisolated struct SmartPlaylistRules: Hashable, Codable {
    enum LimitOrder: String, Codable, CaseIterable, Identifiable {
        case random = "Random", mostPlayed = "Most Played", leastPlayed = "Least Played"
        case recentlyAdded = "Most Recently Added", recentlyPlayed = "Most Recently Played", title = "Title"
        var id: String { rawValue }
    }
    var matchAll = true
    var rules: [SmartRule] = [SmartRule()]
    var limit: Int? = nil
    var limitOrder: LimitOrder = .random

    func evaluate(_ library: [LocalTrack], seed: UUID) -> [LocalTrack] {
        let now = Date()
        var matched = library.filter { t in
            guard !rules.isEmpty else { return true }
            return matchAll ? rules.allSatisfy { $0.matches(t, now: now) } : rules.contains { $0.matches(t, now: now) }
        }
        guard let limit, limit > 0, matched.count > limit else { return matched }
        switch limitOrder {
        case .random:
            // Stable per playlist so the selection doesn't change on every redraw.
            let salt = seed.uuidString
            matched.sort { ArtworkStore.stableHash(salt + $0.id.uuidString) < ArtworkStore.stableHash(salt + $1.id.uuidString) }
        case .mostPlayed: matched.sort { $0.playCount > $1.playCount }
        case .leastPlayed: matched.sort { $0.playCount < $1.playCount }
        case .recentlyAdded: matched.sort { $0.dateAdded > $1.dateAdded }
        case .recentlyPlayed: matched.sort { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        case .title: matched.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return Array(matched.prefix(limit))
    }
}

struct LocalAlbum: Identifiable, Hashable {
    var id: String { key }
    /// Album key: the name, plus the album artist when another album shares the name.
    let key: String
    let name: String
    let artist: String
    let tracksCount: Int
    let trackRepresentative: LocalTrack
    var yearRecorded: Int? {
        trackRepresentative.yearRecorded ?? trackRepresentative.year
    }
}

struct LocalArtist: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tracksCount: Int
    let trackRepresentative: LocalTrack
    var yearRecorded: Int? {
        trackRepresentative.yearRecorded ?? trackRepresentative.year
    }
}

struct LocalGenre: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tracksCount: Int
    let trackRepresentative: LocalTrack
}

struct LibraryStats: Equatable {
    var songs = 0
    var artists = 0
    var albums = 0
    var genres = 0
    var plays = 0
    var listeningSeconds: TimeInterval = 0
}

nonisolated struct DatabaseDump: Codable {
    var tracks: [LocalTrack]
    var playlists: [Playlist]
    var playHistoryLog: [PlayLogEntry]?
}

// MARK: - Themes Structure


// MARK: - Library folders

class LibraryManager {
    static let shared = LibraryManager()

    let libraryDirectory: URL
    let autoAddDirectory: URL
    let mediaDirectory: URL

    private init() {
        libraryDirectory = MeshPaths.meshLibraryFolder
        autoAddDirectory = libraryDirectory.appendingPathComponent("Automatically Add to Mesh Player")
        mediaDirectory = libraryDirectory.appendingPathComponent("Media/Music")

        for dir in [libraryDirectory, autoAddDirectory, mediaDirectory] {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create Mesh Player library directory \(dir.path): \(error)")
            }
        }
    }

    // Simple polling monitor for the Automatically Add folder
    private var monitorTimer: Timer?
    func startMonitoringAutoAddFolder(onFound: @escaping ([URL]) -> Void) {
        monitorTimer?.invalidate()
        let folder = autoAddDirectory
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let audio = files.filter { MeshPaths.isAudioFile($0) }
            if !audio.isEmpty { onFound(audio) }
        }
    }
}

// MARK: - App State

class AppStateManager: ObservableObject {
    enum RightSidebarPanel: String, CaseIterable {
        case none, lyrics, queue, output
    }
    @Published var activeRightSidebar: RightSidebarPanel = .none
    @Published var showSyncWindow: Bool = false
    @Published var showSettingsSheet: Bool = false
    @Published var showFullscreenPlayer: Bool = false
    @Published var showImportOptions: Bool = false
    @Published var selectedTab: String? = "home" {
        didSet {
            guard oldValue != selectedTab else { return }
            activeFilterType = nil
            activeFilterValue = nil
            if !preserveSearchOnNavigation { searchKeyword = "" }
            // Picking something in the sidebar starts a fresh trail.
            if !isDrillingDown { backStack = [] }
        }
    }
    private var preserveSearchOnNavigation = false

    /// A page reached by drilling down (album, artist, "See All" lists, search results).
    struct DetailLocation: Equatable {
        var tab: String?
        var filterType: String?
        var filterValue: String?
        var search: String
    }

    /// Where Back goes: the pages visited before the current drill-down page.
    @Published private(set) var backStack: [DetailLocation] = []
    private var isDrillingDown = false

    private var currentLocation: DetailLocation {
        DetailLocation(tab: selectedTab, filterType: activeFilterType, filterValue: activeFilterValue, search: searchKeyword)
    }

    /// Opens a drill-down page, remembering the current page so Back returns to it.
    func open(tab: String, filter type: String, value: String) {
        let from = currentLocation
        if from != DetailLocation(tab: tab, filterType: type, filterValue: value, search: from.search) { backStack.append(from) }
        isDrillingDown = true
        selectedTab = tab
        isDrillingDown = false
        activeFilterType = type
        activeFilterValue = value
    }

    /// Back from a drill-down page.
    func goBack() {
        guard let previous = backStack.popLast() else {
            activeFilterType = nil
            activeFilterValue = nil
            return
        }
        isDrillingDown = true
        preserveSearchOnNavigation = true
        selectedTab = previous.tab
        preserveSearchOnNavigation = false
        isDrillingDown = false
        activeFilterType = previous.filterType
        activeFilterValue = previous.filterValue
        if searchKeyword != previous.search { searchKeyword = previous.search }
    }

    /// Title for the Back button.
    var backTitle: String {
        guard let previous = backStack.last else { return Self.tabTitle(selectedTab) }
        if previous.tab == "search" && previous.filterType == nil { return "Search" }
        if let value = previous.filterValue {
            if previous.filterType == "album" { return Self.albumName(fromKey: value) }
            if previous.filterType == "artistSection" || previous.filterType == "searchSection" {
                return value.components(separatedBy: "\u{1}").last ?? "Back"
            }
            return value
        }
        if let tab = previous.tab, tab.hasPrefix("playlist-"),
           let playlist = playlists.first(where: { "playlist-\($0.id.uuidString)" == tab }) {
            return playlist.name
        }
        return Self.tabTitle(previous.tab)
    }

    static func tabTitle(_ tab: String?) -> String {
        switch tab {
        case "albums": return "Albums"
        case "artists": return "Artists"
        case "genres": return "Genres"
        case "songs": return "All Songs"
        case "recently-added": return "Recently Added"
        case "allPlaylists": return "All Playlists"
        case "search": return "Search"
        case "home": return "Home"
        case "getMusic": return "Get Music"
        case "meshReplay": return "Mesh Replay"
        case "statistics": return "Statistics"
        default: return "Back"
        }
    }

    /// Lists "A & B" collaborations under the first artist (Settings › Library).
    @Published var mergeCollaborationArtists: Bool = UserDefaults.standard.bool(forKey: "settings.mergeCollaborationArtists") {
        didSet {
            UserDefaults.standard.set(mergeCollaborationArtists, forKey: "settings.mergeCollaborationArtists")
            derived.artists = nil
            derived.albums = nil
            derived.recentAlbums = nil
            derived.stats = nil
            objectWillChange.send()
        }
    }

    /// The artist a song is listed under: with the merge setting on, "A & B", "A, B" and
    /// "A feat. B" become "A".
    func displayArtist(_ artist: String) -> String {
        guard mergeCollaborationArtists else { return artist }
        var name = artist
        for separator in [" & ", ", ", " feat. ", " ft. ", " featuring ", " with ", " x ", " X "] {
            if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? artist : trimmed
    }

    /// A search for Get Music to run when it opens.
    @Published var getMusicQuery: String?

    /// Favorite artists (the heart on an artist's page).
    @Published var favoriteArtists: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favoriteArtists") ?? []) {
        didSet { UserDefaults.standard.set(Array(favoriteArtists).sorted(), forKey: "favoriteArtists") }
    }

    @Published var activeQueue: [LocalTrack] = []
    @Published var unshuffleQueue: [LocalTrack] = []
    @Published var isQueueShuffled: Bool = false
    @Published var repeatMode: Int = 0 // 0 = off, 1 = all, 2 = one

    // Album Sorting
    enum AlbumSortCriteria: String, CaseIterable {
        case dateAdded = "Date Added"
        case yearReleased = "Year Released"
        case title = "Title"
        case artist = "Artist"
    }
    @Published var albumSortCriteria: AlbumSortCriteria = .dateAdded { didSet { persist(albumSortCriteria.rawValue, "albumSortCriteria") } }

    // Global Idle Tracker. Only publishes when the value actually flips, so mouse movement
    // and scrolling no longer invalidate every view observing the app state.
    @Published private(set) var isIdle = false
    private var lastActivity = Date()
    private var idleTimer: Timer?
    private var eventMonitor: Any?
    private var terminationObserver: NSObjectProtocol?

    init() {
        loadSettings()
        loadContext()
        setupIdleMonitor()
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    private func setupIdleMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastActivity = Date()
                if self.isIdle { self.isIdle = false }
            }
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isIdle else { return }
                if Date().timeIntervalSince(self.lastActivity) > 30 { self.isIdle = true }
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Navigates to a tab while keeping the current search text.
    func navigate(to tab: String, keepingSearch: Bool) {
        preserveSearchOnNavigation = keepingSearch
        selectedTab = tab
        preserveSearchOnNavigation = false
    }

    /// Opens an album page by album key (see `albumKey(for:)`).
    func showAlbum(_ key: String) {
        open(tab: "albums", filter: "album", value: key)
    }

    func showAlbum(of track: LocalTrack) {
        showAlbum(albumKey(for: track))
    }

    func showArtist(_ name: String) {
        open(tab: "artists", filter: "artist", value: displayArtist(name))
    }

    func showGenre(_ name: String) {
        open(tab: "genres", filter: "genre", value: name)
    }

    // Manage active queue tracking
    func fetchITunesData(album: String, artist: String, completion: @escaping (String?, String?) -> Void) {
        let cleanAlbum = album.replacingOccurrences(of: "(Explicit)", with: "", options: .caseInsensitive)
                              .replacingOccurrences(of: "(Deluxe)", with: "", options: .caseInsensitive)
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        let term = "\(cleanAlbum) \(cleanArtist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(term)&media=music&entity=album&limit=5") else {
            completion(nil, nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            var artwork: String? = nil
            var copyright: String? = nil
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]], !results.isEmpty {
                let bestMatch = results.first { item in
                    let itemArtist = (item["artistName"] as? String ?? "").lowercased()
                    return itemArtist.contains(cleanArtist.lowercased()) || cleanArtist.lowercased().contains(itemArtist)
                } ?? results.first
                if let first = bestMatch {
                    if let art100 = first["artworkUrl100"] as? String {
                        artwork = art100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    }
                    copyright = first["copyright"] as? String
                }
            }
            DispatchQueue.main.async { completion(artwork, copyright) }
        }.resume()
    }

    func setQueue(tracks: [LocalTrack], startTrack: LocalTrack) {
        unshuffleQueue = tracks
        if isQueueShuffled {
            var shuffled = tracks.filter { $0.id != startTrack.id }.shuffled()
            shuffled.insert(startTrack, at: 0)
            activeQueue = shuffled
        } else {
            activeQueue = tracks
        }
    }

    /// Replaces the queue with `tracks` and starts playing `startTrack` (or the first track).
    func play(_ tracks: [LocalTrack], startingAt startTrack: LocalTrack? = nil, shuffled: Bool? = nil, engine: AudioEngineManager) {
        if let shuffled { isQueueShuffled = shuffled }
        let start = startTrack ?? (isQueueShuffled ? tracks.randomElement() : tracks.first)
        guard let start else { return }
        setQueue(tracks: tracks, startTrack: start)
        engine.playTrack(start)
    }

    /// Inserts songs right after the current one ("Play Next").
    func playNext(_ newTracks: [LocalTrack], engine: AudioEngineManager) {
        guard !newTracks.isEmpty else { return }
        guard let current = engine.currentTrack, let idx = activeQueue.firstIndex(where: { $0.id == current.id }) else {
            play(newTracks, shuffled: false, engine: engine)
            return
        }
        let ids = Set(newTracks.map(\.id))
        var queue = activeQueue
        queue.removeAll { ids.contains($0.id) && $0.id != current.id }
        let insertAt = (queue.firstIndex(where: { $0.id == current.id }) ?? idx) + 1
        queue.insert(contentsOf: newTracks.filter { $0.id != current.id }, at: insertAt)
        activeQueue = queue
        unshuffleQueue.append(contentsOf: newTracks.filter { t in !unshuffleQueue.contains(where: { $0.id == t.id }) })
    }

    /// Appends songs to the end of the queue ("Play Later").
    func playLater(_ newTracks: [LocalTrack], engine: AudioEngineManager) {
        guard !newTracks.isEmpty else { return }
        guard engine.currentTrack != nil, !activeQueue.isEmpty else {
            play(newTracks, shuffled: false, engine: engine)
            return
        }
        activeQueue.append(contentsOf: newTracks)
        unshuffleQueue.append(contentsOf: newTracks)
    }

    // Continuous Immutable Logging Store
    @Published var playHistoryLog: [PlayLogEntry] = []

    func logPlayEvent(for track: LocalTrack) {
        let entry = PlayLogEntry(
            trackId: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            genre: track.genre,
            duration: track.duration,
            timestamp: Date()
        )
        playHistoryLog.append(entry)
        saveContext()
    }


    // MARK: - Persistence

    @Published private(set) var isLibraryLoaded = false
    private var isApplyingLoadedLibrary = false
    private var pendingSave: Task<Void, Never>?
    nonisolated private static let saveQueue = DispatchQueue(label: "mesh.database.save", qos: .utility)

    private static var databaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mesh Player")
            .appendingPathComponent("database.sqlite")
    }

    /// Debounced, off-main write of the whole library.
    func saveContext() {
        guard isLibraryLoaded, !isApplyingLoadedLibrary else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            let dump = self.makeDump()
            Self.saveQueue.async { Self.write(dump, to: Self.databaseURL) }
        }
    }

    /// Immediate synchronous save, used when the app quits.
    func saveNow() {
        guard isLibraryLoaded else { return }
        pendingSave?.cancel()
        let dump = makeDump()
        Self.saveQueue.sync { Self.write(dump, to: Self.databaseURL) }
    }

    private func makeDump() -> DatabaseDump {
        DatabaseDump(tracks: tracks, playlists: playlists, playHistoryLog: playHistoryLog)
    }

    nonisolated private static func write(_ dump: DatabaseDump, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(dump)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed context.save(): \(error)")
        }
    }

    func loadContext() {
        let dbFile = Self.databaseURL

        // Migration: Check for old database location
        let oldDbFile = LibraryManager.shared.libraryDirectory.appendingPathComponent("database.sqlite")
        if FileManager.default.fileExists(atPath: oldDbFile.path), !FileManager.default.fileExists(atPath: dbFile.path) {
            // Copy (an instant APFS clone) rather than move, so the original stays untouched.
            try? FileManager.default.createDirectory(at: dbFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: oldDbFile, to: dbFile)
        }

        Task.detached(priority: .userInitiated) { [self] in
            var dump: DatabaseDump? = nil
            var migratedArtwork = false
            if let data = try? Data(contentsOf: dbFile) {
                do {
                    var decoded = try JSONDecoder().decode(DatabaseDump.self, from: data)
                    migratedArtwork = Self.migrateInlineArtwork(&decoded)
                    dump = decoded
                } catch {
                    // Never let a later save overwrite a library we couldn't read: set it aside first.
                    print("Failed loadContext(): \(error)")
                    let stamp = Int(Date().timeIntervalSince1970)
                    let backup = dbFile.deletingLastPathComponent().appendingPathComponent("database-unreadable-\(stamp).sqlite")
                    try? FileManager.default.moveItem(at: dbFile, to: backup)
                }
            }
            let loaded = dump
            let migrated = migratedArtwork
            await MainActor.run {
                if let loaded {
                    self.isApplyingLoadedLibrary = true
                    self.tracks = loaded.tracks
                    if !loaded.playlists.isEmpty {
                        // Two playlists with one id make the sidebar open the wrong one; give repeats a new id.
                        var seen = Set<UUID>()
                        var lists = loaded.playlists
                        for i in lists.indices where !seen.insert(lists[i].id).inserted { lists[i].id = UUID() }
                        self.playlists = lists
                    }
                    self.playHistoryLog = loaded.playHistoryLog ?? []
                    self.isApplyingLoadedLibrary = false
                }
                self.isLibraryLoaded = true
                if migrated { self.saveContext() }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard let self else { return }
                    CopyrightResolver.shared.backfillFromTags(self)
                }
            }
        }
    }

    /// Moves artwork that older builds stored inline in the database into the on-disk artwork cache.
    nonisolated private static func migrateInlineArtwork(_ dump: inout DatabaseDump) -> Bool {
        var migrated = false
        for i in dump.tracks.indices {
            if let data = dump.tracks[i].embeddedArtData {
                ArtworkStore.shared.store(data, forKey: dump.tracks[i].artworkKey, overwrite: false)
                dump.tracks[i].embeddedArtData = nil
                migrated = true
            }
        }
        for p in dump.playlists.indices {
            for t in dump.playlists[p].playlistTracks.indices where dump.playlists[p].playlistTracks[t].track.embeddedArtData != nil {
                dump.playlists[p].playlistTracks[t].track.embeddedArtData = nil
                migrated = true
            }
        }
        return migrated
    }

    // MARK: - Settings (persisted in UserDefaults)

    private func persist(_ value: Any, _ key: String) {
        guard !isLoadingSettings else { return }
        UserDefaults.standard.set(value, forKey: "settings.\(key)")
    }

    private var isLoadingSettings = false

    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: "settings.\(key)") as? Bool ?? fallback }
        if let theme = d.string(forKey: "settings.currentThemeName") { currentThemeName = theme }
        if let sort = d.string(forKey: "settings.sortCriteria") { sortCriteria = sort }
        if let albumSort = d.string(forKey: "settings.albumSortCriteria"), let c = AlbumSortCriteria(rawValue: albumSort) { albumSortCriteria = c }
        sortAscending = bool("sortAscending", false)
        autoScrollLyrics = bool("autoScrollLyrics", true)
        showDockArtwork = bool("showDockArtwork", false)
        enableAtmos = bool("enableAtmos", true)
        spatialAudioActive = bool("spatialAudioActive", false)
        animatedArtworkEnabled = bool("animatedArtworkEnabled", true)
        showTimeColumn = bool("showTimeColumn", true)
        showArtistColumn = bool("showArtistColumn", true)
        showYearColumn = bool("showYearColumn", true)
        showAlbumColumn = bool("showAlbumColumn", true)
        showGenreColumn = bool("showGenreColumn", true)
        showFavoritesColumn = bool("showFavoritesColumn", true)
        showPlaysColumn = bool("showPlaysColumn", true)
        showDateAddedColumn = bool("showDateAddedColumn", true)
        showFormatColumn = bool("showFormatColumn", true)
    }

    // MARK: - Queue navigation

    func toggleShuffle(currentTrack: LocalTrack?) {
        isQueueShuffled.toggle()
        if isQueueShuffled {
            if let current = currentTrack, activeQueue.contains(where: { $0.id == current.id }) {
                var shuffled = unshuffleQueue.filter { $0.id != current.id }.shuffled()
                shuffled.insert(current, at: 0)
                activeQueue = shuffled
            } else {
                activeQueue = unshuffleQueue.shuffled()
            }
        } else {
            activeQueue = unshuffleQueue
        }
    }

    func playNext(engine: AudioEngineManager) {
        guard let current = engine.currentTrack else { return }

        if repeatMode == 2 {
            engine.playTrack(current)
            return
        }

        let queueToUse = activeQueue.isEmpty ? tracks : activeQueue
        if queueToUse.isEmpty { return }

        if let idx = queueToUse.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = idx + 1
            if nextIdx < queueToUse.count {
                engine.playTrack(queueToUse[nextIdx])
            } else if repeatMode == 1 {
                engine.playTrack(queueToUse[0])
            } else {
                engine.pause() // stop at end of queue
            }
        }
    }

    func playPrevious(engine: AudioEngineManager) {
        guard let current = engine.currentTrack else { return }

        // If we are more than 3 seconds in, previous resets the track
        if engine.currentTime > 3.0 {
            engine.seek(to: 0)
            return
        }

        if repeatMode == 2 {
            engine.playTrack(current)
            return
        }

        let queueToUse = activeQueue.isEmpty ? tracks : activeQueue
        if queueToUse.isEmpty { return }

        if let idx = queueToUse.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = idx - 1
            if prevIdx >= 0 {
                engine.playTrack(queueToUse[prevIdx])
            } else if repeatMode == 1 {
                engine.playTrack(queueToUse[queueToUse.count - 1])
            } else {
                engine.seek(to: 0)
            }
        }
    }

    @Published var searchKeyword: String = ""
    @Published var sortCriteria: String = "dateAdded" { didSet { persist(sortCriteria, "sortCriteria") } } // "dateAdded", "title", "artist", "album", "playCount", "duration"
    @Published var sortAscending: Bool = false { didSet { persist(sortAscending, "sortAscending") } }
    @Published var selectedTrackIds: Set<UUID> = []
    var lastSelectedTrackIndex: Int? = nil
    @Published var activeFilterType: String? = nil
    @Published var activeFilterValue: String? = nil
    @Published var isShuffleActive: Bool = false

    // Core settings mapped from user preferences settings panel
    @Published var currentThemeName: String = "Mesh Default (Apple Music)" { didSet { persist(currentThemeName, "currentThemeName") } }
    @Published var autoScrollLyrics: Bool = true { didSet { persist(autoScrollLyrics, "autoScrollLyrics") } }
    @Published var showDockArtwork: Bool = false { didSet { persist(showDockArtwork, "showDockArtwork") } }
    @Published var enableAtmos: Bool = true { didSet { persist(enableAtmos, "enableAtmos") } }
    @Published var spatialAudioActive: Bool = false { didSet { persist(spatialAudioActive, "spatialAudioActive") } }
    @Published var animatedArtworkEnabled: Bool = true { didSet { persist(animatedArtworkEnabled, "animatedArtworkEnabled") } }

    /// Per-playlist sort. Playlists open in their own order until a column header is clicked.
    @Published var playlistSorts: [UUID: PlaylistSort] = [:]
    struct PlaylistSort: Equatable {
        var criteria = "playlistOrder"
        var ascending = true
    }

    // Visible details columns
    @Published var showTimeColumn: Bool = true { didSet { persist(showTimeColumn, "showTimeColumn") } }
    @Published var showArtistColumn: Bool = true { didSet { persist(showArtistColumn, "showArtistColumn") } }
    @Published var showYearColumn: Bool = true { didSet { persist(showYearColumn, "showYearColumn") } }
    @Published var showAlbumColumn: Bool = true { didSet { persist(showAlbumColumn, "showAlbumColumn") } }
    @Published var showGenreColumn: Bool = true { didSet { persist(showGenreColumn, "showGenreColumn") } }
    @Published var showFavoritesColumn: Bool = true { didSet { persist(showFavoritesColumn, "showFavoritesColumn") } }
    @Published var showPlaysColumn: Bool = true { didSet { persist(showPlaysColumn, "showPlaysColumn") } }
    @Published var showDateAddedColumn: Bool = true { didSet { persist(showDateAddedColumn, "showDateAddedColumn") } }
    @Published var showFormatColumn: Bool = true { didSet { persist(showFormatColumn, "showFormatColumn") } }

    var theme: ThemeColor { ThemeCatalog.theme(named: currentThemeName) }

    @Published var playlists: [Playlist] = [
        Playlist(name: "Favorites (Apple Music)", description: "Every song you've loved", isImported: true, playlistTracks: [])
    ] {
        didSet {
            playlistsVersion &+= 1
            saveContext()
        }
    }

    @Published var tracks: [LocalTrack] = [] {
        didSet {
            libraryVersion &+= 1
            saveContext()
        }
    }

    // MARK: - Library mutation

    private func indexOfExisting(_ track: LocalTrack) -> Int? {
        if let path = track.fileURL?.path, let idx = trackIndexByPath[path] { return idx }
        if let pid = track.persistentID, let idx = tracks.firstIndex(where: { $0.persistentID == pid }) { return idx }
        return tracks.firstIndex(where: { $0.title == track.title && $0.artist == track.artist && $0.album == track.album })
    }

    func upsertTrack(_ track: LocalTrack) {
        mergeImportedTracks([track])
    }

    /// Merges freshly imported tracks into the library in a single mutation, keeping
    /// user-specific state (favorites, play counts, date added) for tracks we already know.
    @discardableResult
    func mergeImportedTracks(_ incoming: [LocalTrack]) -> (added: Int, updated: Int) {
        guard !incoming.isEmpty else { return (0, 0) }
        var updatedTracks = tracks
        let pathIndex = trackIndexByPath
        var metaIndex: [String: Int] = [:]
        for (i, t) in updatedTracks.enumerated() {
            metaIndex["\(t.title)|\(t.artist)|\(t.album)"] = i
        }
        var added = 0, updated = 0
        var newTracks: [LocalTrack] = []
        var newKeys = Set<String>()

        for track in incoming {
            let metaKey = "\(track.title)|\(track.artist)|\(track.album)"
            let pathKey = track.fileURL.map { "path:" + $0.path }
            // Skip duplicates inside the same import batch.
            if newKeys.contains("meta:" + metaKey) || (pathKey.map { newKeys.contains($0) } ?? false) { continue }
            let existing = track.fileURL.flatMap { pathIndex[$0.path] } ?? metaIndex[metaKey]
            if let idx = existing, idx >= 0, idx < updatedTracks.count {
                var merged = track
                let old = updatedTracks[idx]
                merged.id = old.id
                merged.dateAdded = min(old.dateAdded, track.dateAdded)
                merged.isFavorite = old.isFavorite || track.isFavorite
                merged.playCount = max(old.playCount, track.playCount)
                merged.lastPlayedDate = [old.lastPlayedDate, track.lastPlayedDate].compactMap { $0 }.max()
                merged.artworkColors = old.artworkColors ?? track.artworkColors
                if merged.copyright == nil { merged.copyright = old.copyright }
                if merged.lyrics.isEmpty { merged.lyrics = old.lyrics }
                updatedTracks[idx] = merged
                updated += 1
            } else {
                newTracks.append(track)
                if let pathKey { newKeys.insert(pathKey) }
                newKeys.insert("meta:" + metaKey)
                added += 1
            }
        }
        updatedTracks.insert(contentsOf: newTracks, at: 0)
        tracks = updatedTracks
        return (added, updated)
    }

    /// Adds imported playlists, replacing earlier imports that have the same name.
    func mergeImportedPlaylists(_ incoming: [Playlist]) {
        guard !incoming.isEmpty else { return }
        var updated = playlists
        // Each existing playlist can be matched once. Match by Apple Music ID; fall back to the name
        // only for playlists imported before IDs were stored, so two playlists that share a name
        // (e.g. two called "Loose") never overwrite each other.
        var claimed = Set<UUID>()
        for playlist in incoming {
            let byID = playlist.appleMusicID.flatMap { id in
                updated.firstIndex { $0.isImported && $0.appleMusicID == id && !claimed.contains($0.id) }
            }
            let byName = byID == nil ? updated.firstIndex { $0.isImported && $0.appleMusicID == nil && $0.name == playlist.name && !claimed.contains($0.id) } : nil
            if let idx = byID ?? byName {
                claimed.insert(updated[idx].id)
                var replacement = playlist
                let existing = updated[idx]
                replacement.id = existing.id
                replacement.artworkFileName = existing.artworkFileName
                replacement.excludeFromLibrary = playlist.excludeFromLibrary ?? existing.excludeFromLibrary
                replacement.dateCreated = existing.dateCreated ?? playlist.dateCreated
                updated[idx] = replacement
            } else {
                updated.append(playlist)
                claimed.insert(playlist.id)
            }
        }
        // Earlier imports could leave two playlists with the same Apple Music ID or the same id;
        // keep the one this import claimed.
        var seenIDs = Set<UUID>()
        var seenAppleIDs = Set<String>()
        updated = updated.sorted { claimed.contains($0.id) && !claimed.contains($1.id) }.filter { p in
            guard seenIDs.insert(p.id).inserted else { return false }
            if p.isImported, let am = p.appleMusicID { return seenAppleIDs.insert(am).inserted }
            return true
        }
        let order = Dictionary(playlists.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        updated.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        playlists = updated
    }

    func removeTracks(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        tracks.removeAll { ids.contains($0.id) }
        var updated = playlists
        for i in updated.indices {
            updated[i].playlistTracks.removeAll { ids.contains($0.track.id) }
        }
        playlists = updated
        selectedTrackIds.subtract(ids)
    }

    func addTrackToPlaylist(track: LocalTrack, playlistId: UUID) {
        addTracksToPlaylist([track], playlistId: playlistId)
    }

    func addTracksToPlaylist(_ newTracks: [LocalTrack], playlistId: UUID) {
        guard let playlist = playlists.first(where: { $0.id == playlistId }), !playlist.isSmart else { return }
        if playlist.isAppleMusicFavorites {
            var updated = tracks
            let ids = Set(newTracks.map(\.id))
            for i in updated.indices where ids.contains(updated[i].id) { updated[i].isFavorite = true }
            tracks = updated
            return
        }
        updatePlaylist(playlistId) { $0.playlistTracks.append(contentsOf: newTracks.map { PlaylistTrack(track: $0) }) }
    }

    /// Playlists songs can be added to (smart playlists fill themselves).
    var editablePlaylists: [Playlist] { playlists.filter { !$0.isSmart } }

    func createNewPlaylist(name: String, initialTrack: LocalTrack? = nil) {
        createNewPlaylist(name: name, tracks: initialTrack.map { [$0] } ?? [])
    }

    @discardableResult
    func createNewPlaylist(name: String, tracks initialTracks: [LocalTrack]) -> Playlist {
        var newPlaylist = Playlist(name: name, description: "", isImported: false, playlistTracks: initialTracks.map { PlaylistTrack(track: $0) })
        newPlaylist.dateCreated = Date()
        newPlaylist.dateModified = Date()
        playlists.append(newPlaylist)
        return newPlaylist
    }

    @discardableResult
    func createSmartPlaylist(name: String, rules: SmartPlaylistRules) -> Playlist {
        var playlist = Playlist(name: name, description: "", isImported: false, playlistTracks: [])
        playlist.smartRules = rules
        playlist.dateCreated = Date()
        playlist.dateModified = Date()
        playlists.append(playlist)
        return playlist
    }

    func updatePlaylist(_ id: UUID, _ change: (inout Playlist) -> Void) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        var copy = playlists[idx]
        change(&copy)
        copy.dateModified = Date()
        playlists[idx] = copy
    }

    func duplicatePlaylist(_ id: UUID) {
        guard let original = playlists.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " Copy"
        copy.isImported = false
        copy.appleMusicID = nil
        copy.dateCreated = Date()
        copy.dateModified = Date()
        copy.playlistTracks = original.playlistTracks.map { PlaylistTrack(track: $0.track) }
        if let file = original.artworkFileName {
            let newName = copy.id.uuidString + "." + (file as NSString).pathExtension
            try? FileManager.default.copyItem(at: Self.playlistArtworkFolder.appendingPathComponent(file), to: Self.playlistArtworkFolder.appendingPathComponent(newName))
            copy.artworkFileName = newName
        }
        if let idx = playlists.firstIndex(where: { $0.id == id }) {
            playlists.insert(copy, at: idx + 1)
        } else {
            playlists.append(copy)
        }
        selectedTab = "playlist-\(copy.id.uuidString)"
    }

    /// Reorders playlist entries (playlist order view only).
    func movePlaylistTracks(_ playlistId: UUID, trackIds: [UUID], toIndex destination: Int) {
        updatePlaylist(playlistId) { playlist in
            let moving = trackIds.compactMap { id in playlist.playlistTracks.first(where: { $0.track.id == id }) }
            guard !moving.isEmpty else { return }
            let movingIds = Set(moving.map(\.id))
            let before = playlist.playlistTracks.prefix(destination).filter { movingIds.contains($0.id) }.count
            playlist.playlistTracks.removeAll { movingIds.contains($0.id) }
            let insertAt = max(0, min(playlist.playlistTracks.count, destination - before))
            playlist.playlistTracks.insert(contentsOf: moving, at: insertAt)
        }
    }

    static var playlistArtworkFolder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mesh Player/Playlist Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func setPlaylistArtwork(_ id: UUID, from url: URL?) {
        let folder = Self.playlistArtworkFolder
        if let old = playlists.first(where: { $0.id == id })?.artworkFileName {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
        }
        guard let url else {
            updatePlaylist(id) { $0.artworkFileName = nil }
            return
        }
        // A fresh name per change so cached images of the old cover are never reused.
        let name = "\(id.uuidString)-\(Int(Date().timeIntervalSince1970)).\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased())"
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
            updatePlaylist(id) { $0.artworkFileName = name }
        } catch {
            print("Couldn't set playlist artwork: \(error)")
        }
    }

    func playlistArtworkURL(_ playlist: Playlist) -> URL? {
        playlist.artworkFileName.map { Self.playlistArtworkFolder.appendingPathComponent($0) }
    }

    /// Writes an .m3u8 file listing the playlist's songs.
    func exportPlaylistM3U(_ playlist: Playlist, to url: URL) throws {
        var lines = ["#EXTM3U", "#PLAYLIST:\(playlist.name)"]
        for track in resolvedTracks(of: playlist) {
            guard let path = track.fileURL?.path else { continue }
            lines.append("#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)")
            lines.append(path)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Library maintenance

    /// Empties the library (songs, playlists, history). Audio files on disk are not touched.
    func clearLibrary() {
        activeQueue = []
        unshuffleQueue = []
        selectedTrackIds = []
        playHistoryLog = []
        playlistSorts = [:]
        tracks = []
        playlists = [Playlist(name: "Favorites (Apple Music)", description: "Every song you've loved", isImported: true, playlistTracks: [])]
        selectedTab = "home"
        saveNow()
    }

    func clearPlayHistory() {
        playHistoryLog = []
        saveContext()
    }

    func resetPlayCounts() {
        var updated = tracks
        for i in updated.indices {
            updated[i].playCount = 0
            updated[i].lastPlayedDate = nil
        }
        tracks = updated
        playHistoryLog = []
    }

    func clearFavorites() {
        var updated = tracks
        for i in updated.indices { updated[i].isFavorite = false }
        tracks = updated
    }

    func removeMissingTracks() -> Int {
        let missing = tracks.filter { t in t.fileURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true }
        removeTracks(ids: Set(missing.map(\.id)))
        return missing.count
    }

    /// Batch version of `setCopyright` used by the background tag reader.
    func setCopyrights(_ byAlbum: [String: String]) {
        var updated = tracks
        var changed = false
        for i in updated.indices where (updated[i].copyright ?? "").isEmpty {
            if let value = byAlbum[updated[i].album] {
                updated[i].copyright = value
                changed = true
            }
        }
        if changed { tracks = updated }
    }

    /// Stores a copyright line for every song on an album so it shows instantly next time.
    func setCopyright(_ copyright: String, forAlbum album: String) {
        guard !copyright.isEmpty else { return }
        var updated = tracks
        var changed = false
        for i in updated.indices where albumKey(for: updated[i]) == album && (updated[i].copyright ?? "").isEmpty {
            updated[i].copyright = copyright
            changed = true
        }
        if changed { tracks = updated }
    }

    /// What happens to a deleted playlist's songs.
    enum PlaylistSongsFate {
        case keep
        case removeFromLibrary
        case moveFilesToTrash
    }

    /// A removal waiting for the user to confirm (shown as one dialog by the main window).
    enum PendingRemoval: Identifiable {
        case songs([LocalTrack])
        case playlist(Playlist)

        var id: String {
            switch self {
            case .songs(let tracks): return "songs-" + tracks.map(\.id.uuidString).joined()
            case .playlist(let playlist): return "playlist-" + playlist.id.uuidString
            }
        }
    }

    @Published var pendingRemoval: PendingRemoval?

    func confirmRemoval(of tracks: [LocalTrack]) {
        guard !tracks.isEmpty else { return }
        pendingRemoval = .songs(tracks)
    }

    func confirmDeletion(of playlist: Playlist) {
        pendingRemoval = .playlist(playlist)
    }

    /// Removes songs from the library; with `trashFiles`, their audio files go to the Trash too.
    /// Returns how many files couldn't be moved.
    @discardableResult
    func removeFromLibrary(_ ids: Set<UUID>, trashFiles: Bool) -> Int {
        let urls = trashFiles ? tracks.filter { ids.contains($0.id) }.compactMap(\.fileURL) : []
        removeTracks(ids: ids)
        var failed = 0
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed += 1 }
        }
        return failed
    }

    func deletePlaylist(_ id: UUID, songs fate: PlaylistSongsFate = .keep) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let playlist = playlists[index]
        let playlistSongs = resolvedTracks(of: playlist)
        if let art = playlist.artworkFileName {
            try? FileManager.default.removeItem(at: Self.playlistArtworkFolder.appendingPathComponent(art))
        }
        playlists.remove(at: index)

        switch fate {
        case .keep:
            break
        case .removeFromLibrary:
            removeFromLibrary(Set(playlistSongs.map(\.id)), trashFiles: false)
        case .moveFilesToTrash:
            removeFromLibrary(Set(playlistSongs.map(\.id)), trashFiles: true)
        }
        if selectedTab == "playlist-\(id.uuidString)" {
            selectedTab = "songs"
        }
    }

    func removeTrackFromPlaylist(trackId: UUID, playlistId: UUID) {
        removeTracksFromPlaylist([trackId], playlistId: playlistId)
    }

    func removeTracksFromPlaylist(_ trackIds: [UUID], playlistId: UUID) {
        let ids = Set(trackIds)
        updatePlaylist(playlistId) { $0.playlistTracks.removeAll { ids.contains($0.track.id) } }
        // Loved songs live on the track itself, so removing from Favorites un-loves them.
        if let playlist = playlists.first(where: { $0.id == playlistId }), playlist.isAppleMusicFavorites {
            var updated = tracks
            for i in updated.indices where ids.contains(updated[i].id) { updated[i].isFavorite = false }
            tracks = updated
        }
    }

    func toggleFavorite(track: LocalTrack) {
        if let idx = trackIndexById[track.id] ?? tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx].isFavorite.toggle()
            LastFMService.shared.setLoved(tracks[idx], loved: tracks[idx].isFavorite)
        }
    }

    func isFavorite(_ trackId: UUID) -> Bool {
        guard let idx = trackIndexById[trackId], idx < tracks.count else { return false }
        return tracks[idx].isFavorite
    }

    func track(withId id: UUID) -> LocalTrack? {
        guard let idx = trackIndexById[id], idx < tracks.count else { return nil }
        return tracks[idx]
    }

    /// Resolves a playlist's tracks against the live library so edits (favorites, play counts) show up.
    func resolvedTracks(of playlist: Playlist) -> [LocalTrack] {
        if let rules = playlist.smartRules {
            return smartTracks(playlist.id, rules: rules)
        }
        let explicit = playlist.playlistTracks.map { track(withId: $0.track.id) ?? $0.track }
        if playlist.isAppleMusicFavorites {
            let explicitIds = Set(explicit.map(\.id))
            return explicit + tracks.filter { $0.isFavorite && !explicitIds.contains($0.id) }
        }
        return explicit
    }

    private func smartTracks(_ id: UUID, rules: SmartPlaylistRules) -> [LocalTrack] {
        validateDerived()
        let key = "\(libraryVersion)-\(rules.hashValue)"
        if let cached = derived.smart[id], cached.key == key { return cached.tracks }
        let result = rules.evaluate(libraryTracks, seed: id)
        derived.smart[id] = (key, result)
        return result
    }

    var currentPlaylist: Playlist? {
        guard let tab = selectedTab, tab.hasPrefix("playlist-"),
              let uuid = UUID(uuidString: String(tab.dropFirst("playlist-".count))) else { return nil }
        return playlists.first(where: { $0.id == uuid })
    }

    func playlistSort(for id: UUID) -> PlaylistSort {
        playlistSorts[id] ?? PlaylistSort()
    }

    // MARK: - Derived, memoized library views

    private var libraryVersion = 0
    private var playlistsVersion = 0
    private let derived = DerivedCache()

    private final class DerivedCache {
        var version = -1
        var exclusionVersion = ""
        var trackIndexById: [UUID: Int] = [:]
        var trackIndexByPath: [String: Int] = [:]
        var excludedIds: Set<UUID> = []
        var libraryTracks: [LocalTrack] = []
        var albums: [LocalAlbum]?
        var recentAlbums: [LocalAlbum]?
        /// Track id → album key (see `albumKey(for:)`).
        var albumKeys: [UUID: String]?
        var artists: [LocalArtist]?
        var genres: [LocalGenre]?
        var stats: LibraryStats?
        var smart: [UUID: (key: String, tracks: [LocalTrack])] = [:]
        var filteredSignature = ""
        var filtered: [LocalTrack] = []
    }

    private func validateDerived() {
        if derived.version != libraryVersion {
            derived.version = libraryVersion
            var byId: [UUID: Int] = [:]
            var byPath: [String: Int] = [:]
            byId.reserveCapacity(tracks.count)
            for (i, t) in tracks.enumerated() {
                byId[t.id] = i
                if let p = t.fileURL?.path { byPath[p] = i }
            }
            derived.trackIndexById = byId
            derived.trackIndexByPath = byPath
            derived.smart = [:]
            derived.albumKeys = nil
            derived.exclusionVersion = ""
        }
        let exclusionKey = "\(libraryVersion)-\(playlistsVersion)"
        guard derived.exclusionVersion != exclusionKey else { return }
        derived.exclusionVersion = exclusionKey
        var excluded = Set<UUID>()
        for playlist in playlists where playlist.hidesSongsFromLibrary && !playlist.isSmart {
            excluded.formUnion(playlist.playlistTracks.map(\.track.id))
        }
        derived.excludedIds = excluded
        derived.libraryTracks = excluded.isEmpty ? tracks : tracks.filter { !excluded.contains($0.id) }
        derived.albums = nil
        derived.recentAlbums = nil
        derived.artists = nil
        derived.genres = nil
        derived.stats = nil
        derived.filteredSignature = ""
    }

    private var trackIndexById: [UUID: Int] { validateDerived(); return derived.trackIndexById }
    private var trackIndexByPath: [String: Int] { validateDerived(); return derived.trackIndexByPath }

    /// Songs shown in library views: everything except songs from playlists marked "hide from library".
    var libraryTracks: [LocalTrack] { validateDerived(); return derived.libraryTracks }

    func isHiddenFromLibrary(_ id: UUID) -> Bool { validateDerived(); return derived.excludedIds.contains(id) }

    /// Identifies an album. Usually just its name; when two different artists have an album with
    /// the same name (two albums called "Loose"), the album artist is added after a \u{1}.
    func albumKey(for track: LocalTrack) -> String {
        validateDerived()
        if derived.albumKeys == nil { derived.albumKeys = Self.computeAlbumKeys(tracks) }
        return derived.albumKeys?[track.id] ?? track.album
    }

    /// The album name shown for an album key.
    static func albumName(fromKey key: String) -> String {
        key.components(separatedBy: "\u{1}").first ?? key
    }

    nonisolated private static func computeAlbumKeys(_ tracks: [LocalTrack]) -> [UUID: String] {
        var keys: [UUID: String] = [:]
        keys.reserveCapacity(tracks.count)
        var byName: [String: [LocalTrack]] = [:]
        for track in tracks { byName[track.album, default: []].append(track) }
        for (name, list) in byName {
            func owner(_ t: LocalTrack) -> String { (t.albumArtist?.isEmpty == false ? t.albumArtist! : t.artist) }
            // Owners with at least two songs count as separate albums; a lone song by a guest
            // artist (no album artist tag) joins the biggest one. Compilations stay together.
            let counts = Dictionary(grouping: list, by: owner).mapValues(\.count)
            let real = counts.filter { $0.value >= 2 }
            guard real.count > 1 else {
                for t in list { keys[t.id] = name }
                continue
            }
            let largest = real.max { $0.value < $1.value }!.key
            for t in list {
                let o = owner(t)
                keys[t.id] = name + "\u{1}" + (real[o] != nil ? o : largest)
            }
        }
        return keys
    }

    /// Songs of one album (by album key) in disc/track order (falls back to hidden songs when that's all there is).
    func albumTracks(named key: String) -> [LocalTrack] {
        var list = libraryTracks.filter { albumKey(for: $0) == key }
        if list.isEmpty { list = tracks.filter { albumKey(for: $0) == key } }
        return list.sorted {
            if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
            let a = $0.parsedTrackNumber, b = $1.parsedTrackNumber
            if a != b { return a < b }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func groupedAlbums(representative: ([LocalTrack]) -> LocalTrack) -> [LocalAlbum] {
        var dict: [String: [LocalTrack]] = [:]
        for track in libraryTracks { dict[albumKey(for: track), default: []].append(track) }
        return dict.map { (key, list) in
            let owner = list.first(where: { $0.albumArtist?.isEmpty == false })?.albumArtist ?? list.first?.artist ?? "Unknown Artist"
            return LocalAlbum(key: key, name: Self.albumName(fromKey: key), artist: displayArtist(owner), tracksCount: list.count, trackRepresentative: representative(list))
        }
    }

    var albumsList: [LocalAlbum] {
        validateDerived()
        if let cached = derived.albums { return cached }
        let result = groupedAlbums { $0.first! }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        derived.albums = result
        return result
    }

    var recentlyAddedAlbumsList: [LocalAlbum] {
        validateDerived()
        if let cached = derived.recentAlbums { return cached }
        let result = groupedAlbums { list in list.max(by: { $0.dateAdded < $1.dateAdded })! }
            .sorted { $0.trackRepresentative.dateAdded > $1.trackRepresentative.dateAdded }
        derived.recentAlbums = result
        return result
    }

    var artistsList: [LocalArtist] {
        validateDerived()
        if let cached = derived.artists { return cached }
        var dict: [String: [LocalTrack]] = [:]
        for track in libraryTracks { dict[displayArtist(track.artist), default: []].append(track) }
        let result = dict.map { (key, list) in
            LocalArtist(name: key, tracksCount: list.count, trackRepresentative: list.first!)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        derived.artists = result
        return result
    }

    var genresList: [LocalGenre] {
        validateDerived()
        if let cached = derived.genres { return cached }
        var dict: [String: [LocalTrack]] = [:]
        for track in libraryTracks { dict[track.genre, default: []].append(track) }
        let result = dict.map { (key, list) in
            LocalGenre(name: key, tracksCount: list.count, trackRepresentative: list.first!)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        derived.genres = result
        return result
    }

    var libraryStats: LibraryStats {
        validateDerived()
        if let cached = derived.stats { return cached }
        var stats = LibraryStats()
        var artists = Set<String>(), albums = Set<String>(), genres = Set<String>()
        for t in libraryTracks {
            artists.insert(displayArtist(t.artist))
            albums.insert(albumKey(for: t))
            genres.insert(t.genre)
            stats.plays += t.playCount
            stats.listeningSeconds += t.duration * Double(t.playCount)
        }
        stats.songs = libraryTracks.count
        stats.artists = artists.count
        stats.albums = albums.count
        stats.genres = genres.count
        derived.stats = stats
        return stats
    }

    /// Criteria / direction in effect for the list currently shown.
    var effectiveSort: (criteria: String, ascending: Bool) {
        if activeFilterType == nil, let playlist = currentPlaylist {
            let sort = playlistSort(for: playlist.id)
            return (sort.criteria, sort.ascending)
        }
        return (sortCriteria, sortAscending)
    }

    var filteredTracks: [LocalTrack] {
        validateDerived()
        let sort = effectiveSort
        let sig = "\(libraryVersion)-\(playlistsVersion)-\(selectedTab ?? "")-\(activeFilterType ?? "")-\(activeFilterValue ?? "")-\(sort.criteria)-\(sort.ascending)-\(searchKeyword)"
        if derived.filteredSignature == sig { return derived.filtered }

        var sorted = libraryTracks

        // 1. First, check if there is an active sub-filter drill-down
        if let filterType = activeFilterType, let filterVal = activeFilterValue {
            if filterType == "album" {
                sorted = sorted.filter { self.albumKey(for: $0) == filterVal }
            } else if filterType == "artist" {
                sorted = sorted.filter { $0.artist == filterVal }
            } else if filterType == "genre" {
                sorted = sorted.filter { $0.genre == filterVal }
            }
        } else if let playlist = currentPlaylist {
            sorted = resolvedTracks(of: playlist)
        }

        // 2. Sorting Criteria (playlists keep their own order unless the user picks a column)
        if sort.criteria != "playlistOrder" {
            // Precompute track numbers once instead of inside the comparator.
            let trackNumbers: [UUID: Int] = sort.criteria == "album"
                ? Dictionary(sorted.map { ($0.id, $0.parsedTrackNumber) }, uniquingKeysWith: { a, _ in a })
                : [:]
            let ascending = sort.ascending
            let criteria = sort.criteria
            sorted.sort { a, b in
                let result: ComparisonResult
                switch criteria {
                case "title":
                    result = a.title.localizedStandardCompare(b.title)
                case "artist":
                    result = a.artist.localizedStandardCompare(b.artist)
                case "album":
                    if a.album == b.album {
                        if a.discNumber != b.discNumber {
                            result = a.discNumber < b.discNumber ? .orderedAscending : .orderedDescending
                        } else {
                            let an = trackNumbers[a.id] ?? 0, bn = trackNumbers[b.id] ?? 0
                            result = an == bn ? .orderedSame : (an < bn ? .orderedAscending : .orderedDescending)
                        }
                    } else {
                        result = a.album.localizedStandardCompare(b.album)
                    }
                case "playCount":
                    result = a.playCount == b.playCount ? .orderedSame : (a.playCount < b.playCount ? .orderedAscending : .orderedDescending)
                case "duration":
                    result = a.duration == b.duration ? .orderedSame : (a.duration < b.duration ? .orderedAscending : .orderedDescending)
                case "genre":
                    result = a.genre.localizedStandardCompare(b.genre)
                case "year":
                    result = a.sortYear == b.sortYear ? .orderedSame : (a.sortYear < b.sortYear ? .orderedAscending : .orderedDescending)
                case "favourites", "favorites":
                    result = a.favoriteRank == b.favoriteRank ? .orderedSame : (a.favoriteRank < b.favoriteRank ? .orderedAscending : .orderedDescending)
                case "format":
                    result = a.format.localizedStandardCompare(b.format)
                default: // dateAdded
                    result = a.dateAdded == b.dateAdded ? .orderedSame : (a.dateAdded < b.dateAdded ? .orderedAscending : .orderedDescending)
                }

                if result == .orderedSame {
                    // Album order is naturally ascending even when other columns sort descending.
                    if criteria == "album" { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
                    return a.id.uuidString < b.id.uuidString
                }
                if criteria == "album" && a.album == b.album { return result == .orderedAscending }
                return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
            }
        }

        // 3. Search text Filtering
        let query = searchKeyword.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            sorted = sorted.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query) ||
                $0.album.localizedCaseInsensitiveContains(query) ||
                $0.genre.localizedCaseInsensitiveContains(query)
            }
        }

        derived.filtered = sorted
        derived.filteredSignature = sig
        return sorted
    }
}


struct InstrumentalBreakDots: View {
    let currentTime: TimeInterval
    let breakStart: TimeInterval
    let breakEnd: TimeInterval

    var body: some View {
        let duration = max(0.1, breakEnd - breakStart)
        let elapsed = currentTime - breakStart
        let fraction = min(max(0.0, elapsed / duration), 1.0)

        let remainingTime = breakEnd - currentTime
        let containerOpacity = remainingTime <= 0.7 ? min(max(0.0, remainingTime / 0.7), 1.0) : 1.0

        let d1Opacity = min(1.0, max(0.2, fraction / 0.33))
        let d2Opacity = min(1.0, max(0.2, (fraction - 0.33) / 0.33))
        let d3Opacity = min(1.0, max(0.2, (fraction - 0.66) / 0.34))

        HStack(spacing: 20) {
            ForEach(Array([d1Opacity, d2Opacity, d3Opacity].enumerated()), id: \.offset) { _, opacity in
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .opacity(opacity)
                    .scaleEffect(opacity > 0.6 ? 1.15 : 1.0)
            }
        }
        .padding(.vertical, 14)
        .opacity(containerOpacity)
    }
}

struct DolbyAtmosBadge: View {
    var color: Color = .white
    var scale: CGFloat = 1.0
    var showText: Bool = true

    var body: some View {
        HStack(spacing: 5 * scale) {
            HStack(spacing: 1.5 * scale) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addArc(center: CGPoint(x: 0, y: 4 * scale), radius: 4 * scale, startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.closeSubpath()
                }
                .fill(color)
                .frame(width: 4 * scale, height: 8 * scale)

                Path { path in
                    path.move(to: CGPoint(x: 4 * scale, y: 0))
                    path.addArc(center: CGPoint(x: 4 * scale, y: 4 * scale), radius: 4 * scale, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
                    path.addLine(to: CGPoint(x: 4 * scale, y: 0))
                    path.closeSubpath()
                }
                .fill(color)
                .frame(width: 4 * scale, height: 8 * scale)
            }
            .frame(width: 9 * scale, height: 8 * scale)

            if showText {
                Text("ATMOS")
                    .font(.system(size: 8.5 * scale, weight: .black, design: .default))
                    .tracking(1.5 * scale)
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 3 * scale)
        .background(color.opacity(0.12))
        .cornerRadius(4 * scale)
    }
}
