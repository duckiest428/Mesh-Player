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
    
    // Find all tracks in this album
    var albumTracks: [LocalTrack] {
        state.tracks.filter { $0.album == albumName }
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
        if albumTracks.count == 1 {
            return "1 Song, \(mins) Minutes"
        } else {
            return "\(albumTracks.count) Songs, \(mins) Minutes"
        }
    }
    
    var copyrightText: String {
        let year = "2026"
        let artist = representative?.artist ?? "Music Corp"
        return "℗ \(year) \(artist) Records LLC, licensed under native CoreAudio pipeline."
    }
    

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                
                // LEFT SIDEBAR: Album Artwork, Format tags, Editor Notes
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(state.theme.cardBackground)
                            .frame(width: 190, height: 190)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        if let rep = representative {
                            if let artData = rep.embeddedArtData, let nsImage = NSImage(data: artData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 190, height: 190)
                                    .cornerRadius(12)
                            } else if let imageURL = rep.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 190, height: 190)
                                    .cornerRadius(12)
                            } else {
                                Image(systemName: rep.coverImageName)
                                    .font(.system(size: 60))
                                    .foregroundColor(state.theme.accent)
                            }
                        }
                    }
                    .frame(width: 190, height: 190)
                    
                    // 2. Audio Quality Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAGS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(state.theme.textSecondary.opacity(0.7))
                            .tracking(1.2)
                        
                        FlowLayout(spacing: 6) {
                            // Genre Tag
                            Text(representative?.genre ?? "Unknown")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(state.theme.cardBackground)
                                .foregroundColor(state.theme.textPrimary)
                                .cornerRadius(4)
                            
                            if hasAtmos {
                                DolbyAtmosBadge(color: .blue, scale: 0.85, showText: true)
                            }
                            
                            if hasLossless {
                                Text("Lossless")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                            
                            if let kps = kbpsTag {
                                Text(kps.uppercased())
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(state.theme.cardBackground)
                                    .foregroundColor(state.theme.textSecondary)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .frame(width: 190)
                
                // RIGHT WORKSPACE: Header titles, Play Shuffles, Track Table Rows
                VStack(alignment: .leading, spacing: 18) {
                    
                    // Header group
                    VStack(alignment: .leading, spacing: 4) {
                        Text(albumName)
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
                        
                        Text("Album • \(representative?.genre ?? "Alternative") • \(totalDurationText)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(state.theme.textSecondary)
                    }
                    
                    // Action Pills
                    HStack(spacing: 12) {
                        Button(action: {
                            if !albumTracks.isEmpty {
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
                        
                        ForEach(Array(albumTracks.enumerated()), id: \.offset) { index, track in
                            let isPlaying = engine.currentTrack?.id == track.id
                            
                            HStack(spacing: 14) {
                                // Index
                                Text("\(index + 1)")
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
                                Button(action: {
                                    // Set track selection to trigger standard non-fullscreen menu options
                                    state.selectedTrackId = track.id
                                }) {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(state.theme.textSecondary)
                                }
                                .buttonStyle(PremiumButtonStyle())
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(isPlaying ? state.theme.accent.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
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
