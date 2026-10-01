//
//  MobileLibrary.swift
//  Mesh Player iOS
//
//  The iPhone's music library: songs synced from the Mac (or added from Files / Finder),
//  playlists, favorites and play counts. Changes made here (plays, favorites, playlists) are
//  remembered and handed to the Mac on the next sync.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit
internal import UniformTypeIdentifiers

nonisolated struct Song: Identifiable, Codable, Hashable, Sendable {
    var info: SyncTrack
    /// Audio file name inside the library's Music folder; nil until the file has arrived.
    var fileName: String?
    /// Added on the iPhone (Files / Finder) rather than synced from a Mac.
    var isLocal = false
    /// Plays since the last sync (sent to the Mac, then reset).
    var pendingPlays = 0
    var favoriteChanged = false

    var id: UUID { info.id }
    var title: String { info.title }
    var artist: String { info.artist }
    var album: String { info.album }
    var albumArtist: String { info.albumArtist?.isEmpty == false ? info.albumArtist! : info.artist }
    var genre: String { info.genre }
    var duration: Double { info.duration }
    var isFavorite: Bool { info.isFavorite }
    var playCount: Int { info.playCount }
    var artworkKey: String { info.artworkKey }
    var isAvailable: Bool { fileName != nil }

    var qualityLabel: String? {
        if info.isAtmos { return "Dolby Atmos" }
        if info.format.localizedCaseInsensitiveContains("hi-res") { return "Hi-Res Lossless" }
        if info.format.localizedCaseInsensitiveContains("lossless") { return "Lossless" }
        return nil
    }
}

nonisolated struct MobilePlaylist: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var description: String
    var songIds: [UUID]
    var isSmart = false
    var isFavorites = false
    /// Created or edited on the iPhone since the last sync.
    var isDirty = false
    var dateModified: Date?
    /// Custom cover (an artwork key) chosen on the Mac.
    var artworkKey: String?
    /// Made on this iPhone (deleting it here also deletes it on the Mac).
    var createdHere: Bool?
}

nonisolated struct MobileAlbum: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let artist: String
    let year: Int?
    let genre: String
    let songs: [Song]
    var representative: Song { songs[0] }
    var dateAdded: Date { songs.map(\.info.dateAdded).max() ?? .distantPast }
}

nonisolated struct MobileArtist: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let songs: [Song]
    let albumCount: Int
}

private nonisolated struct LibraryFile: Codable {
    var songs: [Song]
    var playlists: [MobilePlaylist]
    var lastSync: Date?
    var lastSyncSource: String?
    var trustedMacs: [String: String]?
    /// Settings from the Mac (the Last.fm login is kept in the Keychain, not here).
    var settings: SyncSettings?
    /// Every counted play, the Mac's and this iPhone's (for Statistics and Replay).
    var playHistory: [SyncPlayEvent]?
    /// Plays made here that the Mac hasn't received yet.
    var pendingEventIds: [UUID]?
    /// Playlists deleted here since the last sync.
    var deletedPlaylists: [UUID]?
}

final class MobileLibrary: ObservableObject {
    static let shared = MobileLibrary()

    @Published private(set) var songs: [Song] = [] { didSet { version &+= 1 } }
    @Published private(set) var playlists: [MobilePlaylist] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastSyncSource: String?
    /// Mac device id → name, for Macs allowed to sync without asking.
    @Published private(set) var trustedMacs: [String: String] = [:]
    @Published private(set) var isImporting = false
    @Published var importMessage: String?
    /// Settings the Mac decided (theme, hidden songs, collaborations…). nil until the first sync.
    @Published private(set) var settings: SyncSettings? { didSet { hiddenIds = Set(settings?.hiddenTrackIds ?? []); version &+= 1 } }
    @Published private(set) var playHistory: [SyncPlayEvent] = []
    private(set) var hiddenIds: Set<UUID> = []
    private var pendingEventIds: Set<UUID> = []
    private var deletedPlaylists: Set<UUID> = []

    private var version = 0
    private var cacheVersion = -1
    private var cachedAlbums: [MobileAlbum] = []
    private var cachedArtists: [MobileArtist] = []
    private var cachedById: [UUID: Int] = [:]
    private var saveTask: Task<Void, Never>?

    // MARK: Locations

    nonisolated static var root: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    nonisolated static var musicFolder: URL { folder("Music") }
    nonisolated static var artworkFolder: URL { folder("Artwork") }
    nonisolated static var incomingFolder: URL { folder("Incoming") }
    private nonisolated static var databaseURL: URL { root.appendingPathComponent("library.json") }

    private nonisolated static func folder(_ name: String) -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = dir
            try? url.setResourceValues(values)
        }
        return dir
    }

    func fileURL(for song: Song) -> URL? {
        song.fileName.map { Self.musicFolder.appendingPathComponent($0) }
    }

    nonisolated static func artworkURL(for key: String) -> URL {
        artworkFolder.appendingPathComponent(key + ".jpg")
    }

    // MARK: Load / save

    private init() {
        if let data = try? Data(contentsOf: Self.databaseURL),
           let file = try? Self.decoder.decode(LibraryFile.self, from: data) {
            songs = file.songs
            playlists = file.playlists
            lastSync = file.lastSync
            lastSyncSource = file.lastSyncSource
            trustedMacs = file.trustedMacs ?? [:]
            settings = file.settings
            playHistory = file.playHistory ?? []
            pendingEventIds = Set(file.pendingEventIds ?? [])
            deletedPlaylists = Set(file.deletedPlaylists ?? [])
        }
        ensureFavoritesPlaylist()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        let file = LibraryFile(songs: songs, playlists: playlists, lastSync: lastSync, lastSyncSource: lastSyncSource, trustedMacs: trustedMacs,
                               settings: settings, playHistory: playHistory, pendingEventIds: Array(pendingEventIds), deletedPlaylists: Array(deletedPlaylists))
        DispatchQueue.global(qos: .utility).async {
            if let data = try? Self.encoder.encode(file) { try? data.write(to: Self.databaseURL, options: .atomic) }
        }
    }

    private func ensureFavoritesPlaylist() {
        if !playlists.contains(where: \.isFavorites) {
            playlists.insert(MobilePlaylist(id: UUID(), name: "Favorites", description: "Songs you love", songIds: [], isFavorites: true), at: 0)
        }
    }

    // MARK: Derived views

    private func refreshCaches() {
        guard cacheVersion != version else { return }
        cacheVersion = version
        let available = songs.filter { $0.isAvailable && !hiddenIds.contains($0.id) }
        var byAlbum: [String: [Song]] = [:]
        for song in available { byAlbum["\(song.albumArtist.lowercased())|\(song.album.lowercased())", default: []].append(song) }
        cachedAlbums = byAlbum.map { key, list in
            let sorted = list.sorted { ($0.info.discNumber, $0.info.trackNumber, $0.title) < ($1.info.discNumber, $1.info.trackNumber, $1.title) }
            let first = sorted[0]
            return MobileAlbum(key: key, title: first.album, artist: first.albumArtist, year: first.info.year, genre: first.genre, songs: sorted)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        var byArtist: [String: [Song]] = [:]
        for song in available { byArtist[displayArtist(song.albumArtist), default: []].append(song) }
        cachedArtists = byArtist.map { name, list in
            MobileArtist(name: name, songs: list, albumCount: Set(list.map(\.album)).count)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cachedById = Dictionary(uniqueKeysWithValues: songs.enumerated().map { ($1.id, $0) })
    }

    /// Songs that can play (their file is here), including ones hidden from the library.
    var playableSongs: [Song] { songs.filter(\.isAvailable) }
    /// Songs shown in the library: playable and not hidden by the Mac's "hide from library" playlists.
    var availableSongs: [Song] { songs.filter { $0.isAvailable && !hiddenIds.contains($0.id) } }

    /// The artist a song is listed under: with the Mac's collaboration setting on, "A & B",
    /// "A, B" and "A feat. B" become "A".
    func displayArtist(_ artist: String) -> String {
        guard settings?.mergeCollaborations == true else { return artist }
        var name = artist
        for separator in [" & ", ", ", " feat. ", " ft. ", " featuring ", " with ", " x ", " X "] {
            if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? artist : trimmed
    }

    func isFavoriteArtist(_ name: String) -> Bool { settings?.favoriteArtists.contains(name) ?? false }
    var albums: [MobileAlbum] { refreshCaches(); return cachedAlbums }
    var artists: [MobileArtist] { refreshCaches(); return cachedArtists }
    var recentlyAddedAlbums: [MobileAlbum] { albums.sorted { $0.dateAdded > $1.dateAdded } }
    var genres: [(name: String, songs: [Song])] {
        Dictionary(grouping: availableSongs, by: \.genre).map { ($0.key, $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func song(_ id: UUID) -> Song? {
        refreshCaches()
        guard let idx = cachedById[id], idx < songs.count else { return nil }
        return songs[idx]
    }

    func album(for song: Song) -> MobileAlbum? {
        albums.first { $0.title == song.album && $0.artist == song.albumArtist }
    }

    func songs(of playlist: MobilePlaylist) -> [Song] {
        if playlist.isFavorites {
            let explicit = playlist.songIds.compactMap(song).filter(\.isAvailable)
            let ids = Set(explicit.map(\.id))
            return explicit + playableSongs.filter { $0.isFavorite && !ids.contains($0.id) }
        }
        return playlist.songIds.compactMap(song).filter(\.isAvailable)
    }

    var totalBytes: Int64 {
        playableSongs.reduce(0) { $0 + $1.info.fileSize }
    }

    // MARK: Listening

    func recordPlay(_ id: UUID) {
        guard let idx = songs.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        songs[idx].info.playCount += 1
        songs[idx].info.lastPlayedDate = now
        songs[idx].pendingPlays += 1
        let s = songs[idx]
        let event = SyncPlayEvent(id: UUID(), trackId: s.id, title: s.title, artist: s.artist, album: s.album, genre: s.genre, duration: s.duration, timestamp: now)
        playHistory.append(event)
        pendingEventIds.insert(event.id)
        save()
    }

    func toggleFavorite(_ id: UUID) {
        guard let idx = songs.firstIndex(where: { $0.id == id }) else { return }
        songs[idx].info.isFavorite.toggle()
        songs[idx].favoriteChanged = true
        MobileLastFM.shared.setLoved(songs[idx], loved: songs[idx].info.isFavorite)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        save()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(name: String, songs initial: [UUID] = []) -> MobilePlaylist {
        let playlist = MobilePlaylist(id: UUID(), name: name, description: "", songIds: initial, isDirty: true, dateModified: Date(), createdHere: true)
        playlists.append(playlist)
        save()
        return playlist
    }

    func updatePlaylist(_ id: UUID, _ change: (inout MobilePlaylist) -> Void) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[idx])
        playlists[idx].isDirty = true
        playlists[idx].dateModified = Date()
        save()
    }

    func add(_ ids: [UUID], to playlistId: UUID) {
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else { return }
        if playlist.isFavorites {
            for id in ids where song(id)?.isFavorite == false { toggleFavorite(id) }
            return
        }
        updatePlaylist(playlistId) { $0.songIds.append(contentsOf: ids) }
    }

    func deletePlaylist(_ id: UUID) {
        if let playlist = playlists.first(where: { $0.id == id }), playlist.createdHere == true { deletedPlaylists.insert(id) }
        playlists.removeAll { $0.id == id && !$0.isFavorites }
        save()
    }

    // MARK: Removing

    func removeSongs(_ ids: Set<UUID>) {
        for song in songs where ids.contains(song.id) {
            if let url = fileURL(for: song) { try? FileManager.default.removeItem(at: url) }
        }
        songs.removeAll { ids.contains($0.id) }
        for i in playlists.indices { playlists[i].songIds.removeAll { ids.contains($0) } }
        save()
    }

    func removeAllMusic() {
        try? FileManager.default.removeItem(at: Self.musicFolder)
        try? FileManager.default.removeItem(at: Self.artworkFolder)
        songs = []
        playlists = []
        lastSync = nil
        ensureFavoritesPlaylist()
        ArtworkCache.shared.removeAll()
        saveNow()
    }

    // MARK: Trust

    func isTrusted(_ macId: String) -> Bool { trustedMacs[macId] != nil }

    func trust(_ macId: String, name: String) {
        trustedMacs[macId] = name
        saveNow()
    }

    func forget(_ macId: String) {
        trustedMacs[macId] = nil
        saveNow()
    }

    // MARK: Sync

    func makeInventory() -> SyncInventory {
        var files: [String: Int64] = [:]
        for song in songs where !song.isLocal {
            if let url = fileURL(for: song), let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                files[song.id.uuidString] = Int64(size)
            }
        }
        let artFiles = (try? FileManager.default.contentsOfDirectory(at: Self.artworkFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var artworkSizes: [String: Int64] = [:]
        for url in artFiles {
            artworkSizes[url.deletingPathExtension().lastPathComponent] = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0)
        }
        var changes: [String: SyncTrackChange] = [:]
        for song in songs where !song.isLocal && (song.pendingPlays > 0 || song.favoriteChanged) {
            changes[song.id.uuidString] = SyncTrackChange(playsSinceSync: song.pendingPlays, lastPlayed: song.info.lastPlayedDate,
                                                          isFavorite: song.favoriteChanged ? song.isFavorite : nil)
        }
        let dirty = playlists.filter { $0.isDirty && !$0.isFavorites }.map {
            SyncPlaylist(id: $0.id, name: $0.name, description: $0.description, trackIds: $0.songIds, isSmart: false, isFavorites: false, dateModified: $0.dateModified)
        }
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        let events = playHistory.filter { pendingEventIds.contains($0.id) }
        let local = songs.filter { $0.isLocal && $0.isAvailable }.map(\.info)
        return SyncInventory(files: files, artworkKeys: Array(artworkSizes.keys), changes: changes, playlists: dirty, freeSpace: free,
                             artworkSizes: artworkSizes, playEvents: events, deletedPlaylists: Array(deletedPlaylists), localSongs: local)
    }

    /// File for a song added on this iPhone that the Mac asked for.
    func uploadFile(for id: UUID) -> (song: Song, url: URL, artwork: URL?)? {
        guard let song = song(id), song.isLocal, let url = fileURL(for: song) else { return nil }
        let art = Self.artworkURL(for: song.artworkKey)
        return (song, url, FileManager.default.fileExists(atPath: art.path) ? art : nil)
    }

    /// Applies the Mac's metadata. Plays and favorites were merged on the Mac, so local counters reset.
    func applyManifest(_ manifest: SyncManifest) {
        let existing = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        var updated: [Song] = manifest.tracks.map { track in
            var song = existing[track.id] ?? Song(info: track)
            song.info = track
            // Songs added here and uploaded are now the Mac's too.
            song.isLocal = false
            song.pendingPlays = 0
            song.favoriteChanged = false
            if let name = song.fileName, !FileManager.default.fileExists(atPath: Self.musicFolder.appendingPathComponent(name).path) { song.fileName = nil }
            return song
        }
        let manifestIds = Set(manifest.tracks.map(\.id))
        updated.append(contentsOf: songs.filter { $0.isLocal && !manifestIds.contains($0.id) })
        songs = updated
        let createdHere = Set(playlists.filter { $0.createdHere == true }.map(\.id))
        var lists = manifest.playlists.map { p in
            MobilePlaylist(id: p.id, name: p.name, description: p.description, songIds: p.trackIds, isSmart: p.isSmart, isFavorites: p.isFavorites,
                           dateModified: p.dateModified, artworkKey: p.artworkKey, createdHere: createdHere.contains(p.id) ? true : nil)
        }
        // The Mac decides settings; the Last.fm login goes to the Keychain.
        if let incoming = manifest.settings {
            MobileLastFM.shared.update(from: incoming.lastFM)
            var stored = incoming
            stored.lastFM = nil
            settings = stored
            UserDefaults.standard.set(incoming.animatedArtwork, forKey: "animatedArtwork")
        }
        // Play history: the Mac's, plus plays made here that it hasn't seen yet.
        if let macHistory = manifest.playHistory {
            let macIds = Set(macHistory.map(\.id))
            let localOnly = playHistory.filter { pendingEventIds.contains($0.id) && !macIds.contains($0.id) }
            playHistory = (macHistory + localOnly).sorted { $0.timestamp < $1.timestamp }
        }
        if !lists.contains(where: \.isFavorites) { lists.insert(MobilePlaylist(id: UUID(), name: "Favorites", description: "Songs you love", songIds: [], isFavorites: true), at: 0) }
        // Playlists that only hold songs added on the iPhone stay.
        lists.append(contentsOf: playlists.filter { local in !lists.contains(where: { $0.id == local.id }) && local.songIds.allSatisfy { id in songs.first(where: { $0.id == id })?.isLocal ?? false } && !local.isFavorites })
        playlists = lists
        save()
    }

    /// Adds files received during a sync. Called in batches so the library (and every screen
    /// showing it) updates a few times a second at most, not once per file.
    func registerReceived(files: [(id: UUID, url: URL)], artwork: [(key: String, url: URL)]) {
        let fm = FileManager.default
        if !files.isEmpty {
            var updated = songs
            let index = Dictionary(updated.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            for file in files {
                guard let idx = index[file.id] else {
                    try? fm.removeItem(at: file.url)
                    continue
                }
                let name = file.id.uuidString + "." + updated[idx].info.fileExtension
                let destination = Self.musicFolder.appendingPathComponent(name)
                try? fm.removeItem(at: destination)
                do {
                    try fm.moveItem(at: file.url, to: destination)
                    updated[idx].fileName = name
                } catch {
                    print("Couldn't store synced file: \(error)")
                }
            }
            songs = updated
            save() // keep what arrived if the sync is cut off
        }
        if !artwork.isEmpty {
            for art in artwork {
                let destination = Self.artworkURL(for: art.key)
                try? fm.removeItem(at: destination)
                try? fm.moveItem(at: art.url, to: destination)
            }
            ArtworkCache.shared.invalidate(Set(artwork.map(\.key)))
        }
    }

    /// Removes partly received files left by a sync that was cut off.
    func clearIncoming() {
        let folder = Self.incomingFolder
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Ends a sync: removes songs that are no longer part of it and remembers the Mac.
    func finishSync(manifest: SyncManifest, damaged: Int = 0) -> String {
        let keep = Set(manifest.tracks.map(\.id))
        let removed = songs.filter { !$0.isLocal && !keep.contains($0.id) }
        for song in removed {
            if let url = fileURL(for: song) { try? FileManager.default.removeItem(at: url) }
        }
        songs.removeAll { !$0.isLocal && !keep.contains($0.id) }
        // Remove files that no longer belong to any song.
        let expected = Set(songs.compactMap(\.fileName))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Self.musicFolder.path)) ?? [] where !expected.contains(name) {
            try? FileManager.default.removeItem(at: Self.musicFolder.appendingPathComponent(name))
        }
        for i in playlists.indices { playlists[i].isDirty = false }
        // The Mac now has these.
        pendingEventIds.removeAll()
        deletedPlaylists.removeAll()
        // Covers nothing uses any more.
        var keys = Set(songs.map(\.artworkKey))
        keys.formUnion(playlists.compactMap(\.artworkKey))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Self.artworkFolder.path)) ?? [] where !keys.contains((name as NSString).deletingPathExtension) {
            try? FileManager.default.removeItem(at: Self.artworkFolder.appendingPathComponent(name))
        }
        lastSync = Date()
        lastSyncSource = manifest.sourceName
        saveNow()
        let missing = songs.filter { !$0.isAvailable }.count
        var summary = "\(availableSongs.count) songs on \(UIDevice.current.name)"
        if !removed.isEmpty { summary += " · \(removed.count) removed" }
        if missing > 0 { summary += " · \(missing) still missing" }
        if damaged > 0 { summary += " · \(damaged) damaged, will resend" }
        return summary
    }

    // MARK: Importing files (Files app, Finder file sharing)

    /// Files dropped into the app's Documents folder with Finder (USB) or the Files app are imported.
    func importDocumentsFolder() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = Self.audioFiles(in: docs)
        guard !files.isEmpty else { return }
        importFiles(files, move: true)
    }

    nonisolated static func audioFiles(in folder: URL) -> [URL] {
        let exts: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "flac", "alac", "caf", "mp4"]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { exts.contains($0.pathExtension.lowercased()) }
    }

    func importFiles(_ urls: [URL], move: Bool) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task { [weak self] in
            var imported: [Song] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let song = await Self.makeLocalSong(from: url, move: move) { imported.append(song) }
            }
            guard let self else { return }
            let existingKeys = Set(self.songs.map { "\($0.title)|\($0.artist)|\($0.album)" })
            let fresh = imported.filter { !existingKeys.contains("\($0.title)|\($0.artist)|\($0.album)") }
            self.songs.append(contentsOf: fresh)
            self.isImporting = false
            self.importMessage = fresh.isEmpty ? "Those songs are already in your library." : "Added \(fresh.count) song\(fresh.count == 1 ? "" : "s")."
            self.save()
        }
    }

    private nonisolated static func makeLocalSong(from url: URL, move: Bool) async -> Song? {
        let id = UUID()
        let ext = url.pathExtension.lowercased()
        let destination = musicFolder.appendingPathComponent(id.uuidString + "." + ext)
        do {
            if move { try FileManager.default.moveItem(at: url, to: destination) } else { try FileManager.default.copyItem(at: url, to: destination) }
        } catch {
            return nil
        }
        let asset = AVURLAsset(url: destination)
        var title = url.deletingPathExtension().lastPathComponent, artist = "Unknown Artist", album = "Unknown Album", genre = "Unknown Genre"
        var albumArtist: String?, year: Int?, lyrics = "", trackNumber = 0, artData: Data?
        for item in (try? await asset.load(.metadata)) ?? [] {
            switch item.identifier {
            case .some(.commonIdentifierTitle), .some(.iTunesMetadataSongName), .some(.id3MetadataTitleDescription):
                if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
            case .some(.commonIdentifierArtist), .some(.iTunesMetadataArtist), .some(.id3MetadataLeadPerformer):
                if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
            case .some(.commonIdentifierAlbumName), .some(.iTunesMetadataAlbum), .some(.id3MetadataAlbumTitle):
                if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
            case .some(.iTunesMetadataAlbumArtist), .some(.id3MetadataBand):
                if let v = try? await item.load(.stringValue), !v.isEmpty { albumArtist = v }
            case .some(.iTunesMetadataUserGenre), .some(.id3MetadataContentType):
                if let v = try? await item.load(.stringValue), !v.isEmpty { genre = v }
            case .some(.iTunesMetadataReleaseDate), .some(.id3MetadataYear):
                if let v = try? await item.load(.stringValue), let y = Int(v.prefix(4)) { year = y }
            case .some(.iTunesMetadataLyrics), .some(.id3MetadataUnsynchronizedLyric):
                if let v = try? await item.load(.stringValue) { lyrics = v }
            case .some(.iTunesMetadataTrackNumber):
                if let d = try? await item.load(.dataValue), d.count >= 4 { trackNumber = Int(d[d.startIndex + 2]) << 8 | Int(d[d.startIndex + 3]) }
            case .some(.commonIdentifierArtwork), .some(.iTunesMetadataCoverArt), .some(.id3MetadataAttachedPicture):
                if artData == nil { artData = try? await item.load(.dataValue) }
            default: break
            }
        }
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let key = "local-" + id.uuidString
        if let artData, let image = UIImage(data: artData), let jpeg = image.preparingThumbnail(of: CGSize(width: 800, height: 800))?.jpegData(compressionQuality: 0.86) ?? image.jpegData(compressionQuality: 0.86) {
            try? jpeg.write(to: artworkURL(for: key))
        }
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        let info = SyncTrack(id: id, title: title, artist: artist, album: album, albumArtist: albumArtist, genre: genre,
                             duration: duration.isFinite ? duration : 0, year: year, trackNumber: trackNumber, discNumber: 1, isAtmos: false,
                             format: ["flac", "wav", "aif", "aiff", "alac"].contains(ext) ? "Lossless" : ext.uppercased(), lyrics: lyrics,
                             copyright: nil, isFavorite: false, playCount: 0, lastPlayedDate: nil, dateAdded: Date(), artworkKey: key,
                             fileExtension: ext, fileSize: Int64(size), bitDepth: nil, sampleRate: nil)
        var song = Song(info: info, fileName: destination.lastPathComponent)
        song.isLocal = true
        return song
    }
}

// MARK: - Artwork

final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()
    /// Decoded sizes per key, so one cover can be dropped without clearing the rest.
    private var sizes: [String: Set<Int>] = [:]
    /// Keys whose file just arrived or changed; nil means everything changed.
    let changes = PassthroughSubject<Set<String>?, Never>()

    init() { cache.countLimit = 400 }

    func cached(_ key: String, size: CGFloat) -> UIImage? {
        cache.object(forKey: "\(key)@\(Int(size))" as NSString)
    }

    func image(_ key: String, size: CGFloat) async -> UIImage? {
        if let hit = cached(key, size: size) { return hit }
        let url = MobileLibrary.artworkURL(for: key)
        let pixels = size * 3
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image {
            cache.setObject(image, forKey: "\(key)@\(Int(size))" as NSString)
            sizes[key, default: []].insert(Int(size))
        }
        return image
    }

    /// Only covers showing one of these keys reload.
    func invalidate(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        for key in keys {
            for size in sizes.removeValue(forKey: key) ?? [] { cache.removeObject(forKey: "\(key)@\(size)" as NSString) }
        }
        changes.send(keys)
    }

    func removeAll() {
        cache.removeAllObjects()
        sizes = [:]
        changes.send(nil)
    }
}
