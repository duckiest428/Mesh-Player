//
//  AppState.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import Combine

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

struct Playlist: Identifiable, Hashable {
    let id: UUID = UUID()
    var name: String
    var description: String
    var isImported: Bool
    var tracks: [LocalTrack]
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
    let id: UUID = UUID()
    let timestamp: TimeInterval
    let text: String
    var isBreak: Bool = false
    var breakStart: TimeInterval = 0.0
    var breakEnd: TimeInterval = 0.0
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

class AppStateManager: ObservableObject {
    enum RightSidebarPanel: String, CaseIterable {
        case none, lyrics, queue, output
    }
    @Published var activeRightSidebar: RightSidebarPanel = .none
    @Published var selectedTab: String? = "songs" {
        didSet {
            activeFilterType = nil
            activeFilterValue = nil
        }
    }
    @Published var searchKeyword: String = ""
    @Published var sortCriteria: String = "dateAdded" // "dateAdded", "title", "artist", "album", "playCount", "duration"
    @Published var sortAscending: Bool = false
    @Published var selectedTrackId: UUID? = nil
    @Published var activeFilterType: String? = nil
    @Published var activeFilterValue: String? = nil
    
    // Core settings mapped from user preferences settings panel
    @Published var currentThemeName: String = "Space Gray"
    @Published var autoScrollLyrics: Bool = true
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
        Playlist(name: "Favorites (Apple Music)", description: "Imported from Apple Music App preferences", isImported: true, tracks: [])
    ]
    
    @Published var tracks: [LocalTrack] = [
        LocalTrack(
            title: "Ambient Horizon (Atmos)",
            artist: "Heliosphere",
            album: "Floating Coordinates",
            genre: "Ambient",
            duration: 372,
            coverImageName: "globe.americas.fill",
            localCoverURL: nil,
            dateAdded: Date().addingTimeInterval(-86400 * 5),
            isAtmos: true,
            fileSize: "14.2 MB",
            lyrics: """
            [00:03.000] (Instrumental Intro)
            [00:10.000] Floating in the cosmic sea
            [00:18.000] Stars align for you and me
            [00:26.000] Dolby Atmos spatial dome
            [00:35.000] Infinite acoustic home
            [00:45.000] Resonating far and wide
            [00:54.000] Riding on the solar tide
            """,
            isFavorite: true,
            playCount: 15420,
            format: "Atmos"
        ),
        LocalTrack(
            title: "Midnight Breeze",
            artist: "Luna Lounge Trio",
            album: "Corner Table Jazz",
            genre: "Jazz",
            duration: 425,
            coverImageName: "music.note",
            localCoverURL: nil,
            dateAdded: Date(),
            isAtmos: false,
            fileSize: "28.5 MB",
            lyrics: """
            [00:04.000] Rain is drumming on the window
            [00:10.000] Coffee sits quiet and still
            [00:18.000] Midnight breeze begins to blow
            [00:25.000] Chasing shadows down the hill
            [00:34.000] Smoke rings rise towards the ceiling
            [00:42.000] Bringing back a peaceful feeling
            """,
            isFavorite: false,
            playCount: 9241,
            format: "ALAC 262kbps"
        ),
        LocalTrack(
            title: "Stellar Drift",
            artist: "Tokyo Synth Syndicate",
            album: "Arcade Odyssey",
            genre: "Synthwave",
            duration: 322,
            coverImageName: "sparkles",
            localCoverURL: nil,
            dateAdded: Date().addingTimeInterval(-86400 * 12),
            isAtmos: true,
            fileSize: "12.8 MB",
            lyrics: """
            [00:03.000] Neon grids and spatial arrays
            [00:08.000] Travelling back to eighties days
            [00:16.000] Synthetic pulse in stereo
            [00:23.000] Ready for the spatial show
            [00:31.000] Gridlines flow beneath our feet
            [00:39.000] Feel the driving custom beat
            """,
            isFavorite: true,
            playCount: 18765,
            format: "Atmos"
        )
    ]
    
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
