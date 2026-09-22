import AVFoundation
import Combine
import CoreAudio
import SwiftUI
import iTunesLibrary

// MARK: - SongTableView.swift
//
//  SongTableView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

internal import UniformTypeIdentifiers

struct SongTableView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var trackToAdd: LocalTrack?
    
    var body: some View {
        VStack(spacing: 0) {
            
            if let tab = state.selectedTab, tab.hasPrefix("playlist-"),
               let uuidString = tab.components(separatedBy: "-").dropFirst().joined(separator: "-").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.removingPercentEncoding,
               let playlistUUID = UUID(uuidString: uuidString),
               let playlist = state.playlists.first(where: { $0.id == playlistUUID }) {
                
                let trackCount = playlist.tracks.count
                let totalDuration = playlist.tracks.reduce(0) { $0 + $1.duration }
                
                // Playlist Header Banner
                HStack(spacing: 30) {
                    // Artwork Container
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 220, height: 220)
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        if let firstTrack = playlist.tracks.first {
                            AsyncFlexibleThumbnailView(track: firstTrack, maxPixelSize: 440, theme: state.theme, cornerRadius: 12)
                                .frame(width: 220, height: 220)
                        } else {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 80))
                                .foregroundColor(state.theme.textSecondary.opacity(0.5))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Playlist")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(state.theme.accent)
                        
                        Text(playlist.name)
                            .font(.system(size: 36, weight: .black, design: .default))
                            .foregroundColor(state.theme.textPrimary)
                            .lineLimit(2)
                        
                        Text(playlist.description.isEmpty ? "Apple Music" : playlist.description)
                            .font(.title3)
                            .foregroundColor(state.theme.textSecondary)
                        
                        Text("\(trackCount) songs, \(formatTotalTime(totalDuration))")
                            .font(.subheadline)
                            .foregroundColor(state.theme.textSecondary)
                            .padding(.top, 4)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                if let firstTrack = state.filteredTracks.first {
                                    state.setQueue(tracks: state.filteredTracks, startTrack: firstTrack)
                                    engine.playTrack(firstTrack)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Play")
                                        .fontWeight(.semibold)
                                }
                                .frame(width: 120, height: 32)
                            }
                            .buttonStyle(.plain)
                            .background(state.theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            
                            Button(action: {
                                // Shuffle Play
                                if let randomTrack = state.filteredTracks.randomElement() {
                                    state.setQueue(tracks: state.filteredTracks, startTrack: randomTrack)
                                    engine.playTrack(randomTrack)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "shuffle")
                                    Text("Shuffle")
                                        .fontWeight(.semibold)
                                }
                                .frame(width: 120, height: 32)
                            }
                            .buttonStyle(.plain)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(state.theme.accent)
                            .cornerRadius(6)
                        }
                        .padding(.top, 10)
                    }
                    
                    Spacer()
                }
                .padding(32)
                .background(
                    ZStack {
                        if let firstTrack = playlist.tracks.first {
                            AsyncFlexibleThumbnailView(track: firstTrack, maxPixelSize: 600, theme: state.theme, cornerRadius: 0)
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 60)
                                .opacity(0.15)
                        }
                        LinearGradient(gradient: Gradient(colors: [state.theme.background.opacity(0.0), state.theme.background]), startPoint: .top, endPoint: .bottom)
                    }
                )
                .clipped()
            }
            
            // Search, dynamic sorting, and filter header strip
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search songs, artists, or albums...", text: $state.searchKeyword)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 300)
                
                Spacer()
                
                // Dynamic Sorting Picker Mirror
                HStack(spacing: 4) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Menu {
                        ForEach(["dateAdded", "title", "artist", "album", "playCount", "duration"], id: \.self) { criterion in
                            Button(action: { state.sortCriteria = criterion }) {
                                HStack {
                                    Text(getCriteriaLabel(criterion))
                                    if state.sortCriteria == criterion {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(getCriteriaLabel(state.sortCriteria))
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 140, alignment: .leading)
                }
                
                // Dynamic Sorting Order direction toggle
                Button(action: { state.sortAscending.toggle() }) {
                    Image(systemName: state.sortAscending ? "arrow.up" : "arrow.down")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .help("Toggle sorting direction")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.04))
            
            Divider()
            
            // Custom Song List Grid with dynamic Column Headers
            
                // Table header row Simulation matching state preferences with clickable sort gestures
                HStack {
                    Text(state.sortCriteria == "title" ? "Title \(state.sortAscending ? "▲" : "▼")" : "Title")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(state.sortCriteria == "title" ? state.theme.accent : state.theme.textSecondary)
                        .frame(width: 220, alignment: .leading)
                        .onTapGesture {
                            if state.sortCriteria == "title" {
                                state.sortAscending.toggle()
                            } else {
                                state.sortCriteria = "title"
                            }
                        }
                    
                    if state.showArtistColumn {
                        Text(state.sortCriteria == "artist" ? "Artist \(state.sortAscending ? "▲" : "▼")" : "Artist")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "artist" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 120, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "artist" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "artist"
                                }
                            }
                    }
                    
                    if state.showAlbumColumn {
                        Text(state.sortCriteria == "album" ? "Album \(state.sortAscending ? "▲" : "▼")" : "Album")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "album" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 140, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "album" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "album"
                                }
                            }
                    }
                    
                    if state.showGenreColumn {
                        Text(state.sortCriteria == "genre" ? "Genre \(state.sortAscending ? "▲" : "▼")" : "Genre")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "genre" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 80, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "genre" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "genre"
                                }
                            }
                    }
                    
                    if state.showYearColumn {
                        Text(state.sortCriteria == "year" ? "Year \(state.sortAscending ? "▲" : "▼")" : "Year")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "year" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 60, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "year" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "year"
                                }
                            }
                    }
                    
                    if state.showPlaysColumn {
                        Text(state.sortCriteria == "playCount" ? "Plays \(state.sortAscending ? "▲" : "▼")" : "Plays")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "playCount" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 80, alignment: .center)
                            .onTapGesture {
                                if state.sortCriteria == "playCount" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "playCount"
                                }
                            }
                    }
                    
                    if state.showDateAddedColumn {
                        Text(state.sortCriteria == "dateAdded" ? "Date Added \(state.sortAscending ? "▲" : "▼")" : "Date Added")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "dateAdded" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 90, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "dateAdded" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "dateAdded"
                                }
                            }
                    }
                    
                    if state.showFormatColumn {
                        Text(state.sortCriteria == "format" ? "Format \(state.sortAscending ? "▲" : "▼")" : "Format")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "format" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 60, alignment: .center)
                            .onTapGesture {
                                if state.sortCriteria == "format" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "format"
                                }
                            }
                    }
                    
                    Spacer()
                    
                    if state.showFavoritesColumn {
                        Text(state.sortCriteria == "favourites" || state.sortCriteria == "favorites" ? "Fav \(state.sortAscending ? "▲" : "▼")" : "Fav")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "favourites" || state.sortCriteria == "favorites" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 40, alignment: .center)
                            .onTapGesture {
                                if state.sortCriteria == "favourites" || state.sortCriteria == "favorites" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "favourites"
                                }
                            }
                    }
                    
                    if state.showTimeColumn {
                        Text(state.sortCriteria == "duration" ? "Time \(state.sortAscending ? "▲" : "▼")" : "Time")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "duration" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 50, alignment: .trailing)
                            .onTapGesture {
                                if state.sortCriteria == "duration" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "duration"
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                Divider()
                
                ScrollView {
                    LazyVStack(spacing: 2) {
ForEach(Array(state.filteredTracks.enumerated()), id: \.element.id) { index, track in
                    let isPlayingThis = engine.currentTrack?.id == track.id
                    
                    HStack {

                        // Title block with alignment play spacer (artwork completely removed as requested)
                        HStack(spacing: 8) {
                            if isPlayingThis {
                                AnimatedEQView(color: state.theme.accent, isPlaying: engine.isPlaying)
                                    .frame(width: 24)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(state.theme.textSecondary.opacity(0.6))
                                    .frame(width: 24, alignment: .trailing)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .fontWeight(isPlayingThis ? .bold : .regular)
                                    .foregroundColor(isPlayingThis ? state.theme.accent : state.theme.textPrimary)
                                    .lineLimit(1)
                                
                                if !state.showArtistColumn {
                                    InteractiveText(text: track.artist, color: state.theme.textSecondary, isCaption: true) {
                                        state.selectedTab = "artists"
                                        state.activeFilterType = "artist"
                                        state.activeFilterValue = track.artist
                                    }
                                }
                            }
                        }
                        .frame(width: 220, alignment: .leading)
                        
                        // Dynamic rendering of configured columns
                        if state.showArtistColumn {
                            InteractiveText(text: track.artist, color: state.theme.textSecondary) {
                                state.selectedTab = "artists"
                                state.activeFilterType = "artist"
                                state.activeFilterValue = track.artist
                            }
                            .frame(width: 120, alignment: .leading)
                        }
                        
                        if state.showAlbumColumn {
                            InteractiveText(text: track.album, color: state.theme.textSecondary) {
                                state.selectedTab = "albums"
                                state.activeFilterType = "album"
                                state.activeFilterValue = track.album
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        
                        if state.showGenreColumn {
                            Text(track.genre)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 80, alignment: .leading)
                        }
                        
                        if state.showYearColumn {
                            Text(track.year != nil ? "\(track.year!)" : "-")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                        }
                        
                        if state.showPlaysColumn {
                            Text("\(formatNumber(track.playCount)) plays")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(state.currentThemeName == "Classic Light" ? 0.05 : 0.2))
                                .cornerRadius(4)
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 80, alignment: .center)
                        }
                        
                        if state.showDateAddedColumn {
                            Text(formatDate(track.dateAdded))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 90, alignment: .leading)
                        }
                        
                        if state.showFormatColumn {
                            if track.isAtmos {
                                DolbyAtmosBadge(color: .blue, scale: 0.6, showText: true)
                                    .frame(width: 60, alignment: .center)
                            } else {
                                Text(track.format)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(state.theme.textSecondary.opacity(0.6))
                                    .frame(width: 60, alignment: .center)
                            }
                        }
                        
                        Spacer()
                        
                        if state.showFavoritesColumn {
                            Button(action: {
                                state.toggleFavorite(track: track)
                            }) {
                                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                                    .foregroundColor(track.isFavorite ? .red : state.theme.textSecondary.opacity(0.5))
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40, alignment: .center)
                            .help(track.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        }
                        
                        if state.showTimeColumn {
                            Text(formatTime(track.duration))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        
                        Menu {
                            Button("Play") {
                                state.setQueue(tracks: state.filteredTracks, startTrack: track)
                                engine.playTrack(track)
                            }
                            
                            Divider()
                            
                            Menu("Add to Playlist") {
                                Button("New Playlist...") {
                                    trackToAdd = track
                                    newPlaylistName = ""
                                    showNewPlaylistAlert = true
                                }
                                
                                Divider()
                                
                                ForEach(state.playlists) { playlist in
                                    Button(playlist.name) {
                                        state.addTrackToPlaylist(track: track, playlistId: playlist.id)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            if let tab = state.selectedTab, tab.hasPrefix("playlist-"),
                               let uuidString = tab.components(separatedBy: "-").dropFirst().joined(separator: "-").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.removingPercentEncoding,
                               let playlistUUID = UUID(uuidString: uuidString) {
                                Button("Remove from Playlist") {
                                    state.removeTrackFromPlaylist(trackId: track.id, playlistId: playlistUUID)
                                }
                            }
                            
                            Button("Show in Finder") {
                                if let url = track.fileURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .padding(.leading, 8)
                    }
                    .frame(minHeight: 36)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        state.selectedTrackIds.contains(track.id)
                        ? state.theme.accent.opacity(0.12)
                        : (isPlayingThis ? state.theme.accent.opacity(0.06) : Color.clear)
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        state.setQueue(tracks: state.filteredTracks, startTrack: track)
                        engine.playTrack(track)
                    }
                    .onTapGesture(count: 1) {
                        let flags = NSEvent.modifierFlags
                        if flags.contains(.shift) {
                            if let lastIdx = state.lastSelectedTrackIndex {
                                let start = min(lastIdx, index)
                                let end = max(lastIdx, index)
                                let range = state.filteredTracks[start...end].map { $0.id }
                                state.selectedTrackIds.formUnion(range)
                            } else {
                                state.selectedTrackIds = [track.id]
                                state.lastSelectedTrackIndex = index
                            }
                        } else if flags.contains(.command) {
                            if state.selectedTrackIds.contains(track.id) {
                                state.selectedTrackIds.remove(track.id)
                            } else {
                                state.selectedTrackIds.insert(track.id)
                            }
                            state.lastSelectedTrackIndex = index
                        } else {
                            state.selectedTrackIds = [track.id]
                            state.lastSelectedTrackIndex = index
                        }
                    }
                    .contextMenu {
                        let isSelected = state.selectedTrackIds.contains(track.id)
                        let targetTracks = isSelected ? state.selectedTrackIds.compactMap { id in state.tracks.first(where: { $0.id == id }) } : [track]
                        
                        Button("Play") {
                            state.setQueue(tracks: state.filteredTracks, startTrack: track)
                            engine.playTrack(track)
                        }
                        
                        Divider()
                        
                        Menu(targetTracks.count > 1 ? "Add \(targetTracks.count) Items to Playlist" : "Add to Playlist") {
                            Button("New Playlist...") {
                                trackToAdd = track // Only seeds with one, but standard UX for new playlist
                                newPlaylistName = ""
                                showNewPlaylistAlert = true
                            }
                            
                            Divider()
                            
                            ForEach(state.playlists) { playlist in
                                Button(playlist.name) {
                                    for t in targetTracks {
                                        state.addTrackToPlaylist(track: t, playlistId: playlist.id)
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        if let tab = state.selectedTab, tab.hasPrefix("playlist-"),
                           let uuidString = tab.components(separatedBy: "-").dropFirst().joined(separator: "-").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.removingPercentEncoding,
                           let playlistUUID = UUID(uuidString: uuidString) {
                            Button(targetTracks.count > 1 ? "Remove \(targetTracks.count) Items from Playlist" : "Remove from Playlist") {
                                for t in targetTracks {
                                    state.removeTrackFromPlaylist(trackId: t.id, playlistId: playlistUUID)
                                }
                            }
                        }
                        
                        Button("Show in Finder") {
                            let urls = targetTracks.compactMap { $0.fileURL }
                            if !urls.isEmpty {
                                NSWorkspace.shared.activateFileViewerSelecting(urls)
                            }
                        }
                    }
            }
        }
    }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                        // Handle only audio files
                        let audioExtensions = ["mp3", "m4a", "wav", "flac", "alac", "m4b", "aac", "mp4", "ogg"]
                        guard audioExtensions.contains(url.pathExtension.lowercased()) else { return }

                        Task {
                            do {
                                let track = engine.parseTrackMetadata(from: url)
                                if let organizedURL = try await LibraryManager.shared.organizeAndCopyFile(at: url, trackMetadata: track) {
                                    var updatedTrack = track
                                    updatedTrack.fileURL = organizedURL
                                    await MainActor.run {
                                        state.upsertTrack(updatedTrack)
                                    }
                                }
                            } catch {
                                print("Failed to import dropped file: \(error)")
                            }
                        }
                    }
                }
                return true
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert, actions: {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Create", action: {
                    if !newPlaylistName.isEmpty {
                        state.createNewPlaylist(name: newPlaylistName, initialTrack: trackToAdd)
                    }
                })
                Button("Cancel", role: .cancel, action: {})
            }, message: {
                Text("Enter a name for the new playlist.")
            })
        }
    }
    
    private func getCriteriaLabel(_ key: String) -> String {
        switch key {
        case "dateAdded": return "Date Added"
        case "title": return "Song Title"
        case "artist": return "Artist Name"
        case "album": return "Album Name"
        case "playCount": return "Plays Count"
        case "duration": return "Song Duration"
        default: return key.capitalized
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTime(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
    private func formatTotalTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h) hr \(m) min"
        } else {
            return "\(m) min"
        }
    }
}

struct AnimatedEQView: View {
    let color: Color
    let isPlaying: Bool
    
    @State private var phase: Bool = false
    
    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: isPlaying ? (phase ? 12 : 3) : 0)
                .animation(isPlaying ? .easeInOut(duration: 0.2).repeatForever(autoreverses: true) : .default, value: phase)
            
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: isPlaying ? (phase ? 4 : 12) : 0)
                .animation(isPlaying ? .easeInOut(duration: 0.25).repeatForever(autoreverses: true).delay(0.1) : .default, value: phase)
            
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: isPlaying ? (phase ? 10 : 5) : 0)
                .animation(isPlaying ? .easeInOut(duration: 0.22).repeatForever(autoreverses: true).delay(0.05) : .default, value: phase)
        }
        .frame(height: 12, alignment: .bottom)
        .onChange(of: isPlaying) { playing in
            if playing {
                phase.toggle()
            } else {
                phase = false
            }
        }
        .onAppear {
            if isPlaying {
                phase.toggle()
            }
        }
    }
}

struct InteractiveText: View {
    let text: String
    let color: Color
    var isCaption: Bool = false
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Text(text)
            .font(isCaption ? .caption : .body)
            .foregroundColor(isHovering ? .accentColor : color)
            .underline(isHovering)
            .lineLimit(1)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                action()
            }
    }
}

// MARK: - AlbumDetailView.swift
//
//  AlbumDetailView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-22.
//  SPDX-License-Identifier: Apache-2.0
//


struct AlbumDetailView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    var albumName: String
    
    @State private var fetchedCopyright: String? = nil
    @State private var fetchedArtwork: NSImage? = nil
    
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var trackToAdd: LocalTrack?
    @State private var showingAudioQualityPopover = false
    @State private var popupTitle: String = ""
    @State private var popupDescription: String = ""
    
    // Find all tracks in this album
    var albumTracks: [LocalTrack] {
        state.tracks.filter { $0.album == albumName }.sorted {
            if $0.discNumber != $1.discNumber {
                return $0.discNumber < $1.discNumber
            }
            if $0.parsedTrackNumber != $1.parsedTrackNumber {
                return $0.parsedTrackNumber < $1.parsedTrackNumber
            }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }
    
    // Representative track
    var representative: LocalTrack? {
        albumTracks.first
    }
    
    // Quality tags computed from album tracks
    var hasAtmos: Bool {
        albumTracks.contains(where: { $0.isAtmos || $0.format.lowercased().contains("atmos") })
    }
    
    var hasLossless: Bool {
        albumTracks.contains(where: {
            let fmt = $0.format.lowercased()
            return fmt.contains("lossless") || fmt.contains("alac") || fmt.contains("flac") || fmt.contains("wav")
        })
    }
    
    var kbpsTag: String? {
        if hasAtmos {
            return nil
        }
        for track in albumTracks {
            let fmt = track.format
            // Match numbers followed by kbps (e.g. 1411kbps, 320kbps)
            let lower = fmt.lowercased()
            if lower.contains("kbps") {
                if let range = fmt.range(of: "\\d+\\s*kbps", options: .regularExpression) {
                    return String(fmt[range])
                }
            }
        }
        return hasLossless ? "Lossless" : "256 kbps"
    }
    
    // Total duration of album
    var totalDurationText: String {
        let totalSecs = albumTracks.reduce(0.0) { $0 + $1.duration }
        let mins = Int(totalSecs) / 60
        return "\(mins) Minute\(mins == 1 ? "" : "s")"
    }
    
    var copyrightText: String {
        if let firstExplicit = albumTracks.first(where: { $0.copyright != nil && !$0.copyright!.isEmpty })?.copyright {
            return firstExplicit
        }
        if let fetched = fetchedCopyright, !fetched.isEmpty {
            return fetched
        }
        let yearStr = representative?.year != nil ? String(representative!.year!) : String(Calendar.current.component(.year, from: Date()))
        let artist = representative?.artist ?? "Unknown Artist"
        return "℗ \(yearStr) \(artist)"
    }
    

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                
                // LEFT SIDEBAR: Album Artwork, Editor Notes
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(state.theme.cardBackground)
                            .frame(width: 190, height: 190)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                                               if let rep = representative {
                            AsyncFlexibleThumbnailView(track: rep, maxPixelSize: 380, theme: state.theme, cornerRadius: 12)
                                .frame(width: 190, height: 190)
                                
                            AnimatedArtworkView(track: rep, cornerRadius: 12)
                                .frame(width: 190, height: 190)
                                .allowsHitTesting(false)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(state.theme.cardBackground)
                                .frame(width: 190, height: 190)
                        }
                    }
                    .frame(width: 190, height: 190)
                }
                .frame(width: 190)
                
                // RIGHT WORKSPACE: Header titles, Play Shuffles, Track Table Rows
                VStack(alignment: .leading, spacing: 18) {
                    
                    // Header group
                    VStack(alignment: .leading, spacing: 4) {
                        Text(albumName.hasSuffix(" - Single") ? String(albumName.dropLast(9)) : (albumName.hasSuffix("- Single") ? String(albumName.dropLast(8)) : albumName))
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(state.theme.textPrimary)
                        
                        Button(action: {
                            if let artist = representative?.artist {
                                state.selectedTab = "artists"
                                state.activeFilterType = "artist"
                                state.activeFilterValue = artist
                            }
                        }) {
                            Text(representative?.artist ?? "Unknown Artist")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(state.theme.accent)
                        }
                        .buttonStyle(.plain)
                        
                        HStack(spacing: 4) {
                            Text(albumName.contains("- Single") ? "Single" : "Album")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(state.theme.textSecondary)
                                
                            if let year = representative?.year {
                                Text("•")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(state.theme.textSecondary)
                                Text("\(year)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(state.theme.textSecondary)
                            }
                            
                            Text("•")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(state.theme.textSecondary)
                            
                            Button(action: {
                                if let g = representative?.genre {
                                    state.selectedTab = "songs"
                                    state.searchKeyword = g
                                }
                            }) {
                                Text(representative?.genre ?? "Alternative")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(state.theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovered in
                                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                            
                            Text("• \(albumTracks.count) Song\(albumTracks.count == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(state.theme.textSecondary)
                            
                            Text("• \(totalDurationText)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(state.theme.textSecondary)
                                
                            if let yearRecorded = representative?.year {
                                Text("• \(yearRecorded)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(state.theme.textSecondary)
                            }
                                
                            if let representative = representative {
                                Text("•")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(state.theme.textSecondary)
                                
                                AudioQualityTagsView(track: representative, theme: state.theme)
                            }
                        }
                    }
                    
                    // Action Pills
                    HStack(spacing: 12) {
                        Button(action: {
                            if !albumTracks.isEmpty {
                                state.setQueue(tracks: albumTracks, startTrack: albumTracks.first!)
                                engine.playTrack(albumTracks.first!)
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play")
                                    .fontWeight(.bold)
                            }
                            .frame(width: 80, height: 28)
                            .background(state.theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PremiumButtonStyle())
                        
                        Button(action: {
                            if !albumTracks.isEmpty {
                                let shuffled = albumTracks.shuffled()
                                state.setQueue(tracks: albumTracks, startTrack: shuffled.first!)
                                engine.playTrack(shuffled.first!)
                            }
                        }) {
                            HStack {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                                    .fontWeight(.bold)
                            }
                            .frame(width: 90, height: 28)
                            .background(state.theme.cardBackground)
                            .foregroundColor(state.theme.textPrimary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PremiumButtonStyle())
                        
                        Button(action: {
                            // Simulator Action: Already added indicator
                        }) {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Added")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.theme.textSecondary)
                        }
                        .disabled(true)
                    }
                    
                    // Songs Rows
                    VStack(spacing: 0) {
                        Divider()
                            .background(state.theme.textSecondary.opacity(0.12))
                        
                        let isMultiDisc = (albumTracks.map { $0.discNumber }.max() ?? 1) > 1
                        
                        ForEach(Array(albumTracks.enumerated()), id: \.element.id) { index, track in
                            let isPlaying = engine.currentTrack?.id == track.id
                            let showDiscHeader = isMultiDisc && (index == 0 || albumTracks[index - 1].discNumber != track.discNumber)
                            
                            if showDiscHeader {
                                HStack {
                                    Text("Disc \(track.discNumber)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(state.theme.textSecondary)
                                    Spacer()
                                }
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                                .padding(.horizontal, 8)
                                
                                Divider()
                                    .background(state.theme.textSecondary.opacity(0.12))
                            }
                            
                            HStack(spacing: 14) {
                                // Index
                                Text("\(track.parsedTrackNumber != 9999 && track.parsedTrackNumber > 0 ? track.parsedTrackNumber : index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(isPlaying ? state.theme.accent : state.theme.textSecondary.opacity(0.4))
                                    .frame(width: 18, alignment: .trailing)
                                
                                // Song metadata
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(track.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(isPlaying ? state.theme.accent : state.theme.textPrimary)
                                        
                                        if track.isAtmos {
                                            DolbyAtmosBadge(color: .blue, scale: 0.7, showText: false)
                                        }
                                    }
                                    
                                    Button(action: {
                                        state.selectedTab = "artists"
                                        state.activeFilterType = "artist"
                                        state.activeFilterValue = track.artist
                                    }) {
                                        Text(track.artist)
                                            .font(.system(size: 11))
                                            .foregroundColor(state.theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Spacer()
                                
                                // Format Spec label
                                if track.isAtmos {
                                    Text("Spatial Audio")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                        .padding(.trailing, 10)
                                } else {
                                    Text(track.format)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(state.theme.textSecondary.opacity(0.45))
                                        .padding(.trailing, 10)
                                }
                                
                                // Duration
                                Text(formatTime(track.duration))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(state.theme.textSecondary)
                                
                                // Double-dot / Three-dot options menu
                                Menu {
                                    Button("Play") {
                                        state.setQueue(tracks: albumTracks, startTrack: track)
                                        engine.playTrack(track)
                                    }
                                    
                                    Divider()
                                    
                                    Menu("Add to Playlist") {
                                        Button("New Playlist...") {
                                            trackToAdd = track
                                            newPlaylistName = ""
                                            showNewPlaylistAlert = true
                                        }
                                        
                                        Divider()
                                        
                                        ForEach(state.playlists) { playlist in
                                            Button(playlist.name) {
                                                state.addTrackToPlaylist(track: track, playlistId: playlist.id)
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button("Show in Finder") {
                                        if let url = track.fileURL {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(state.theme.textSecondary)
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 24)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(isPlaying ? state.theme.accent.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                state.setQueue(tracks: albumTracks, startTrack: track)
                                engine.playTrack(track)
                            }
                            
                            Divider()
                                .background(state.theme.textSecondary.opacity(0.12))
                        }
                    }
                    
                    // Copyright
                    Text(copyrightText)
                        .font(.system(size: 9.5))
                        .foregroundColor(state.theme.textSecondary.opacity(0.45))
                        .padding(.top, 14)
                }
            }
            .padding(24)
        }
        .onAppear {
            if let rep = representative, (rep.copyright == nil || rep.copyright!.isEmpty || rep.embeddedArtData == nil) {
                state.fetchITunesData(album: albumName, artist: rep.artist) { artwork, copyright in
                    if let copyright = copyright {
                        self.fetchedCopyright = copyright
                    }
                    if let artwork = artwork, let url = URL(string: artwork) {
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                                DispatchQueue.main.async {
                                    self.fetchedArtwork = img
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert, actions: {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create", action: {
                if !newPlaylistName.isEmpty {
                    state.createNewPlaylist(name: newPlaylistName, initialTrack: trackToAdd)
                }
            })
            Button("Cancel", role: .cancel, action: {})
        }, message: {
            Text("Enter a name for the new playlist.")
        })
    }
    
    // Formatting durations helper
    private func formatTime(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// Custom flow layout for tags row inside margins
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? 190
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for size in sizes {
            if currentX + size.width > width {
                currentX = 0
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            maxRowHeight = max(maxRowHeight, size.height)
            currentX += size.width + spacing
        }
        totalHeight = currentY + maxRowHeight
        return CGSize(width: width, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var maxRowHeight: CGFloat = 0
        
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            maxRowHeight = max(maxRowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

// MARK: - SidebarView.swift
//
//  SidebarView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

internal import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    // Store library tabs as state to make them interactive and movable!
    @State private var libraryTabs = ["home", "meshReplay", "songs", "albums", "artists", "genres", "recently-added"]
    
    var body: some View {
        List(selection: $state.selectedTab) {
            Section("Apple Music Library") {
                ForEach(libraryTabs, id: \.self) { tab in
                    if tab == "home" {
                        NavigationLink(value: "home") {
                            Label("Home", systemImage: "house")
                        }
                    } else if tab == "meshReplay" {
                        NavigationLink(value: "meshReplay") {
                            Label("Mesh Replay", systemImage: "sparkles.rectangle.stack.fill")
                        }
                    } else if tab == "songs" {
                        NavigationLink(value: "songs") {
                            Label("Songs", systemImage: "music.note.list")
                        }
                    } else if tab == "albums" {
                        NavigationLink(value: "albums") {
                            Label("Albums", systemImage: "square.stack")
                        }
                    } else if tab == "artists" {
                        NavigationLink(value: "artists") {
                            Label("Artists", systemImage: "music.mic")
                        }
                    } else if tab == "genres" {
                        NavigationLink(value: "genres") {
                            Label("Genres", systemImage: "guitars")
                        }
                    } else if tab == "recently-added" {
                        NavigationLink(value: "recently-added") {
                            Label("Recently Added", systemImage: "clock")
                        }
                    }
                }
                .onMove { indices, newOffset in
                    libraryTabs.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            
            Section("Playlists (Imported)") {
                ForEach(state.playlists) { playlist in
                    NavigationLink(value: "playlist-\(playlist.id.uuidString)") {
                        Label(playlist.name, systemImage: "music.note.house")
                    }
                    .contextMenu {
                        Button("Delete Playlist") {
                            state.deletePlaylist(playlist.id)
                        }
                    }
                }
            }
            
            Section("Import") {
                Button(action: scanLocalMusicDirectory) {
                     Label("Import Local Folders", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
            }
            
            Section("Expand") {
                Button(action: {
                    if let url = URL(string: "https://am-dl.pages.dev") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                     Label("Download from Apple Music", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let url = URL(string: "https://monochrome.tf") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                     Label("Download from Amazon Music", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
    
    private func processAndImportFile(at url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        guard ["mp3", "m4a", "flac", "wav", "aiff"].contains(fileExtension) else { return }
        
        var track = engine.parseTrackMetadata(from: url)
        
        let fileDateAdded = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        var fileSizeString = "Unknown"
        if let sizeDict = try? FileManager.default.attributesOfItem(atPath: url.path), let size = sizeDict[.size] as? Int64 {
            fileSizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        
        // Ensure format and other specific overrides
        let asset = AVAsset(url: url)
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let formatDescriptions = audioTrack.formatDescriptions
            for desc in formatDescriptions {
                let formatDesc = desc as! CMFormatDescription
                let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
                let byte1 = (subType >> 24) & 0xff
                let byte2 = (subType >> 16) & 0xff
                let byte3 = (subType >> 8) & 0xff
                let byte4 = subType & 0xff
                if let s1 = UnicodeScalar(byte1), let s2 = UnicodeScalar(byte2), let s3 = UnicodeScalar(byte3), let s4 = UnicodeScalar(byte4) {
                    let subTypeStr = "\(Character(s1))\(Character(s2))\(Character(s3))\(Character(s4))".trimmingCharacters(in: .whitespaces).lowercased()
                    if ["ec-3", "ec3", "mlp", "ac-3", "ac3", "atmos"].contains(where: { subTypeStr.contains($0) }) {
                        track.isAtmos = true
                        track.format = "Dolby Atmos (\(subTypeStr))"
                    }
                }
            }
        }
        
        track.dateAdded = fileDateAdded
        track.fileSize = fileSizeString
        track.lyrics = ""
        track.isFavorite = false
        track.playCount = 0
        
        DispatchQueue.main.async {
            self.state.upsertTrack(track)
            self.state.saveContext()
        }
    }
    
    private func importAppleMusicPlaylists() {
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = """
            tell application "Music"
                set output to ""
                set allPlaylists to user playlists
                repeat with p in allPlaylists
                    set pName to name of p
                    -- skip standard default ones if you want, but for now take all
                    set output to output & "PLAYLIST:" & pName & "\\n"
                    set pTracks to tracks of p
                    repeat with t in pTracks
                        try
                            set loc to location of t
                            set POSIXloc to POSIX path of loc
                            set fav to loved of t
                            set pc to played count of t
                            set output to output & "TRACK:" & POSIXloc & "|" & fav & "|" & pc & "\\n"
                        end try
                    end repeat
                end repeat
                return output
            end tell
            """
            
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: scriptSource) {
                let output = scriptObject.executeAndReturnError(&error)
                if let resultString = output.stringValue {
                    var newPlaylists: [Playlist] = []
                    var favTracks: [PlaylistTrack] = []
                    
                    let lines = resultString.components(separatedBy: .newlines)
                    var currentPlaylistName: String = ""
                    var currentTracks: [PlaylistTrack] = []
                    
                    for line in lines {
                        if line.hasPrefix("PLAYLIST:") {
                            if !currentPlaylistName.isEmpty && !currentTracks.isEmpty {
                                newPlaylists.append(Playlist(name: currentPlaylistName, description: "Imported from Apple Music", isImported: true, playlistTracks: currentTracks))
                            }
                            currentPlaylistName = String(line.dropFirst(9))
                            currentTracks = []
                        } else if line.hasPrefix("TRACK:") {
                            let dataStr = String(line.dropFirst(6))
                            let parts = dataStr.components(separatedBy: "|")
                            if parts.count >= 3 {
                                let path = parts[0]
                                let isLoved = parts[1] == "true"
                                let playCount = Int(parts[2]) ?? 0
                                let fileURL = URL(fileURLWithPath: path)
                                
                                if let trackIndex = self.state.tracks.firstIndex(where: { $0.fileURL == fileURL }) {
                                    let track = self.state.tracks[trackIndex]
                                    currentTracks.append(PlaylistTrack(track: track))
                                    
                                    DispatchQueue.main.async {
                                        if isLoved {
                                            self.state.tracks[trackIndex].isFavorite = true
                                        }
                                        if playCount > self.state.tracks[trackIndex].playCount {
                                            self.state.tracks[trackIndex].playCount = playCount
                                        }
                                    }
                                    
                                    if (isLoved || playCount > 20) && !favTracks.contains(where: { $0.track.id == track.id }) {
                                        favTracks.append(PlaylistTrack(track: track))
                                    }
                                }
                            }
                        }
                    }
                    if !currentPlaylistName.isEmpty && !currentTracks.isEmpty {
                        newPlaylists.append(Playlist(name: currentPlaylistName, description: "Imported from Apple Music", isImported: true, playlistTracks: currentTracks))
                    }
                    
                    if !favTracks.isEmpty {
                        newPlaylists.append(Playlist(name: "Favorites (Apple Music)", description: "Imported from Apple Music App preferences", isImported: true, playlistTracks: favTracks))
                    }
                    
                    DispatchQueue.main.async {
                        self.state.playlists.append(contentsOf: newPlaylists)
                        self.state.saveContext()
                    }
                } else if let error = error {
                    print("AppleScript execution failed: \\(error)")
                }
            }
        }
    }
    
    private func syncLibraryViaAppleScript() {
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = """
            tell application "Music"
                set output to ""
                set allTracks to tracks of library playlist 1
                repeat with t in allTracks
                    try
                        set loc to location of t
                        set POSIXloc to POSIX path of loc
                        set output to output & POSIXloc & "\\n"
                    end try
                end repeat
                return output
            end tell
            """
            
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: scriptSource) {
                let output = scriptObject.executeAndReturnError(&error)
                if let resultString = output.stringValue {
                    let lines = resultString.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    for line in lines {
                        let fileURL = URL(fileURLWithPath: line)
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            if !self.state.tracks.contains(where: { $0.fileURL?.path == fileURL.path }) {
                                self.processAndImportFile(at: fileURL)
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.state.saveContext()
                    }
                } else if let error = error {
                    print("AppleScript sync failed: \\(error)")
                }
            }
        }
    }
    
    private func scanLocalMusicDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Apple Music Media Library Folder"
        panel.prompt = "Choose Folder"
        panel.message = "Choose your Apple Music/Media directory with Artist and Album subfolders to import your music."
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.importTracksFromFolder(at: selectedURL)
                }
            }
        }
    }
    
    private func importTracksFromFolder(at folderURL: URL) {
        Task {
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [.isRegularFileKey, .localizedNameKey]
        
        let isScoped = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return
        }
        
        var importedTracks: [LocalTrack] = []
        let audioExtensions = ["mp3", "m4a", "wav", "flac", "alac", "m4b", "aac", "mp4", "ogg"]
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                guard let isRegularFile = resourceValues.isRegularFile else { continue }
                if isRegularFile {
                    let ext = fileURL.pathExtension.lowercased()
                    if audioExtensions.contains(ext) {
                        // Gather path components to detect Artist and Album
                        let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path, with: "")
                        let parts = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
                        
                        var title = fileURL.deletingPathExtension().lastPathComponent
                        var artist = "Unknown Artist"
                        var album = "Unknown Album"
                        
                        // If path is Artist/Album/Song.m4a
                        if parts.count >= 3 {
                            artist = parts[parts.count - 3]
                            album = parts[parts.count - 2]
                            title = fileURL.deletingPathExtension().lastPathComponent
                        } else if parts.count == 2 {
                            // If Artist/Song.m4a
                            artist = parts[parts.count - 2]
                            album = "Single"
                        }
                        
                        // Clean the song title to remove playlist/track numbering prefixes
                        title = cleanSongTitle(title)
                        
                        // Simple file size fetch helper
                        var fileSizeString = "Unknown Size"
                        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                           let size = attributes[.size] as? Int64 {
                            let mb = Double(size) / (1024.0 * 1024.0)
                            fileSizeString = String(format: "%.1f MB", mb)
                        }
                        
                        // Determine if it's potentially Dolby Atmos
                        let lowerName = title.lowercased()
                        var isAtmos = lowerName.contains("atmos") || lowerName.contains("spatial") || lowerName.contains("surround") || lowerName.contains("5.1")
                        
                        // Search for cover artwork inside the album folder
                        var coverURL: URL? = nil
                        let parentFolderURL = fileURL.deletingLastPathComponent()
                        if let enumerator = FileManager.default.enumerator(at: parentFolderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) {
                            for case let url as URL in enumerator {
                                let pathExt = url.pathExtension.lowercased()
                                if ["jpg", "jpeg", "png", "webp"].contains(pathExt) {
                                    coverURL = url
                                    break
                                }
                            }
                        }
                        
                        // Extract metadata from AVAsset directly!
                        let asset = AVAsset(url: fileURL)
                        
                        // Try reading embedded tags
                        var embeddedArtworkData: Data? = nil
                        for item in asset.metadata {
                            if item.commonKey == AVMetadataKey.commonKeyArtwork {
                                if let data = item.dataValue {
                                    embeddedArtworkData = data
                                    break
                                }
                            }
                        }
                        
                        // Read track info or use path fallbacks
                        var finalTitle = title
                        var finalArtist = artist
                        var finalAlbum = album
                        var finalGenre = "Alternative"
                        var finalDuration: TimeInterval = 240.0
                        var finalYear: Int? = nil
                        
                        let durationVal = asset.duration
                        let secs = CMTimeGetSeconds(durationVal)
                        if !secs.isNaN && secs > 0 {
                            finalDuration = secs
                        }
                        
                        for item in asset.metadata {
                            let idRaw = item.identifier?.rawValue.lowercased() ?? ""
                            if let commonKey = item.commonKey {
                                switch commonKey {
                                case AVMetadataKey.commonKeyTitle:
                                    if let val = item.stringValue, !val.isEmpty { finalTitle = val }
                                case AVMetadataKey.commonKeyArtist:
                                    if let val = item.stringValue, !val.isEmpty { finalArtist = val }
                                case AVMetadataKey.commonKeyAlbumName:
                                    if let val = item.stringValue, !val.isEmpty { finalAlbum = val }
                                case AVMetadataKey.commonKeyType:
                                    if let val = item.stringValue, !val.isEmpty { finalGenre = val }
                                case AVMetadataKey.commonKeyCreationDate:
                                    if let val = item.stringValue, let parsed = Int(val.prefix(4)) { finalYear = parsed }
                                default:
                                    break
                                }
                            }
                            if idRaw.contains("gen") {
                                if let val = item.stringValue, !val.isEmpty { finalGenre = val }
                            }
                            if idRaw.contains("year") || idRaw.contains("tdrc") || idRaw.contains("tdat") || idRaw.contains("tyer") || idRaw.contains("time") {
                                if let val = item.stringValue, let parsed = Int(val.prefix(4)) { finalYear = parsed }
                            }
                        }
                        
                        // Estimate format metadata and perform robust Dolby Atmos & Lossless analysis
                        let combinedMetaLower = "\(fileURL.lastPathComponent) \(finalTitle) \(finalAlbum) \(finalGenre) \(finalArtist)".lowercased()
                        var isCodecAtmos = false
                        var isLossless = false
                        let ext = fileURL.pathExtension.lowercased()
                        if ["flac", "wav", "aif", "aiff", "alac"].contains(ext) {
                            isLossless = true
                        }
                        
                        // Check structural track formats
                        if let audioTrack = asset.tracks(withMediaType: .audio).first {
                            let formatDescriptions = audioTrack.formatDescriptions
                            for desc in formatDescriptions {
                                let formatDesc = desc as! CMFormatDescription
                                let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
                                
                                // Convert FourCharCode to string safely
                                let byte1 = (subType >> 24) & 0xff
                                let byte2 = (subType >> 16) & 0xff
                                let byte3 = (subType >> 8) & 0xff
                                let byte4 = subType & 0xff
                                
                                if let scalar1 = UnicodeScalar(byte1),
                                   let scalar2 = UnicodeScalar(byte2),
                                   let scalar3 = UnicodeScalar(byte3),
                                   let scalar4 = UnicodeScalar(byte4) {
                                    let char1 = Character(scalar1)
                                    let char2 = Character(scalar2)
                                    let char3 = Character(scalar3)
                                    let char4 = Character(scalar4)
                                    let subTypeStr = "\(char1)\(char2)\(char3)\(char4)".trimmingCharacters(in: .whitespaces).lowercased()
                                    
                                    if ["ec-3", "ec3", "mlp", "ac-3", "ac3", "atmos"].contains(where: { subTypeStr.contains($0) }) {
                                        isCodecAtmos = true
                                    }
                                    if ["alac", "flac", "lpcm", "pcm"].contains(where: { subTypeStr.contains($0) }) {
                                        isLossless = true
                                    }
                                }
                            }
                        }
                        
                        isAtmos = isCodecAtmos || combinedMetaLower.contains("atmos") ||
                                  combinedMetaLower.contains("spatial") ||
                                  combinedMetaLower.contains("surround") ||
                                  combinedMetaLower.contains("5.1")
                        
                        var formatStr = "AAC 256kbps"
                        if isAtmos {
                            formatStr = "Dolby Atmos"
                        } else {
                            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                               let size = attributes[.size] as? Int64, finalDuration > 0 {
                                let estBitrate = Int(Double(size * 8) / (finalDuration * 1000.0))
                                if ext == "mp3" {
                                    let choices = [128, 160, 192, 256, 320]
                                    let closest = choices.min(by: { abs($0 - estBitrate) < abs($1 - estBitrate) }) ?? 320
                                    formatStr = "MP3 \(closest)kbps"
                                } else if ext == "m4a" || ext == "aac" {
                                    if isLossless {
                                        formatStr = "Lossless (ALAC)"
                                    } else {
                                        let choices = [128, 160, 256, 320]
                                        let closest = choices.min(by: { abs($0 - estBitrate) < abs($1 - estBitrate) }) ?? 256
                                        formatStr = "AAC \(closest)kbps"
                                    }
                                } else if ext == "wav" || ext == "flac" || ext == "alac" {
                                    formatStr = "Lossless (ALAC) \(estBitrate > 100 ? estBitrate : 1411)kbps"
                                } else {
                                    formatStr = "AUDIO \(estBitrate > 50 ? estBitrate : 256)kbps"
                                }
                            }
                        }
                        
                        // Scan for companion .lrc or .txt lyrics file (with the same name as the song) or any .lrc file in that folder
                        var lyricsContent = ""
                        
                        // Check standard id3/m4a lyrics tag first
                        for item in asset.metadata {
                            let idRaw = item.identifier?.rawValue.lowercased() ?? ""
                            let keyStr = (item.key as? String)?.lowercased() ?? ""
                            
                            if idRaw.contains("lyr") || idRaw.contains("uslt") || idRaw.contains("lyrics") ||
                               keyStr.contains("lyr") || keyStr.contains("uslt") || keyStr.contains("lyrics") {
                                if let val = item.stringValue, !val.isEmpty {
                                    lyricsContent = val.replacingOccurrences(of: "\n", with: "\\n")
                                    break
                                }
                            }
                        }
                        
                        let possibleLRCURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
                        let possibleTXTURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
                        
                        if fileManager.fileExists(atPath: possibleLRCURL.path) {
                            if let content = try? String(contentsOf: possibleLRCURL, encoding: .utf8) {
                                lyricsContent = content.replacingOccurrences(of: "\n", with: "\\n")
                            }
                        } else if fileManager.fileExists(atPath: possibleTXTURL.path) {
                            if let content = try? String(contentsOf: possibleTXTURL, encoding: .utf8) {
                                lyricsContent = content.replacingOccurrences(of: "\n", with: "\\n")
                            }
                        } else {
                            // Fallback: search for any .lrc file in same folder
                            if let enumerator = fileManager.enumerator(at: parentFolderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) {
                                for case let url as URL in enumerator {
                                    if url.pathExtension.lowercased() == "lrc" {
                                        if let content = try? String(contentsOf: url, encoding: .utf8) {
                                            lyricsContent = content.replacingOccurrences(of: "\n", with: "\\n")
                                            break
                                        }
                                    }
                                }
                            }
                        }
                        
                        var fileDateAdded = Date()
                        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path) {
                            if let creationDate = attrs[.creationDate] as? Date {
                                fileDateAdded = creationDate
                            } else if let modificationDate = attrs[.modificationDate] as? Date {
                                fileDateAdded = modificationDate
                            }
                        }
                        
                        let baseTrack = LocalTrack(
                            title: finalTitle,
                            artist: finalArtist,
                            album: finalAlbum,
                            genre: finalGenre,
                            duration: finalDuration,
                            fileURL: fileURL,
                            coverImageName: isAtmos ? "sparkles" : "music.note",
                            localCoverURL: coverURL,
                            embeddedArtData: embeddedArtworkData,
                            dateAdded: fileDateAdded,
                            isAtmos: isAtmos,
                            fileSize: fileSizeString,
                            lyrics: lyricsContent,
                            isFavorite: false,
                            playCount: 0,
                            format: formatStr
                        )
                        
                        // Copy into our internal library structure
                        if let organizedURL = try await LibraryManager.shared.organizeAndCopyFile(at: fileURL, trackMetadata: baseTrack) {
                            var track = baseTrack
                            track.fileURL = organizedURL
                            importedTracks.append(track)
                        }
                    }
                }
            } catch {
                print("Error scanning entry: \(error.localizedDescription)")
            }
        }
        
            if !importedTracks.isEmpty {
                await MainActor.run {
                    for track in importedTracks {
                        self.state.upsertTrack(track)
                    }
                    self.state.saveContext()
                    print("Successfully processed \(importedTracks.count) songs from selected folder!")
                }
            }
        }
    }
    
    private func cleanSongTitle(_ rawTitle: String) -> String {
        let titleStr = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^(\\d+[-_.]\\d+|\\d+)\\s*[-_.]?\\s*"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: titleStr.utf16.count)
            let cleaned = regex.stringByReplacingMatches(in: titleStr, options: [], range: range, withTemplate: "")
            if !cleaned.isEmpty {
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return titleStr
    }
}

// MARK: - LyricsSidebarView

struct LyricsSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14))
                        .foregroundColor(state.theme.accent)
                    Text("Synced Lyrics")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(state.theme.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(state.theme.sidebarBackground.opacity(0.5))
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Lyrics scroll view
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    if engine.parsedLyrics.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.system(size: 32))
                                .foregroundColor(state.theme.accent.opacity(0.8))
                            Text("No Lyrics Available")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.theme.textPrimary)
                            Text("Instrumental Atmos stream active.")
                                .font(.system(size: 9.5))
                                .foregroundColor(state.theme.textSecondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(engine.parsedLyrics) { line in
                                let isActive = isLineActive(line)
                                
                                Group {
                                    if line.isBreak {
                                        InstrumentalBreakDots(
                                            currentTime: timeTracker.currentTime,
                                            breakStart: line.breakStart,
                                            breakEnd: line.breakEnd
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .scaleEffect(0.65) // Scales wonderfully for small sidebars!
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundColor(isActive ? state.theme.textPrimary : state.theme.textPrimary.opacity(0.25))
                                            .scaleEffect(isActive ? 1.02 : 1.0)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    engine.seek(to: line.timestamp)
                                }
                                .id(line.id)
                            }
                        }
                        .padding(.vertical, 120)
                        .padding(.horizontal, 16)
                        .onChange(of: timeTracker.currentTime) { newValue in
                            if let currentActive = engine.parsedLyrics.last(where: { $0.timestamp <= newValue }) {
                                withAnimation {
                                    proxy.scrollTo(currentActive.id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 280)
        .background(state.theme.sidebarBackground)
    }
    
    private func isLineActive(_ line: SyncedLyricLine) -> Bool {
        if line.isBreak {
            return timeTracker.currentTime >= line.breakStart && timeTracker.currentTime <= line.breakEnd
        }
        return timeTracker.currentTime >= line.timestamp && timeTracker.currentTime < line.endTime
    }
}

// MARK: - QueueSidebarView

struct QueueSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker
    var isFullscreen: Bool = false
    
    var upcomingTracks: [LocalTrack] {
        guard let currentTrack = engine.currentTrack else { return [] }
        guard let currentIndex = state.activeQueue.firstIndex(where: { $0.id == currentTrack.id }) else { return [] }
        if state.activeQueue.count <= 1 { return [] }
        
        var sorted: [LocalTrack] = []
        for i in (currentIndex + 1)..<state.activeQueue.count {
            sorted.append(state.activeQueue[i])
        }
        return sorted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 14))
                        .foregroundColor(state.theme.accent)
                    Text("Playing Next")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(state.theme.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(state.theme.sidebarBackground.opacity(0.5))
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Now Playing Block
            if let current = engine.currentTrack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOW PLAYING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(state.theme.accent)
                        .tracking(1.5)
                    
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.theme.cardBackground)
                                .frame(width: 44, height: 44)
                            
                            if let artData = current.embeddedArtData, let nsImage = NSImage(data: artData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                            } else if let imageURL = current.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: current.coverImageName)
                                    .font(.system(size: 16))
                                    .foregroundColor(state.theme.accent)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(current.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.theme.textPrimary)
                                .lineLimit(1)
                            
                            Text(current.artist)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.02))
                
                Divider()
                    .background(state.theme.textSecondary.opacity(0.1))
            }
            
            // Scrolling list of next up
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("NEXT UP (\(upcomingTracks.count) TRACKS)")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(state.theme.textSecondary.opacity(0.5))
                            .tracking(1.2)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    if upcomingTracks.isEmpty {
                        VStack {
                            Spacer()
                            Text("No tracks queued next")
                                .font(.system(size: 11))
                                .foregroundColor(state.theme.textSecondary.opacity(0.4))
                                .padding(.vertical, 40)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(upcomingTracks.prefix(100)) { track in
                                Button(action: {
                                    engine.playTrack(track)
                                }) {
                                    HStack(spacing: 10) {
                                        AsyncThumbnailView(track: track, size: 32, theme: state.theme)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title) // Revert cleanTitle
                                                .font(.system(size: 10.5, weight: .bold))
                                                .foregroundColor(state.theme.textPrimary)
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(state.theme.textSecondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(state.theme.textSecondary.opacity(0.3))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(QueueRowButtonStyle(theme: state.theme))
                                .contextMenu {
                                    Button("Play Next") {
                                        engine.playTrack(track)
                                    }
                                    Button("Remove from Queue") {
                                        if let idx = state.activeQueue.firstIndex(where: { $0.id == track.id }) {
                                            state.activeQueue.remove(at: idx)
                                        }
                                    }
                                    Button("Add to Favorites") {
                                        if let idx = state.tracks.firstIndex(where: { $0.id == track.id }) {
                                            state.tracks[idx].isFavorite = true
                                            state.saveContext()
                                        }
                                    }
                                }
                            }
                            
                            if upcomingTracks.count > 100 {
                                Text("+ \(upcomingTracks.count - 100) MORE TRACKS IN QUEUE")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(state.theme.textSecondary.opacity(0.4))
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(width: isFullscreen ? 440 : 280)
        .background(isFullscreen ? Color.clear : state.theme.sidebarBackground)
        .background(isFullscreen ? AnyView(Rectangle().fill(Material.ultraThin).opacity(0.85)) : AnyView(Color.clear))
    }
}

struct QueueRowButtonStyle: ButtonStyle {
    var theme: ThemeColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.cardBackground.opacity(0.2) : Color.clear)
            .cornerRadius(6)
            .padding(.horizontal, 6)
    }
}

// MARK: - OutputDeviceSidebarView

struct SwiftOutputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String // "built-in" | "headphones" | "airplay" | "bluetooth"
    let hasAtmos: Bool
    let model: String
}

struct OutputDeviceSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker
    var isFullscreen: Bool = false
    
    @State private var connectingDeviceId: String? = nil
    @State private var volumes: [String: Double] = [
        "peteys-macbook": 0.75,
        "peteys-airpods-2": 0.60,
        "peteys-airpods-3": 0.55
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 14))
                        .foregroundColor(.indigo)
                    Text("Audio Output Device")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(state.theme.textPrimary)
                }
                
                Spacer()
                
                Text("CoreAudio")
                    .font(.system(size: 8, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(3)
                    .foregroundColor(state.theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(state.theme.sidebarBackground.opacity(0.5))
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Devices scrolling list
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SELECT OUTPUT ZONE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(state.theme.textSecondary.opacity(0.5))
                        .tracking(1.2)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    
                    ForEach(engine.availableOutputs) { device in
                        let isActive = device.id == engine.activeOutputId
                        let isConnecting = device.id == connectingDeviceId
                        let volumeBinding = Binding<Double>(
                            get: { volumes[device.id] ?? 0.5 },
                            set: { volumes[device.id] = $0 }
                        )
                        
                        VStack(spacing: 0) {
                            Button(action: {
                                if device.id != engine.activeOutputId && connectingDeviceId == nil {
                                    connectingDeviceId = device.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                        engine.setOutputDevice(id: device.id)
                                        connectingDeviceId = nil
                                    }
                                }
                            }) {
                                HStack(spacing: 12) {
                                    // Device Type Icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isActive ? Color.indigo : state.theme.cardBackground)
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: getIconName(type: device.type))
                                            .font(.system(size: 14))
                                            .foregroundColor(isActive ? .white : state.theme.textPrimary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(device.name)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(state.theme.textPrimary)
                                                .lineLimit(1)
                                            
                                            if device.hasAtmos {
                                                DolbyAtmosBadge(color: .blue, scale: 0.6, showText: false)
                                            }
                                        }
                                        
                                        Text(device.model)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(state.theme.textSecondary.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    if isConnecting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if isActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.indigo)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if isActive {
                                VStack(spacing: 8) {
                                    VStack(spacing: 4) {
                                        HStack {
                                            HStack(spacing: 4) {
                                                Image(systemName: "volume.2.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.indigo)
                                                Text("Zone Output Limit")
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundColor(state.theme.textSecondary)
                                            }
                                            Spacer()
                                            Text("\(Int(volumeBinding.wrappedValue * 100))%")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(state.theme.textSecondary)
                                        }
                                        
                                        Slider(value: volumeBinding, in: 0...1)
                                            .accentColor(.indigo)
                                            .controlSize(.small)
                                    }
                                    
                                    if device.type == "headphones" {
                                        Divider()
                                            .background(state.theme.textSecondary.opacity(0.12))
                                            .padding(.vertical, 4)
                                        
                                        VStack(spacing: 6) {
                                            HStack {
                                                HStack(spacing: 4) {
                                                    Text(" Spatial Audio")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(state.theme.textPrimary)
                                                    Text("(AirPods Simulation)")
                                                        .font(.system(size: 8))
                                                        .foregroundColor(state.theme.textSecondary.opacity(0.6))
                                                }
                                                Spacer()
                                                Text(state.spatialAudioActive ? "ACTIVE" : "OFF")
                                                    .font(.system(size: 7, weight: .black, design: .monospaced))
                                                    .foregroundColor(state.spatialAudioActive ? Color.blue : state.theme.textSecondary)
                                                    .padding(.horizontal, 4.5)
                                                    .padding(.vertical, 1.5)
                                                    .background(state.spatialAudioActive ? Color.blue.opacity(0.15) : state.theme.textSecondary.opacity(0.1))
                                                    .cornerRadius(3.5)
                                            }
                                            
                                            HStack(spacing: 6) {
                                                Button(action: { state.spatialAudioActive = false }) {
                                                    Text("Stereo")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 6)
                                                        .background(!state.spatialAudioActive ? state.theme.accent.opacity(0.15) : state.theme.cardBackground)
                                                        .foregroundColor(!state.spatialAudioActive ? state.theme.accent : state.theme.textSecondary)
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button(action: { state.spatialAudioActive = true }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "dot.radiowaves.left.and.right")
                                                            .font(.system(size: 8))
                                                        Text("Spatialize")
                                                    }
                                                    .font(.system(size: 10, weight: .bold))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 6)
                                                    .background(state.spatialAudioActive ? Color.blue.opacity(0.15) : state.theme.cardBackground)
                                                    .foregroundColor(state.spatialAudioActive ? Color.blue : state.theme.textSecondary)
                                                    .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            
                                            if state.spatialAudioActive {
                                                Text("• Simulating Spatial Head Field •")
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(.blue)
                                                    .padding(.top, 2)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(isActive ? Color.indigo.opacity(0.06) : Color.clear)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isActive ? Color.indigo.opacity(0.2) : Color.clear, lineWidth: 1)
                        )
                        .padding(.horizontal, 10)
                    }
                }
            }
            
            Spacer()
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Footer
            Text("LATENCY HANDSHAKE: 2ms • AAC LOSSLESS DIRECT")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(state.theme.textSecondary.opacity(0.4))
                .padding(.vertical, 8)
        }
        .frame(width: isFullscreen ? 440 : 280)
        .background(isFullscreen ? Color.clear : state.theme.sidebarBackground)
        .background(isFullscreen ? AnyView(Rectangle().fill(Material.ultraThin).opacity(0.85)) : AnyView(Color.clear))
    }
    
    private func getIconName(type: String) -> String {
        switch type {
        case "built-in":
            return "laptopcomputer"
        case "headphones":
            return "airpodspro"
        case "airplay":
            return "tv.and.mediabox"
        default: // bluetooth / wireless
            return "speaker.wave.2"
        }
    }
}

