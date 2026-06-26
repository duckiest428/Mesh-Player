//
//  PlayerControlsView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @Binding var showFullscreen: Bool
    @Binding var showSettings: Bool
    @Environment(\.openWindow) private var openWindow
    
    @State private var isHoveringArt = false
    @State private var isHoveringArtist = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var trackToAdd: LocalTrack?
    
    var body: some View {
        HStack(spacing: 18) {
            // 1. Current Album Art & Track Metadata (Left Aligned)
            HStack(spacing: 14) {
                Button(action: {
                    if let track = engine.currentTrack {
                        state.selectedTab = "albums"
                        state.activeFilterType = "album"
                        state.activeFilterValue = track.album
                        showFullscreen = false
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(state.theme.cardBackground)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                        
                        if let track = engine.currentTrack {
                            if let artData = track.embeddedArtData, let nsImage = NSImage(data: artData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .cornerRadius(10)
                            } else if let imageURL = track.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .cornerRadius(10)
                            } else {
                                Image(systemName: track.coverImageName)
                                    .foregroundColor(state.theme.accent)
                                    .font(.system(size: 26))
                            }
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 26))
                                .foregroundColor(state.theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isHoveringArt ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringArt)
                .onHover { isHoveringArt = $0 }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(engine.currentTrack?.title ?? "Not Playing")
                            .font(.system(size: 20, weight: .black, design: .default))
                            .foregroundColor(state.theme.textPrimary)
                            .lineLimit(1)
                            
                        if let track = engine.currentTrack {
                            Menu {
                                Button("Play") {
                                    engine.playTrack(track)
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    state.toggleFavorite(track: track)
                                }) {
                                    let isFav = track.isFavorite
                                    Label(isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: isFav ? "heart.fill" : "heart")
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
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(state.theme.textSecondary)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                        }
                    }
                    
                    Button(action: {
                        if let track = engine.currentTrack {
                            state.selectedTab = "artists"
                            state.activeFilterType = "artist"
                            state.activeFilterValue = track.artist
                            showFullscreen = false
                        }
                    }) {
                        Text(engine.currentTrack?.artist ?? "---")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isHoveringArtist ? state.theme.accent : state.theme.textSecondary.opacity(0.85))
                            .lineLimit(1)
                            .underline(isHoveringArtist)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHoveringArtist = $0 }
                }
            }
            .frame(width: 320, alignment: .leading)
            
            Spacer(minLength: 16)
            
            // 2. Timeline progress Scrubber (Center Aligned, fills available workspace)
            VStack(spacing: 4) {
                HStack {
                    Text(formatTime(engine.currentTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(state.theme.textSecondary)
                    
                    Spacer()
                    
                    if engine.isAtmosTrack {
                        DolbyAtmosBadge(color: state.theme.textPrimary.opacity(0.85), scale: 1.0, showText: true)
                    } else if let track = engine.currentTrack {
                        Text(track.format)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(state.theme.textPrimary.opacity(0.06))
                            .cornerRadius(3)
                            .foregroundColor(state.theme.textSecondary.opacity(0.85))
                    }
                    
                    Spacer()
                    
                    Text("-" + formatTime(max(0, engine.duration - engine.currentTime)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(state.theme.textSecondary)
                }
                
                Slider(value: Binding(
                    get: { engine.currentTime },
                    set: { engine.seek(to: $0) }
                ), in: 0...max(0.1, engine.duration))
                .accentColor(state.theme.accent)
                .controlSize(.regular)
                .scaleEffect(y: 1.15)
                .frame(height: 14)
            }
            
            Spacer(minLength: 24)
            
            // 3. Mechanical Prev / Play / Next Buttons (150% bigger, aligned to the right of the timeline)
            HStack(spacing: 18) {
                Button(action: {
                    engine.triggerHaptic(pattern: .alignment)
                    state.playPrevious(engine: engine)
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundColor(state.theme.textPrimary)
                }
                .buttonStyle(PremiumButtonStyle())
                
                Button(action: {
                    engine.triggerHaptic(pattern: .generic)
                    engine.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(state.theme.accent)
                            .frame(width: 48, height: 48) // 150% of 32
                            .shadow(color: Color.black.opacity(0.15), radius: 4)
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold)) // 150% of 11
                            .foregroundColor(.white)
                            .offset(x: engine.isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(PremiumButtonStyle())
                
                Button(action: {
                    engine.triggerHaptic(pattern: .alignment)
                    state.playNext(engine: engine)
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(state.theme.textPrimary)
                }
                .buttonStyle(PremiumButtonStyle())
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // 4. Sound System Volume Slider & Action Panel triggers (Far Right)
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(state.theme.textSecondary)
                    Slider(value: $engine.volume, in: 0...1)
                        .accentColor(state.theme.accent)
                        .frame(width: 80)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(state.theme.textSecondary)
                }
                .controlSize(.small)
                
                Divider()
                    .frame(height: 16)
                    .background(state.theme.textSecondary.opacity(0.3))
                
                Button(action: {
                    state.toggleShuffle(currentTrack: engine.currentTrack)
                }) {
                    Image(systemName: "shuffle")
                        .font(.body)
                        .foregroundColor(state.isQueueShuffled ? state.theme.accent : state.theme.textSecondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Shuffle")
                
                let hasLyrics = !(engine.currentTrack?.lyrics.isEmpty ?? true)
                Button(action: {
                    if hasLyrics {
                        state.activeRightSidebar = state.activeRightSidebar == .lyrics ? .none : .lyrics
                    }
                }) {
                    Image(systemName: "quote.bubble")
                        .font(.body)
                        .foregroundColor(!hasLyrics ? state.theme.textSecondary.opacity(0.3) : (state.activeRightSidebar == .lyrics ? state.theme.accent : state.theme.textSecondary))
                }
                .buttonStyle(PremiumButtonStyle())
                .disabled(!hasLyrics)
                .help(hasLyrics ? "Synced Lyrics" : "No Lyrics Available")
                
                Button(action: {
                    state.activeRightSidebar = state.activeRightSidebar == .queue ? .none : .queue
                }) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.body)
                        .foregroundColor(state.activeRightSidebar == .queue ? state.theme.accent : state.theme.textSecondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Playing Next")
                
                Button(action: {
                    state.activeRightSidebar = state.activeRightSidebar == .output ? .none : .output
                }) {
                    Image(systemName: "airplayaudio")
                        .font(.body)
                        .foregroundColor(state.activeRightSidebar == .output ? state.theme.accent : state.theme.textSecondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Audio Output Device")
                
                if #available(macOS 13.0, *) {
                    Button(action: {
                        openWindow(id: "miniPlayer")
                    }) {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.body)
                            .foregroundColor(state.theme.textSecondary)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .help("Open Mini Player")
                }

                Button(action: {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    showFullscreen.toggle()
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body)
                        .foregroundColor(state.theme.textSecondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Vision Mode Fullscreen")
                
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundColor(state.theme.textSecondary)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("Preferences")
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .background(state.theme.sidebarBackground.opacity(0.95))
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
    
    private func formatTime(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
