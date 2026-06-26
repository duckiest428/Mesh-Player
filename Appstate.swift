//
//  AppState.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import Combine
import iTunesLibrary

// MARK: - Native Apple Music Integration Setup Instructions
// To enable this feature in Xcode:
// 1. Open your project target settings.
// 2. Go to the Info tab (or edit Info.plist directly).
// 3. Add the key "Privacy - Media Library Usage Description" (NSAppleMusicUsageDescription).
// 4. Set the value to a description, e.g., "Mesh Player requires access to your Apple Music library to import your playlists and favorite tracks."

// MARK: - Models

struct LocalTrack: Identifiable, Hashable {
    let id: UUID = UUID()
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: TimeInterval
    var fileURL: URL?
    var coverImageName: String // SF Symbol name or asset image
    var localCoverURL: URL? = nil // Local artwork image file URL (e.g. cover.jpg)
    var embeddedArtData: Data? = nil // Raw album artwork extracted directly from audio files
    var dateAdded: Date
    var isAtmos: Bool
    var fileSize: String
    var lyrics: String
    var isFavorite: Bool = false
    var playCount: Int = 0
    var format: String = "AAC 256kbps"
}

struct PlaylistTrack: Identifiable, Hashable {
    let id: UUID = UUID()
    var track: LocalTrack
}

struct Playlist: Identifiable, Hashable {
    let id: UUID = UUID()
    var name: String
    var description: String
    var isImported: Bool
    var playlistTracks: [PlaylistTrack]
    
    var tracks: [LocalTrack] {
        return playlistTracks.map { $0.track }
    }
}

struct LocalAlbum: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let artist: String
    let tracksCount: Int
    let trackRepresentative: LocalTrack
}

struct LocalArtist: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tracksCount: Int
    let trackRepresentative: LocalTrack
}

struct LocalGenre: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tracksCount: Int
    let trackRepresentative: LocalTrack
}

struct SyncedLyricLine: Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: TimeInterval
    let text: String
    var isBreak: Bool
    var breakStart: TimeInterval
    var breakEnd: TimeInterval
    var endTime: TimeInterval
    
    init(id: UUID = UUID(), timestamp: TimeInterval, text: String, isBreak: Bool = false, breakStart: TimeInterval = 0.0, breakEnd: TimeInterval = 0.0, endTime: TimeInterval = 0.0) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isBreak = isBreak
        self.breakStart = breakStart
        self.breakEnd = breakEnd
        self.endTime = endTime
    }
}

// MARK: - Themes Structure

struct ThemeColor {
    let background: Color
    let sidebarBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let cardBackground: Color
    let isDark: Bool
}

// MARK: - App State Context

import SwiftUI
import AppKit
import AVFoundation

struct AnimatedArtworkView: NSViewRepresentable {
    let track: LocalTrack
    let cornerRadius: CGFloat
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.cornerRadius = cornerRadius
        playerLayer.masksToBounds = true
        view.layer?.addSublayer(playerLayer)
        
        context.coordinator.playerLayer = playerLayer
        updatePlayer(for: track, in: context)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.currentTrackId != track.id {
            updatePlayer(for: track, in: context)
        }
        context.coordinator.playerLayer?.frame = nsView.bounds
    }
    
    private func updatePlayer(for track: LocalTrack, in context: Context) {
        context.coordinator.currentTrackId = track.id
        context.coordinator.player?.pause()
        context.coordinator.player = nil
        context.coordinator.playerLayer?.player = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let videoURL = self.findVideoURL(for: track) {
                DispatchQueue.main.async {
                    if context.coordinator.currentTrackId == track.id {
                        let player = AVPlayer(url: videoURL)
                        player.isMuted = true
                        context.coordinator.player = player
                        context.coordinator.playerLayer?.player = player
                        player.play()
                        
                        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                            player.seek(to: .zero)
                            player.play()
                        }
                    }
                }
            }
        }
    }
    
    private func findVideoURL(for track: LocalTrack) -> URL? {
        let extensions = ["mp4", "mov", "m4v"]
        
        if let fileURL = track.fileURL {
            let baseUrl = fileURL.deletingPathExtension()
            for ext in extensions {
                let videoURL = baseUrl.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
        }
        
        if let coverURL = track.localCoverURL {
            let baseUrl = coverURL.deletingPathExtension()
            for ext in extensions {
                let videoURL = baseUrl.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
            
            let dirUrl = coverURL.deletingLastPathComponent()
            for ext in extensions {
                let videoURL = dirUrl.appendingPathComponent("artwork").appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
        }
        
        if let fileURL = track.fileURL {
            let asset = AVAsset(url: fileURL)
            if asset.tracks(withMediaType: .video).count > 0 {
                return fileURL
            }
        }
        
        return nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var currentTrackId: UUID?
    }
}

class LibraryManager {
    static let shared = LibraryManager()
    
    let libraryDirectory: URL
    
    private init() {
        let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
        libraryDirectory = musicDir.appendingPathComponent("Mesh Player")
        
        if !FileManager.default.fileExists(atPath: libraryDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create Mesh Player library directory: \(error)")
            }
        }
    }
    
    func organizeAndCopyFile(at sourceURL: URL, trackMetadata: LocalTrack) -> URL? {
        let artistDir = libraryDirectory.appendingPathComponent("Artists").appendingPathComponent(trackMetadata.artist.isEmpty ? "Unknown Artist" : trackMetadata.artist)
        let albumDir = artistDir.appendingPathComponent(trackMetadata.album.isEmpty ? "Unknown Album" : trackMetadata.album)
        
        do {
            if !FileManager.default.fileExists(atPath: albumDir.path) {
                try FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)
            }
            
            let filename = trackMetadata.title.isEmpty ? sourceURL.lastPathComponent : "\(trackMetadata.title).\(sourceURL.pathExtension)"
            // Sanitize filename
            let sanitizedFilename = filename.replacingOccurrences(of: "/", with: "_")
            let destinationURL = albumDir.appendingPathComponent(sanitizedFilename)
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL // Already organized
            }
            
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Failed to organize file: \(error)")
            return nil
        }
    }
}

class AppStateManager: ObservableObject {
    enum RightSidebarPanel: String, CaseIterable {
        case none, lyrics, queue, output
    }
    @Published var activeRightSidebar: RightSidebarPanel = .none
    @Published var selectedTab: String? = "songs" {
        didSet {
            activeFilterType = nil
            activeFilterValue = nil
            searchKeyword = ""
        }
    }
    
    @Published var activeQueue: [LocalTrack] = []
    @Published var unshuffleQueue: [LocalTrack] = []
    @Published var isQueueShuffled: Bool = false
    @Published var removePlaylistSongsFromLibrary: Bool = false
    
    // Manage active queue tracking
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
        if activeQueue.isEmpty {
            // Fallback
            if let idx = tracks.firstIndex(where: { $0.id == current.id }) {
                let nextIdx = (idx + 1) % tracks.count
                engine.playTrack(tracks[nextIdx])
            }
            return
        }
        guard let idx = activeQueue.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIdx = (idx + 1) % activeQueue.count
        engine.playTrack(activeQueue[nextIdx])
    }
    
    func playPrevious(engine: AudioEngineManager) {
        guard let current = engine.currentTrack else { return }
        if activeQueue.isEmpty {
            // Fallback
            if let idx = tracks.firstIndex(where: { $0.id == current.id }) {
                let prevIdx = (idx - 1 + tracks.count) % tracks.count
                engine.playTrack(tracks[prevIdx])
            }
            return
        }
        guard let idx = activeQueue.firstIndex(where: { $0.id == current.id }) else { return }
        let prevIdx = (idx - 1 + activeQueue.count) % activeQueue.count
        engine.playTrack(activeQueue[prevIdx])
    }
    @Published var searchKeyword: String = ""
    @Published var sortCriteria: String = "dateAdded" // "dateAdded", "title", "artist", "album", "playCount", "duration"
    @Published var sortAscending: Bool = false
    @Published var selectedTrackId: UUID? = nil
    @Published var activeFilterType: String? = nil
    @Published var activeFilterValue: String? = nil
    @Published var isShuffleActive: Bool = false
    
    // Core settings mapped from user preferences settings panel
    @Published var currentThemeName: String = "Space Gray"
    @Published var autoScrollLyrics: Bool = true
    @Published var showDockArtwork: Bool = false
    @Published var enableAtmos: Bool = true
    @Published var eqMode: String = "Flat (Default Lossless)"
    @Published var crossfadeGap: Double = 4.0
    @Published var spatialAudioActive: Bool = false
    
    // Visible details columns checkboxes (matching React preferences)
    @Published var showTimeColumn: Bool = true
    @Published var showArtistColumn: Bool = true
    @Published var showAlbumColumn: Bool = true
    @Published var showGenreColumn: Bool = true
    @Published var showFavoritesColumn: Bool = true
    @Published var showPlaysColumn: Bool = true
    @Published var showDateAddedColumn: Bool = true
    @Published var showFormatColumn: Bool = true
    
    var theme: ThemeColor {
        switch currentThemeName {
        case "Midnight Indigo":
            return ThemeColor(
                background: Color(red: 0.04, green: 0.02, blue: 0.08),
                sidebarBackground: Color(red: 0.07, green: 0.04, blue: 0.12),
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.6),
                accent: Color(red: 0.60, green: 0.35, blue: 0.95),
                cardBackground: Color.white.opacity(0.08),
                isDark: true
            )
        case "Sakura Blossom":
            return ThemeColor(
                background: Color(red: 1.00, green: 0.94, blue: 0.95),
                sidebarBackground: Color(red: 1.00, green: 0.89, blue: 0.91),
                textPrimary: Color(red: 0.36, green: 0.18, blue: 0.21),
                textSecondary: Color(red: 0.36, green: 0.18, blue: 0.21).opacity(0.6),
                accent: Color(red: 1.00, green: 0.42, blue: 0.54),
                cardBackground: Color.white.opacity(0.8),
                isDark: false
            )
        case "Sunset Glow":
            return ThemeColor(
                background: Color(red: 0.12, green: 0.06, blue: 0.04),
                sidebarBackground: Color(red: 0.18, green: 0.10, blue: 0.07),
                textPrimary: Color(red: 0.92, green: 0.85, blue: 0.82),
                textSecondary: Color(red: 0.92, green: 0.85, blue: 0.82).opacity(0.6),
                accent: .orange,
                cardBackground: Color(red: 0.22, green: 0.12, blue: 0.09),
                isDark: true
            )
        case "Cyber Neon":
            return ThemeColor(
                background: Color.black,
                sidebarBackground: Color(red: 0.05, green: 0.02, blue: 0.10),
                textPrimary: Color(red: 0.85, green: 0.89, blue: 1.00),
                textSecondary: Color(red: 0.85, green: 0.89, blue: 1.00).opacity(0.6),
                accent: .cyan,
                cardBackground: Color(red: 0.08, green: 0.04, blue: 0.14),
                isDark: true
            )
        case "True Black":
            return ThemeColor(
                background: .black,
                sidebarBackground: .black,
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.6),
                accent: .white,
                cardBackground: Color(white: 0.03),
                isDark: true
            )
        case "Midnight Blue":
            return ThemeColor(
                background: Color(red: 0.0, green: 0.04, blue: 0.09),
                sidebarBackground: Color(red: 0.0, green: 0.07, blue: 0.15),
                textPrimary: Color(red: 0.88, green: 0.91, blue: 0.94),
                textSecondary: Color(red: 0.88, green: 0.91, blue: 0.94).opacity(0.6),
                accent: Color(red: 0.22, green: 0.74, blue: 0.97),
                cardBackground: Color(red: 0.0, green: 0.09, blue: 0.19),
                isDark: true
            )
        case "Y2K / Skeuomorphic (Frutiger Aero)":
            return ThemeColor(
                background: Color(red: 0.89, green: 0.96, blue: 0.98),
                sidebarBackground: Color(red: 0.95, green: 0.98, blue: 1.0),
                textPrimary: Color(red: 0.05, green: 0.23, blue: 0.40),
                textSecondary: Color(red: 0.05, green: 0.23, blue: 0.40).opacity(0.6),
                accent: Color(red: 0.13, green: 0.59, blue: 0.95),
                cardBackground: .white,
                isDark: false
            )
        case "Cyberpunk":
            return ThemeColor(
                background: Color(red: 0.06, green: 0.06, blue: 0.08),
                sidebarBackground: Color(red: 0.08, green: 0.08, blue: 0.11),
                textPrimary: Color(red: 1.0, green: 0.92, blue: 0.23),
                textSecondary: Color(red: 1.0, green: 0.92, blue: 0.23).opacity(0.6),
                accent: Color(red: 0.0, green: 0.90, blue: 1.0),
                cardBackground: Color(red: 0.11, green: 0.11, blue: 0.14),
                isDark: true
            )
        case "Vaporwave":
            return ThemeColor(
                background: Color(red: 0.90, green: 0.80, blue: 0.95),
                sidebarBackground: Color(red: 0.95, green: 0.90, blue: 0.98),
                textPrimary: Color(red: 0.29, green: 0.08, blue: 0.29),
                textSecondary: Color(red: 0.29, green: 0.08, blue: 0.29).opacity(0.6),
                accent: Color(red: 0.78, green: 0.15, blue: 1.0),
                cardBackground: Color.white.opacity(0.5),
                isDark: false
            )
        case "Warm Coffee":
            return ThemeColor(
                background: Color(red: 0.96, green: 0.92, blue: 0.87),
                sidebarBackground: Color(red: 0.92, green: 0.87, blue: 0.80),
                textPrimary: Color(red: 0.29, green: 0.23, blue: 0.20),
                textSecondary: Color(red: 0.29, green: 0.23, blue: 0.20).opacity(0.6),
                accent: Color(red: 0.55, green: 0.35, blue: 0.17),
                cardBackground: Color(red: 0.98, green: 0.93, blue: 0.85),
                isDark: false
            )
        default: // Space Gray / Classic Dark
            return ThemeColor(
                background: Color(red: 0.09, green: 0.09, blue: 0.11),
                sidebarBackground: Color(red: 0.06, green: 0.06, blue: 0.08),
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.6),
                accent: Color(red: 0.98, green: 0.18, blue: 0.33), // Apple Crimson Red
                cardBackground: Color.white.opacity(0.06),
                isDark: true
            )
        }
    }
    
    @Published var playlists: [Playlist] = [
        Playlist(name: "Favorites (Apple Music)", description: "Imported from Apple Music App preferences", isImported: true, playlistTracks: [])
    ]
    
    @Published var tracks: [LocalTrack] = []
    
    func upsertTrack(_ track: LocalTrack) {
        if let idx = tracks.firstIndex(where: {
            ($0.fileURL != nil && $0.fileURL?.path == track.fileURL?.path) ||
            ($0.title == track.title && $0.artist == track.artist && $0.album == track.album)
        }) {
            // Update metadata but keep user-specific state like isFavorite, playCount, dateAdded
            var updated = tracks[idx]
            updated.title = track.title
            updated.artist = track.artist
            updated.album = track.album
            updated.genre = track.genre
            updated.duration = track.duration
            updated.fileURL = track.fileURL
            updated.coverImageName = track.coverImageName
            updated.localCoverURL = track.localCoverURL
            updated.embeddedArtData = track.embeddedArtData
            updated.isAtmos = track.isAtmos
            updated.fileSize = track.fileSize
            updated.lyrics = track.lyrics
            updated.format = track.format
            tracks[idx] = updated
        } else {
            tracks.insert(track, at: 0)
        }
    }
    
    func addTrackToPlaylist(track: LocalTrack, playlistId: UUID) {
        if let idx = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[idx].playlistTracks.append(PlaylistTrack(track: track))
        }
    }
    
    func createNewPlaylist(name: String, initialTrack: LocalTrack? = nil) {
        var newPlaylist = Playlist(name: name, description: "", isImported: false, playlistTracks: [])
        if let track = initialTrack {
            newPlaylist.playlistTracks.append(PlaylistTrack(track: track))
        }
        playlists.append(newPlaylist)
    }
    
    func deletePlaylist(_ id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let playlist = playlists[index]
        playlists.remove(at: index)
        
        if removePlaylistSongsFromLibrary {
            let trackIds = Set(playlist.tracks.map { $0.id })
            tracks.removeAll { trackIds.contains($0.id) }
        }
        if selectedTab == "playlist-\(id.uuidString)" {
            selectedTab = "songs"
        }
    }
    
    func removeTrackFromPlaylist(trackId: UUID, playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].playlistTracks.removeAll { $0.track.id == trackId }
        
        if removePlaylistSongsFromLibrary {
            tracks.removeAll { $0.id == trackId }
        }
    }
    
    func toggleFavorite(track: LocalTrack) {
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx].isFavorite.toggle()
        }
    }
    
    // MARK: - Dynamic Library Grouping Lists for Albums/Artists/Genres
    var albumsList: [LocalAlbum] {
        var dict: [String: [LocalTrack]] = [:]
        for track in tracks {
            dict[track.album, default: []].append(track)
        }
        return dict.map { (key, list) in
            LocalAlbum(name: key, artist: list.first?.artist ?? "Unknown Artist", tracksCount: list.count, trackRepresentative: list.first!)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    var recentlyAddedAlbumsList: [LocalAlbum] {
        var dict: [String: [LocalTrack]] = [:]
        for track in tracks {
            dict[track.album, default: []].append(track)
        }
        return dict.map { (key, list) in
            LocalAlbum(name: key, artist: list.first?.artist ?? "Unknown Artist", tracksCount: list.count, trackRepresentative: list.max(by: { $0.dateAdded < $1.dateAdded })!)
        }.sorted { $0.trackRepresentative.dateAdded > $1.trackRepresentative.dateAdded }
    }
    
    var artistsList: [LocalArtist] {
        var dict: [String: [LocalTrack]] = [:]
        for track in tracks {
            dict[track.artist, default: []].append(track)
        }
        return dict.map { (key, list) in
            LocalArtist(name: key, tracksCount: list.count, trackRepresentative: list.first!)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    var genresList: [LocalGenre] {
        var dict: [String: [LocalTrack]] = [:]
        for track in tracks {
            dict[track.genre, default: []].append(track)
        }
        return dict.map { (key, list) in
            LocalGenre(name: key, tracksCount: list.count, trackRepresentative: list.first!)
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    var filteredTracks: [LocalTrack] {
        var sorted = tracks
        
        // 1. First, check if there is an active sub-filter drill-down
        if let filterType = activeFilterType, let filterVal = activeFilterValue {
            if filterType == "album" {
                sorted = sorted.filter { $0.album == filterVal }
            } else if filterType == "artist" {
                sorted = sorted.filter { $0.artist == filterVal }
            } else if filterType == "genre" {
                sorted = sorted.filter { $0.genre == filterVal }
            }
        } else {
            // Apply sidebar selections
            if selectedTab == "songs" {
                // all tracks
            } else if let tab = selectedTab, tab.hasPrefix("playlist-") {
                let playlistIdString = String(tab.dropFirst("playlist-".count))
                if let playlist = playlists.first(where: { $0.id.uuidString == playlistIdString }) {
                    if playlist.name.contains("Favorites") {
                        sorted = tracks.filter { $0.isFavorite }
                    } else {
                        sorted = playlist.tracks
                    }
                }
            } else if selectedTab == "recently-added" {
                // sort default will be handled below
            } else if selectedTab == "albums" {
                var seen = Set<String>()
                sorted = tracks.filter { seen.insert($0.album).inserted }
            } else if selectedTab == "artists" {
                var seen = Set<String>()
                sorted = tracks.filter { seen.insert($0.artist).inserted }
            } else if selectedTab == "genres" {
                var seen = Set<String>()
                sorted = tracks.filter { seen.insert($0.genre).inserted }
            }
        }
        
        // 2. Sorting Criteria
        sorted.sort { a, b in
            let isLess: Bool
            switch sortCriteria {
            case "title":
                isLess = a.title.localizedCompare(b.title) == .orderedAscending
            case "artist":
                isLess = a.artist.localizedCompare(b.artist) == .orderedAscending
            case "album":
                isLess = a.album.localizedCompare(b.album) == .orderedAscending
            case "playCount":
                isLess = a.playCount < b.playCount
            case "duration":
                isLess = a.duration < b.duration
            case "genre":
                isLess = a.genre.localizedCompare(b.genre) == .orderedAscending
            case "favourites", "favorites":
                isLess = (a.isFavorite ? 1 : 0) < (b.isFavorite ? 1 : 0)
            case "format":
                isLess = (a.isAtmos ? 1 : 0) < (b.isAtmos ? 1 : 0)
            default: // dateAdded (or recently-added tab default)
                isLess = a.dateAdded < b.dateAdded
            }
            return sortAscending ? isLess : !isLess
        }
        
        // 3. Search text Filtering
        if !searchKeyword.isEmpty {
            sorted = sorted.filter {
                $0.title.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.artist.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.album.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.genre.localizedCaseInsensitiveContains(searchKeyword)
            }
        }
        
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
        
        // Dot opacities
        let d1Opacity = min(1.0, max(0.2, fraction / 0.33))
        let d2Opacity = min(1.0, max(0.2, (fraction - 0.33) / 0.33))
        let d3Opacity = min(1.0, max(0.2, (fraction - 0.66) / 0.34))
        
        HStack(spacing: 20) {
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .opacity(d1Opacity)
                .scaleEffect(d1Opacity > 0.6 ? 1.15 : 1.0)
            
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .opacity(d2Opacity)
                .scaleEffect(d2Opacity > 0.6 ? 1.15 : 1.0)
                
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .opacity(d3Opacity)
                .scaleEffect(d3Opacity > 0.6 ? 1.15 : 1.0)
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
            // Re-usable official Dolby symbol using high-precision path drawing
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

