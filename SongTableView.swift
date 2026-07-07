//
//  SongTableView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import Combine
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
            .padding(.horizontal)
            .padding(.bottom, 8)
            .padding(.top, (state.selectedTab?.hasPrefix("playlist-") == true) ? 8 : 0)
            .background(Color.secondary.opacity(0.04))
            
            Divider()
            
            // Custom Song List Grid with dynamic Column Headers
            List {
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
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                
                Divider()
                
                ForEach(Array(state.filteredTracks.enumerated()), id: \.offset) { index, track in
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
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        track.id == state.selectedTrackId
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
                        state.selectedTrackId = track.id
                    }
                    .contextMenu {
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
                    }
                }
            }
            .listStyle(.inset)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        
                        // Handle only audio files
                        let audioExtensions = ["mp3", "m4a", "wav", "flac", "alac", "m4b", "aac", "mp4", "ogg"]
                        guard audioExtensions.contains(url.pathExtension.lowercased()) else { return }
                        
                        DispatchQueue.main.async {
                            let track = engine.parseTrackMetadata(from: url)
                            if let organizedURL = LibraryManager.shared.organizeAndCopyFile(at: url, trackMetadata: track) {
                                let updatedTrack = LocalTrack(
                                    title: track.title,
                                    artist: track.artist,
                                    album: track.album,
                                    genre: track.genre,
                                    duration: track.duration,
                                    fileURL: organizedURL,
                                    coverImageName: track.coverImageName,
                                    localCoverURL: track.localCoverURL,
                                    embeddedArtData: track.embeddedArtData,
                                    dateAdded: track.dateAdded,
                                    isAtmos: track.isAtmos,
                                    fileSize: track.fileSize,
                                    lyrics: track.lyrics,
                                    isFavorite: track.isFavorite,
                                    playCount: track.playCount,
                                    format: track.format
                                )
                                state.upsertTrack(updatedTrack)
                            }
                        }
                    }
                }
                return true
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
