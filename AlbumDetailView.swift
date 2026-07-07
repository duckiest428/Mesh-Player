//
//  AlbumDetailView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-22.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI

struct AlbumDetailView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    var albumName: String
    
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
            return $0.parsedTrackNumber < $1.parsedTrackNumber
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
                        
                        ForEach(Array(albumTracks.enumerated()), id: \.offset) { index, track in
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
                                Text("\(track.parsedTrackNumber > 0 ? track.parsedTrackNumber : index + 1)")
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
