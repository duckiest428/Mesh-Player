//
//  MainApp.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import MusicKit
import AppKit
internal import UniformTypeIdentifiers

struct macOSMusicPlayerContentView: View {
    @EnvironmentObject var state: AppStateManager
    @EnvironmentObject var engine: AudioEngineManager
    @State private var showFullscreen = false
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationSplitView {
                    SidebarView(state: state, engine: engine)
                        .frame(minWidth: 200)
                        .navigationTitle("Library")
                } detail: {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if state.selectedTab == "songs" || state.selectedTab?.hasPrefix("playlist-") == true {
                                SongTableView(state: state, engine: engine)
                            } else if state.selectedTab == "recently-added" {
                                AlbumGridView(state: state, isRecentlyAdded: true)
                            } else if (state.selectedTab == "albums" || state.selectedTab == "artists" || state.selectedTab == "genres") && state.activeFilterType != nil {
                                VStack(spacing: 0) {
                                    HStack {
                                        Button(action: {
                                            state.activeFilterType = nil
                                            state.activeFilterValue = nil
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "chevron.left")
                                                Text("Back to All \(state.selectedTab?.capitalized ?? "Categories")")
                                            }
                                            .fontWeight(.bold)
                                            .foregroundColor(state.theme.accent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(state.theme.cardBackground)
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Spacer()
                                        
                                        Text("\(state.selectedTab?.dropLast().capitalized ?? "Selection"): \(state.activeFilterValue ?? "")")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(state.theme.textPrimary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                                    .padding(.bottom, 6)
                                    .background(state.theme.background)
                                    
                                    Divider()
                                        .background(state.theme.textSecondary.opacity(0.1))
                                    
                                    if state.selectedTab == "albums", let albumName = state.activeFilterValue {
                                        AlbumDetailView(state: state, engine: engine, albumName: albumName)
                                    } else if state.selectedTab == "artists" {
                                        ArtistDetailView(state: state, engine: engine)
                                    } else {
                                        SongTableView(state: state, engine: engine)
                                    }
                                }
                            } else if state.selectedTab == "meshReplay" {
                                MeshReplayView(state: state, stats: ReplayStats(year: Calendar.current.component(.year, from: Date()), totalListeningTimeSeconds: state.tracks.map { $0.duration * Double($0.playCount) }.reduce(0.0, +), topTracks: state.tracks.sorted { $0.playCount > $1.playCount }.prefix(10).map { TrackPlayHistory(trackId: $0.id, title: $0.title, artist: $0.artist, playCount: $0.playCount, totalListenDuration: $0.duration * Double($0.playCount)) }, topArtists: Array(Dictionary(grouping: state.tracks, by: { $0.artist }).mapValues { $0.map { $0.playCount }.reduce(0, +) }.map { ArtistMilestone(name: $0.key, playCount: $0.value, badge: nil) }.sorted { $0.playCount > $1.playCount }.prefix(10)), topAlbums: [:], topGenres: [:], monthlyTrends: []))
                            } else if state.selectedTab == "home" || state.selectedTab == nil {
                                HomeView(state: state, engine: engine)
                            } else if state.selectedTab == "albums" {
                                AlbumGridView(state: state)
                            } else if state.selectedTab == "artists" {
                                ArtistGridView(state: state)
                            } else if state.selectedTab == "genres" {
                                GenreGridView(state: state)
                            } else {
                                // Visual categories grid fallbacks (Albums / Artists / Genres)
                                VStack(spacing: 16) {
                                    Image(systemName: "music.note.house")
                                        .font(.system(size: 80))
                                        .foregroundColor(state.theme.textSecondary.opacity(0.5))
                                    
                                    Text("\(state.selectedTab?.capitalized ?? "") Collection")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(state.theme.textPrimary)
                                    
                                    Text("Double-click tracks under the 'Songs' library menu to start Dolby Atmos surround simulation!")
                                        .font(.caption)
                                        .foregroundColor(state.theme.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(state.theme.background)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if state.activeRightSidebar != .none {
                            Divider()
                                .background(state.theme.textSecondary.opacity(0.12))
                            
                            switch state.activeRightSidebar {
                            case .lyrics:
                                LyricsSidebarView(state: state, engine: engine, timeTracker: engine.timeTracker)
                                    .transition(.move(edge: .trailing))
                            case .queue:
                                QueueSidebarView(state: state, engine: engine, timeTracker: engine.timeTracker)
                                    .transition(.move(edge: .trailing))
                            case .output:
                                OutputDeviceSidebarView(state: state, engine: engine, timeTracker: engine.timeTracker)
                                    .transition(.move(edge: .trailing))
                            case .none:
                                EmptyView()
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: state.activeRightSidebar)
                }
                .scrollContentBackground(.hidden)
                .background(state.theme.background)
                
                Divider()
                    .background(state.theme.textSecondary.opacity(0.15))
                
                // Global bottom controls bar spanning full width across both columns!
                PlayerControlsView(state: state, engine: engine, timeTracker: engine.timeTracker, showFullscreen: $showFullscreen, showSettings: $showSettings)
            }
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                LibraryManager.shared.startMonitoringAutoAddFolder { fileURL in
                    Task {
                        do {
                            let track = engine.parseTrackMetadata(from: fileURL)
                            if let organizedURL = try await LibraryManager.shared.organizeAndCopyFile(at: fileURL, trackMetadata: track) {
                                var updatedTrack = track
                                updatedTrack.fileURL = organizedURL
                                await MainActor.run {
                                    state.upsertTrack(updatedTrack)
                                    LibraryManager.shared.deleteFromAutoAdd(url: fileURL)
                                }
                            }
                        } catch {
                            print("Failed to auto-import file: \(error)")
                        }
                    }
                }
            }

            if showFullscreen {
                FullLyricsView(state: state, engine: engine, timeTracker: engine.timeTracker, isPresented: $showFullscreen)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

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
        .sheet(isPresented: $showSettings) {
            PreferencesView(state: state, isPresented: $showSettings)
        }
        .sheet(isPresented: $state.showSyncWindow) {
            LocalSyncView()
                .environmentObject(state)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var state: AppStateManager
    @Binding var isPresented: Bool
    @State private var directPath = "~/Music/Music/Media.localized/Music"
    @AppStorage("dev_bypass_replay_timegate") var bypassReplayTimegate: Bool = false
    
    let themes = ["Mesh Default (Apple Music)", "Space Gray", "Midnight Indigo", "Sakura Blossom", "Sunset Glow", "Cyber Neon", "True Black", "Midnight Blue", "Y2K / Skeuomorphic (Frutiger Aero)", "Cyberpunk", "Vaporwave", "Warm Coffee"]
    let eqModes = ["Flat (Default Lossless)", "Bass Booster (Sub-harmonic)", "Acoustic Live Concert Hall", "Classical (Symphonic Arc)", "Vocal Booster (Custom Lyrics Focus)", "Electronic Spectrum"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("System Preferences")
                    .font(.headline)
                    .bold()
                    .foregroundColor(state.theme.textPrimary)
                Spacer()
                Button("Apply Setup") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(state.theme.sidebarBackground)
            
            Divider()
            
            ScrollView {
                    HStack(alignment: .top, spacing: 24) {
                        // Column 1: Themes, Equalizer, Crossfade duration
                        VStack(alignment: .leading, spacing: 20) {
                            Text("AUDIO & THEME SETUP")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.theme.textSecondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Aesthetic Display Theme")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(state.theme.textPrimary)
                                Picker("", selection: $state.currentThemeName) {
                                    ForEach(themes, id: \.self) { t in
                                        Text(t).tag(t)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Acoustic Equalizer Mode")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(state.theme.textPrimary)
                                Picker("", selection: $state.eqMode) {
                                    ForEach(eqModes, id: \.self) { m in
                                        Text(m).tag(m)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Crossfade Gap")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(state.theme.textPrimary)
                                    Spacer()
                                    Text("\(Int(state.crossfadeGap)) seconds")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(state.theme.textSecondary)
                                }
                                Slider(value: $state.crossfadeGap, in: 0...12, step: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                        
                        // Column 2: Trajectory path, Spatial core checkboxes
                        VStack(alignment: .leading, spacing: 20) {
                            Text("SPATIAL CORE & PATHS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.theme.textSecondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Direct Trajectory Path")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(state.theme.textPrimary)
                                    Spacer()
                                    Text("SYNCED")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.green)
                                }
                                TextField("", text: $directPath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)
                                    .font(.system(.body, design: .monospaced))
                                Text("Points specifically to Apple Music's library directory containing lyrics assets and lossless source tracks.")
                                    .font(.system(size: 10))
                                    .foregroundColor(state.theme.textSecondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("LAST.FM SCROBBLING")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(state.theme.textSecondary)
                                
                                Toggle("Enable Last.fm Scrobbling", isOn: $state.enableLastFm)
                                    .toggleStyle(.checkbox)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                if state.enableLastFm {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Username")
                                            .font(.system(size: 11))
                                            .foregroundColor(state.theme.textPrimary)
                                        TextField("Last.fm Username", text: $state.lastFmUsername)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                        
                                        Text("Session Key")
                                            .font(.system(size: 11))
                                            .foregroundColor(state.theme.textPrimary)
                                        SecureField("Last.fm Session Key", text: $state.lastFmSessionKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Spatial Core Engine")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                Toggle("Render Spatial Audio Object Layouts", isOn: $state.enableAtmos)
                                    .toggleStyle(.checkbox)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                Toggle("Auto-scroll lyrics on time updates", isOn: $state.autoScrollLyrics)
                                    .toggleStyle(.checkbox)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                Toggle("Show album artwork in Dock", isOn: $state.showDockArtwork)
                                    .toggleStyle(.checkbox)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                Toggle("Remove playlist songs from library", isOn: $state.removePlaylistSongsFromLibrary)
                                    .toggleStyle(.checkbox)
                                    .foregroundColor(state.theme.textPrimary)
                                    .help("When deleting a playlist or removing a song, also delete it from the global library.")
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Visible Songs Details Columns")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    Toggle("Duration (Time)", isOn: $state.showTimeColumn)
                                    Toggle("Artist", isOn: $state.showArtistColumn)
                                    Toggle("Album", isOn: $state.showAlbumColumn)
                                    Toggle("Genre", isOn: $state.showGenreColumn)
                                    Toggle("Favorites", isOn: $state.showFavoritesColumn)
                                    Toggle("Plays Count", isOn: $state.showPlaysColumn)
                                    Toggle("Date Added", isOn: $state.showDateAddedColumn)
                                    Toggle("Year", isOn: $state.showYearColumn)
                                    Toggle("Audio Format", isOn: $state.showFormatColumn)
                                }
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                                .foregroundColor(state.theme.textPrimary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DEVELOPER SETTINGS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(state.theme.textSecondary)
                                
                                Toggle("Disable Replay Time-Gating", isOn: $bypassReplayTimegate)
                                    .toggleStyle(.checkbox)
                                    .foregroundColor(state.theme.textPrimary)
                                
                                Text("Bypasses calendar restrictions on Yearly, Monthly, and Weekly Replays for testing.")
                                    .font(.system(size: 10))
                                    .foregroundColor(state.theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(24)
                
                Spacer()
            }
            .frame(width: 760, height: 600)
            .background(state.theme.background)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var engine: AudioEngineManager?
    var state: AppStateManager?
    var dockIdleTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem(for: nil)
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open App", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Favourite", action: #selector(toggleFavourite), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Previous", action: #selector(playPrevious), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Next", action: #selector(playNext), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleFavourite() {
        if let currentId = engine?.currentTrack?.id, let state = state {
            if let index = state.tracks.firstIndex(where: { $0.id == currentId }) {
                state.tracks[index].isFavorite.toggle()
                if let currentTrack = engine?.currentTrack {
                    var updated = currentTrack
                    updated.isFavorite = state.tracks[index].isFavorite
                    engine?.currentTrack = updated
                }
            }
        }
    }
    
    @objc func playPrevious() {
        if let engine = engine, let state = state {
            state.playPrevious(engine: engine)
        }
    }
    
    @objc func playNext() {
        if let engine = engine, let state = state {
            state.playNext(engine: engine)
        }
    }
    
    @objc func togglePlayPause() {
        engine?.togglePlayPause()
    }
    
    func updateStatusItem(for track: LocalTrack?) {
        if let button = statusItem?.button {
            if let track = track {
                let maxLen = 40
                let titleStr = track.title.count > maxLen ? String(track.title.prefix(maxLen)) + "..." : track.title
                button.title = " \(titleStr)"
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Mesh Player")
            } else {
                button.title = ""
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Mesh Player")
            }
        }
    }
    
    func updateDockTile(for track: LocalTrack?, isPlaying: Bool) {
        let dockTile = NSApplication.shared.dockTile
        
        let shouldShowArtwork = state?.showDockArtwork ?? false
        
        if shouldShowArtwork, let track = track, isPlaying {
            dockIdleTimer?.invalidate()
            dockIdleTimer = nil
            
            let imageView = NSImageView()
            if let artData = track.embeddedArtData, let img = NSImage(data: artData) {
                imageView.image = img
            } else if let localCover = track.localCoverURL, let img = NSImage(contentsOf: localCover) {
                imageView.image = img
            } else {
                imageView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            }
            dockTile.contentView = imageView
            dockTile.display()
        } else {
            if dockIdleTimer == nil && dockTile.contentView != nil {
                dockIdleTimer = Timer.scheduledTimer(withTimeInterval: shouldShowArtwork ? 10.0 : 0.0, repeats: false) { _ in
                    dockTile.contentView = nil
                    dockTile.display()
                }
            }
        }
    }
}

@main
struct macOSMusicPlayerApp: App {
    @StateObject private var state = AppStateManager()
    @StateObject private var engine = AudioEngineManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            macOSMusicPlayerContentView()
                .frame(minWidth: 960, minHeight: 620)
                .environmentObject(state)
                .environmentObject(engine)
                .onAppear {
                    appDelegate.engine = engine
                    appDelegate.state = state
                    
                    engine.onPlayNext = {
                        appDelegate.playNext()
                    }
                    
                    engine.onTrackFinished = { track in
                        // PlayNext is usually handled by AudioEngineManager internally,
                        // but if we need external logic we put it here
                    }
                    
                    engine.onPlayCountUpdate = { trackId in
                        if let idx = state.tracks.firstIndex(where: { $0.id == trackId }) {
                            state.tracks[idx].playCount += 1
                            state.tracks[idx].lastPlayedDate = Date()
                            state.logPlayEvent(for: state.tracks[idx])
                        }
                    }
                    engine.onTrackMetadataUpdated = { updatedTrack in
                        if let idx = state.tracks.firstIndex(where: { $0.id == updatedTrack.id }) {
                            state.tracks[idx] = updatedTrack
                            state.saveContext()
                        }
                    }
                    
                    engine.onPlayPrevious = {
                        appDelegate.playPrevious()
                    }
                }
                .onChange(of: engine.currentTrack) { track in
                    appDelegate.updateStatusItem(for: track)
                    appDelegate.updateDockTile(for: track, isPlaying: engine.isPlaying)
                }
                .onChange(of: engine.isPlaying) { isPlaying in
                    appDelegate.updateDockTile(for: engine.currentTrack, isPlaying: isPlaying)
                }
                .onChange(of: state.showDockArtwork) { _ in
                    appDelegate.updateDockTile(for: engine.currentTrack, isPlaying: engine.isPlaying)
                }
                .touchBar {
                    if let track = engine.currentTrack {
                        Text(track.title) // Restoring original title
                            .font(.system(size: 14))
                    }
                    
                    Button(action: {
                        if let current = engine.currentTrack, let idx = state.tracks.firstIndex(where: { $0.id == current.id }) {
                            let prevIdx = (idx - 1 + state.tracks.count) % state.tracks.count
                            engine.playTrack(state.tracks[prevIdx])
                        }
                    }) {
                        Image(systemName: "backward.fill")
                    }
                    
                    Button(action: { engine.togglePlayPause() }) {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    }
                    
                    Button(action: {
                        if let current = engine.currentTrack, let idx = state.tracks.firstIndex(where: { $0.id == current.id }) {
                            let nextIdx = (idx + 1) % state.tracks.count
                            engine.playTrack(state.tracks[nextIdx])
                        }
                    }) {
                        Image(systemName: "forward.fill")
                    }
                    
                    Slider(value: Binding(
                        get: { engine.currentTime },
                        set: { engine.seek(to: $0) }
                    ), in: 0...max(0.1, engine.duration))
                    .frame(width: 250)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Playlist") { }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Playlist from Selection") { }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Smart Playlist") { }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Playlist Folder") { }
                Divider()
                Button("Local Device Sync...") {
                    state.showSyncWindow = true
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Open Stream URL...") { }
                    .keyboardShortcut("u", modifiers: .command)
                Divider()
                Button("Close") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Button("Add To Library...") { }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Burn Playlist to Disc...") { }
                    .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Show in Finder") { }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            CommandMenu("Song") {
                Button("Get Info...") { }
                    .keyboardShortcut("i", modifiers: .command)
            }
            
            CommandGroup(replacing: .toolbar) {
                Button("Show View Options") { }
                    .keyboardShortcut("j", modifiers: .command)
                Button("Find in Recently Added") { }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Show Playing Next") { }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                Button("Show Lyrics") {
                    if appDelegate.state?.activeRightSidebar == .lyrics {
                        appDelegate.state?.activeRightSidebar = .none
                    } else {
                        appDelegate.state?.activeRightSidebar = .lyrics
                    }
                }
                .keyboardShortcut("u", modifiers: [.command, .control])
                Divider()
                Button("Show Status Bar") { }
                    .keyboardShortcut("/", modifiers: .command)
                Divider()
                Button("Enter Full Screen") {
                    NSApplication.shared.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: .function)
            }
            
            CommandMenu("Controls") {
                Button("Play / Pause") {
                    appDelegate.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { appDelegate.engine?.pause() }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Next Track") { appDelegate.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Track") { appDelegate.playPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Genius Shuffle") { }
                    .keyboardShortcut(.space, modifiers: .option)
                Divider()
                Button("Go to Current Song") { }
                    .keyboardShortcut("l", modifiers: .command)
                Divider()
                Button("Set Volume to Maximum") { appDelegate.engine?.volume = 1.0 }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Set Volume to Minimum") { appDelegate.engine?.volume = 0.0 }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                Divider()
                Button("Back") { }
                    .keyboardShortcut("[", modifiers: .command)
            }
            
            CommandGroup(replacing: .windowList) {
                Button("Minimize") {
                    NSApplication.shared.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)
                Button("Fill") { }
                    .keyboardShortcut("f", modifiers: [.control, .function])
                Button("Centre") { }
                    .keyboardShortcut("c", modifiers: [.control, .function])
                Divider()
                Button("Music") { }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Equalizer") { }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("MiniPlayer") { }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button("Activity") { }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Visualizer") { }
                    .keyboardShortcut("t", modifiers: .command)
                Divider()
                Button("Switch to MiniPlayer") { }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Now Playing") { }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
        .windowStyle(.hiddenTitleBar)
        
        Window("Mini Player", id: "miniPlayer") {
            MiniPlayerView()
                .environmentObject(state)
                .environmentObject(engine)
                .onAppear {
                    if let window = NSApplication.shared.windows.first(where: { $0.title == "Mini Player" }) {
                        window.level = .floating
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 120)
        .windowResizability(.contentSize)
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject var state: AppStateManager
    @EnvironmentObject var engine: AudioEngineManager
    
    var body: some View {
        HStack(spacing: 12) {
            if let track = engine.currentTrack {
                AsyncThumbnailView(track: track, size: 64, theme: state.theme)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundColor(state.theme.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundColor(state.theme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: { engine.togglePlayPause() }) {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(state.theme.textPrimary)
                }
                .buttonStyle(.plain)
            } else {
                Text("Not Playing")
                    .foregroundColor(state.theme.textSecondary)
            }
        }
        .padding()
        .frame(width: 320, height: 90)
        .background(AnyView(Rectangle().fill(Material.ultraThin).opacity(0.85)))
    }
}

// MARK: - Sub library Grid Components

struct AlbumGridView: View {
    @ObservedObject var state: AppStateManager
    var isRecentlyAdded: Bool = false
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)
    ]
    
    // Grouping helper
    func groupAlbums(_ albums: [LocalAlbum]) -> [(String, [LocalAlbum])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let startOfMonth = calendar.date(byAdding: .month, value: -1, to: startOfToday)!
        
        var today: [LocalAlbum] = []
        var thisWeek: [LocalAlbum] = []
        var thisMonth: [LocalAlbum] = []
        var older: [LocalAlbum] = []
        
        for album in albums {
            let date = album.trackRepresentative.dateAdded
            if date >= startOfToday {
                today.append(album)
            } else if date >= startOfWeek {
                thisWeek.append(album)
            } else if date >= startOfMonth {
                thisMonth.append(album)
            } else {
                older.append(album)
            }
        }
        
        var result: [(String, [LocalAlbum])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !thisMonth.isEmpty { result.append(("This Month", thisMonth)) }
        if !older.isEmpty { result.append(("Older", older)) }
        
        return result
    }
    
    private var sortedAlbums: [LocalAlbum] {
        var baseList = isRecentlyAdded ? state.recentlyAddedAlbumsList : state.albumsList
        if state.activeFilterType == "artist", let val = state.activeFilterValue {
            baseList = baseList.filter { $0.artist == val }
        }
        switch state.albumSortCriteria {
        case .dateAdded:
            return baseList.sorted { $0.trackRepresentative.dateAdded > $1.trackRepresentative.dateAdded }
        case .yearReleased:
            return baseList.sorted { ($0.trackRepresentative.year ?? 0) > ($1.trackRepresentative.year ?? 0) }
        case .title:
            return baseList.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .artist:
            return baseList.sorted { $0.artist.lowercased() < $1.artist.lowercased() }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: isRecentlyAdded ? "clock.arrow.circlepath" : "square.stack")
                        .font(.title3)
                        .foregroundColor(state.theme.accent)
                    Text(isRecentlyAdded ? "Recently Added" : "Albums")
                        .font(.title2)
                        .bold()
                        .foregroundColor(state.theme.textPrimary)
                    
                    Spacer()
                    
                    Menu {
                        Picker("Sort By", selection: $state.albumSortCriteria) {
                            ForEach(AppStateManager.AlbumSortCriteria.allCases, id: \.self) { criteria in
                                Text(criteria.rawValue).tag(criteria)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(state.albumSortCriteria.rawValue)
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 140)
                }
                .padding(.top)
                
                if isRecentlyAdded {
                    let grouped = groupAlbums(sortedAlbums)
                    ForEach(grouped, id: \.0) { groupName, albums in
                        Section(header: Text(groupName)
                            .font(.title3)
                            .bold()
                            .foregroundColor(state.theme.textPrimary)
                            .padding(.top, 8)
                            .padding(.bottom, 4)) {
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(albums) { album in
                                        AlbumCell(album: album, state: state)
                                    }
                                }
                            }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(sortedAlbums) { album in
                            AlbumCell(album: album, state: state)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(state.theme.background)
    }
}

struct AlbumCell: View {
    let album: LocalAlbum
    @ObservedObject var state: AppStateManager
    var subtitle: String? = nil
    var pillTag: String? = nil
    
    var body: some View {
        Button(action: {
            state.selectedTab = "albums" // To render AlbumDetailView properly
            state.activeFilterType = "album"
            state.activeFilterValue = album.name
        }) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(state.theme.cardBackground)
                        .aspectRatio(1.0, contentMode: .fit)
                    
                    AsyncFlexibleThumbnailView(track: album.trackRepresentative, maxPixelSize: 300, theme: state.theme, cornerRadius: 10)
                }
                .aspectRatio(1.0, contentMode: .fit)
                .shadow(radius: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(state.theme.textPrimary)
                        .lineLimit(1)
                    
                    if let tag = pillTag {
                        HStack {
                            Text(tag)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(state.theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                            Spacer(minLength: 0)
                        }
                    } else {
                        Text(subtitle ?? "\(album.artist) • \(album.tracksCount) tracks")
                            .font(.caption)
                            .foregroundColor(state.theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ArtistGridView: View {
    @ObservedObject var state: AppStateManager
    
    let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "music.mic")
                        .font(.title3)
                        .foregroundColor(state.theme.accent)
                    Text("Artists")
                        .font(.title2)
                        .bold()
                        .foregroundColor(state.theme.textPrimary)
                }
                .padding(.top)
                
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(state.artistsList) { artist in
                        Button(action: {
                            state.activeFilterType = "artist"
                            state.activeFilterValue = artist.name
                        }) {
                            VStack(alignment: .center, spacing: 10) {
                                ZStack {
                                    CachedArtistProfileView(artistName: artist.name, themeAccent: state.theme.accent)
                                }
                                .shadow(radius: 4)
                                
                                VStack(alignment: .center, spacing: 2) {
                                    Text(artist.name)
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(state.theme.textPrimary)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.center)
                                    
                                    Text("\(artist.tracksCount) tracks on Mac")
                                        .font(.caption)
                                        .foregroundColor(state.theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(state.theme.background)
    }
}

struct GenreGridView: View {
    @ObservedObject var state: AppStateManager
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "guitars")
                        .font(.title3)
                        .foregroundColor(state.theme.accent)
                    Text("Genres")
                        .font(.title2)
                        .bold()
                        .foregroundColor(state.theme.textPrimary)
                }
                .padding(.top)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(state.genresList) { genre in
                        Button(action: {
                            state.activeFilterType = "genre"
                            state.activeFilterValue = genre.name
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(state.theme.cardBackground)
                                        .frame(width: 48, height: 48)
                                    
                                    AsyncFlexibleThumbnailView(track: genre.trackRepresentative, maxPixelSize: 96, theme: state.theme, cornerRadius: 8)
                                        .frame(width: 48, height: 48)
                                }
                                .shadow(radius: 2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(genre.name)
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(state.theme.textPrimary)
                                        .lineLimit(1)
                                    
                                    Text("\(genre.tracksCount) tracks")
                                        .font(.caption)
                                        .foregroundColor(state.theme.textSecondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(state.theme.cardBackground)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(state.theme.background)
    }
}

// MARK: - MusicKit Artist Artwork Lookup
struct CachedArtistProfileView: View {
    let artistName: String
    let themeAccent: Color
    var size: CGFloat = 100
    
    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let nsImage = loadedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .contentShape(Circle())
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .task(id: artistName) {
            await fetchArtistArtwork()
        }
    }
    
    private var fallbackView: some View {
        let initial = artistName.first.map { String($0).uppercased() } ?? "A"
        let colors = generateGradient(for: artistName)
        
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .overlay(
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func generateGradient(for name: String) -> [Color] {
        let hash = abs(name.hashValue)
        let colorOptions: [[Color]] = [
            [themeAccent, .purple],
            [.indigo, themeAccent],
            [.pink, .purple],
            [.blue, .teal],
            [.orange, .red],
            [.purple, .blue]
        ]
        return colorOptions[hash % colorOptions.count]
    }
    
    private func fetchArtistArtwork() async {
        guard !artistName.isEmpty && artistName != "Unknown Artist" && artistName != "Local Artist" else { return }
        
        let cacheKey = NSString(string: "artist_avatar_\(artistName)_\(Int(size))")
        if let cached = ThumbnailGenerator.shared.cache.object(forKey: cacheKey) {
            self.loadedImage = cached
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let url = try await ArtistProfilePictureService.shared.fetchAndCacheProfilePicture(for: artistName) {
                let decoded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                    guard let image = NSImage(contentsOf: url) else { return nil }
                    let targetSize = NSSize(width: size, height: size)
                    let imgSize = image.size
                    guard imgSize.width > 0 && imgSize.height > 0 else { return nil }
                    
                    let aspectWidth = targetSize.width / imgSize.width
                    let aspectHeight = targetSize.height / imgSize.height
                    let maxAspect = max(aspectWidth, aspectHeight)
                    
                    let fillSize = NSSize(width: imgSize.width * maxAspect, height: imgSize.height * maxAspect)
                    let cropRect = NSRect(
                        x: (targetSize.width - fillSize.width) / 2.0,
                        y: (targetSize.height - fillSize.height) / 2.0,
                        width: fillSize.width,
                        height: fillSize.height
                    )
                    
                    let resized = NSImage(size: targetSize)
                    resized.lockFocus()
                    image.draw(in: cropRect, from: NSRect(origin: .zero, size: imgSize), operation: .copy, fraction: 1.0)
                    resized.unlockFocus()
                    return resized
                }.value
                
                if let img = decoded {
                    ThumbnailGenerator.shared.cache.setObject(img, forKey: cacheKey)
                    await MainActor.run {
                        self.loadedImage = img
                    }
                }
            }
        } catch {
            print("Failed to fetch artist profile picture: \(error)")
        }
    }
}

struct ArtistDetailView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    var artistName: String {
        state.activeFilterValue ?? "Unknown Artist"
    }
    
    var artistSongs: [LocalTrack] {
        state.tracks.filter { $0.artist == artistName }
    }
    
    var artistAlbums: [LocalAlbum] {
        state.albumsList.filter { $0.artist == artistName }.sorted {
            let y0 = $0.yearRecorded ?? $0.trackRepresentative.yearRecorded ?? $0.trackRepresentative.year ?? 0
            let y1 = $1.yearRecorded ?? $1.trackRepresentative.yearRecorded ?? $1.trackRepresentative.year ?? 0
            if y0 != y1 {
                return y0 > y1
            }
            return $0.name < $1.name
        }
    }
    
    var mostPlayedSongs: [LocalTrack] {
        artistSongs.sorted { $0.playCount > $1.playCount }.prefix(16).map { $0 }
    }
    
    var mostPlayedAlbums: [LocalAlbum] {
        artistAlbums.sorted { a, b in
            let aPlays = artistSongs.filter { $0.album == a.name }.map { $0.playCount }.reduce(0, +)
            let bPlays = artistSongs.filter { $0.album == b.name }.map { $0.playCount }.reduce(0, +)
            if aPlays != bPlays {
                return aPlays > bPlays
            }
            return a.name < b.name
        }.prefix(5).map { $0 }
    }
    
    var playlistsWithArtist: [Playlist] {
        state.playlists.filter { playlist in
            playlist.playlistTracks.contains { $0.track.artist == artistName }
        }
    }
    
    func playSongs(_ songs: [LocalTrack], shuffle: Bool = false) {
        if let first = songs.first {
            engine.playTrack(first)
            state.isQueueShuffled = shuffle
            state.setQueue(tracks: songs, startTrack: first)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header Banner
                ZStack(alignment: .bottom) {
                    // Image Banner
                    ArtistBannerView(artistName: artistName)
                        .frame(height: 300)
                        .clipped()
                        .overlay(Color.black.opacity(0.4))
                    
                    VStack {
                        Spacer()
                        Text(artistName)
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.bottom, 24)
                    }
                }
                .frame(height: 300)
                .cornerRadius(16)
                
                // Action Control Row
                HStack(spacing: 16) {
                    Spacer()
                    Button(action: { playSongs(artistSongs, shuffle: true) }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle All")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(state.theme.cardBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { playSongs(artistSongs) }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(state.theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "heart")
                            .font(.title2)
                            .padding(12)
                            .background(state.theme.cardBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                // Artist Biography & Overview
                ArtistBioView(artistName: artistName, themeAccent: state.theme.accent, textColor: state.theme.textPrimary)
                    .padding(.horizontal, 24)
                
                // Most Played Songs Shelf
                if !mostPlayedSongs.isEmpty {
                    ShelfHeader(title: "Most Played Songs", action: {
                        state.selectedTab = "songs"
                        state.activeFilterType = "artist"
                        state.activeFilterValue = artistName
                        state.sortCriteria = "playCount"
                        state.sortAscending = false
                    })
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(rows: [GridItem(.fixed(50), spacing: 0), GridItem(.fixed(50), spacing: 0), GridItem(.fixed(50), spacing: 0)], spacing: 20) {
                            ForEach(mostPlayedSongs) { track in
                                HStack {
                                    Button(action: { engine.playTrack(track) }) {
                                        HStack {
                                            AsyncFlexibleThumbnailView(track: track, maxPixelSize: 96, theme: state.theme, cornerRadius: 6)
                                                .frame(width: 44, height: 44)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.title)
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundColor(state.theme.textPrimary)
                                                    .lineLimit(1)
                                                Text("\(track.playCount) \(track.playCount == 1 ? "Play" : "Plays")")
                                                    .font(.system(size: 11, weight: .regular))
                                                    .foregroundColor(state.theme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .frame(width: 260)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Menu {
                                        Button("Play") { engine.playTrack(track) }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(state.theme.textSecondary)
                                            .frame(width: 20, height: 20)
                                            .contentShape(Rectangle())
                                    }
                                    .menuStyle(.borderlessButton)
                                    .frame(width: 20)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 50)
                                .overlay(
                                    Divider().padding(.leading, 60),
                                    alignment: .bottom
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Most Played Albums Shelf
                if !mostPlayedAlbums.isEmpty {
                    ShelfHeader(title: "Most Played Albums", action: {
                        state.selectedTab = "albums"
                        state.activeFilterType = "artist"
                        state.activeFilterValue = artistName
                        state.albumSortCriteria = .dateAdded // fallback
                    })
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 20) {
                            ForEach(mostPlayedAlbums) { album in
                                let plays = artistSongs.filter { $0.album == album.name }.map { $0.playCount }.reduce(0, +)
                                AlbumCell(album: album, state: state, subtitle: "\(plays) plays")
                                    .frame(width: 160)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Albums Shelf
                if !artistAlbums.isEmpty {
                    ShelfHeader(title: "Albums", action: {
                        state.selectedTab = "albums"
                        state.activeFilterType = "artist"
                        state.activeFilterValue = artistName
                    })
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 20) {
                            ForEach(artistAlbums) { album in
                                let year = album.yearRecorded ?? album.trackRepresentative.yearRecorded ?? album.trackRepresentative.year
                                let yearTag = year != nil ? "\(year!) • Album" : "Album"
                                AlbumCell(album: album, state: state, subtitle: yearTag, pillTag: yearTag)
                                    .frame(width: 160)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Songs Shelf
                if !artistSongs.isEmpty {
                    ShelfHeader(title: "Songs", action: {
                        state.selectedTab = "songs"
                        state.activeFilterType = "artist"
                        state.activeFilterValue = artistName
                        state.sortCriteria = "title"
                        state.sortAscending = true
                    })
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(artistSongs.prefix(12)) { track in
                            HStack {
                                Text(track.title).lineLimit(1).font(.subheadline)
                                Spacer()
                            }
                            .padding(8)
                            .background(state.theme.cardBackground.opacity(0.5))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                // Found in your playlists Shelf
                if !playlistsWithArtist.isEmpty {
                    ShelfHeader(title: "Found in your playlists", action: {
                        // Could route to playlists tab, handled by user selecting playlist in sidebar anyway
                    })
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 20) {
                            ForEach(playlistsWithArtist) { playlist in
                                VStack(alignment: .leading) {
                                    Rectangle().fill(state.theme.cardBackground).frame(width: 160, height: 160).cornerRadius(8)
                                    Text(playlist.name).font(.subheadline).bold()
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.bottom, 64)
        }
        .background(state.theme.background)
    }
}

struct ShelfHeader: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.title2)
                    .bold()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}


struct JumpBackInCard: View {
    let track: LocalTrack
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            state.setQueue(tracks: [track], startTrack: track)
            engine.playTrack(track)
        }) {
            HStack(spacing: 12) {
                AsyncFlexibleThumbnailView(track: track, maxPixelSize: 120, theme: state.theme, cornerRadius: 8)
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(state.theme.textPrimary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundColor(state.theme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundColor(state.theme.accent)
                    .opacity(isHovered ? 1.0 : 0.6)
            }
            .padding(10)
            .frame(width: 220)
            .background(state.theme.cardBackground.opacity(isHovered ? 0.8 : 0.4))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? state.theme.accent.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct HomeView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    @State private var recommendedItems: [RecommendedTrackItem] = []
    
    var totalSongs: Int {
        state.tracks.count
    }
    
    var totalArtists: Int {
        Set(state.tracks.map { $0.artist }).count
    }
    
    var totalGenres: Int {
        Set(state.tracks.map { $0.genre }).count
    }
    
    var totalPlays: Int {
        state.tracks.map { $0.playCount }.reduce(0, +)
    }
    
    var formattedListeningTime: String {
        let totalSeconds = state.tracks.map { $0.duration * Double($0.playCount) }.reduce(0.0, +)
        if totalSeconds < 3600 {
            let mins = Int(totalSeconds / 60.0)
            return "\(mins) mins"
        } else {
            let hrs = totalSeconds / 3600.0
            return String(format: "%.1f hrs", hrs)
        }
    }
    
    var recentTracks: [LocalTrack] {
        let played = state.tracks.filter { $0.playCount > 0 }
        let sortedTracks = played.sorted(by: { (track1: LocalTrack, track2: LocalTrack) -> Bool in
            let date1 = track1.lastPlayedDate ?? track1.dateAdded
            let date2 = track2.lastPlayedDate ?? track2.dateAdded
            return date1 > date2
        })
        return Array(sortedTracks.prefix(8))
    }
    
    var carouselItems: [LocalTrack] {
        if recentTracks.isEmpty {
            return Array(state.tracks.prefix(8))
        } else {
            return recentTracks
        }
    }
    
    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                Text("Home")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(state.theme.textPrimary)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                
                // 1. "Your Library Stats" Pill Bar
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Library Stats")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(state.theme.textPrimary)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            StatCardOS(title: "Songs", value: "\(totalSongs)", icon: "music.note", gradientColors: [.pink, .red], theme: state.theme)
                            StatCardOS(title: "Artists", value: "\(totalArtists)", icon: "person.fill", gradientColors: [.purple, .indigo], theme: state.theme)
                            StatCardOS(title: "Genres", value: "\(totalGenres)", icon: "guitars.fill", gradientColors: [.blue, .cyan], theme: state.theme)
                            StatCardOS(title: "Total Plays", value: "\(totalPlays)", icon: "play.circle.fill", gradientColors: [.green, .mint], theme: state.theme)
                            StatCardOS(title: "Time Listened", value: formattedListeningTime, icon: "clock.fill", gradientColors: [.orange, .yellow], theme: state.theme)
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // 2. "Jump Back In" Horizontal Carousel
                if !carouselItems.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(state.theme.accent)
                            Text("Jump Back In")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(state.theme.textPrimary)
                        }
                        .padding(.horizontal, 24)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(carouselItems) { track in
                                    JumpBackInCard(track: track, state: state, engine: engine)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // 3. Enhanced "Made For You" Recommendation Grid
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Made For You")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(state.theme.textPrimary)
                            Text("Tailored from your recent plays & library habits")
                                .font(.subheadline)
                                .foregroundColor(state.theme.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            generateRecommendations()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(state.theme.textSecondary)
                                .padding(8)
                                .background(state.theme.cardBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(recommendedItems) { item in
                            MadeForYouCard(track: item.track, badgeTag: item.badgeTag, state: state, engine: engine)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 60)
        }
        .background(state.theme.background)
        .onAppear {
            if recommendedItems.isEmpty && !state.tracks.isEmpty {
                generateRecommendations()
            }
        }
        .onChange(of: state.tracks.count) { _ in
            if recommendedItems.isEmpty && !state.tracks.isEmpty {
                generateRecommendations()
            }
        }
    }
    
    private func generateRecommendations() {
        let now = Date()
        let fourteenDaysSec: TimeInterval = 14 * 86400
        let thirtyDaysSec: TimeInterval = 30 * 86400
        
        let genrePlayCounts = Dictionary(grouping: state.tracks, by: { $0.genre })
            .mapValues { $0.map { $0.playCount }.reduce(0, +) }
        let topGenres = Set(genrePlayCounts.sorted(by: { $0.value > $1.value }).prefix(3).map { $0.key })
        
        let shuffled = state.tracks.shuffled()
        var results: [RecommendedTrackItem] = []
        
        for track in shuffled {
            let secondsSinceAdded = now.timeIntervalSince(track.dateAdded)
            var tag: String? = nil
            
            // Strict Filter Rules:
            // 1. Recently Added: addedDate <= 14 days ago. Never tag if imported older than 14 days.
            if secondsSinceAdded <= fourteenDaysSec {
                tag = "Recently Added"
            // 2. Heavy Rotation: playCount >= 5
            } else if track.playCount >= 5 {
                tag = "Heavy Rotation"
            // 3. Discovery: added <= 30 days ago and playCount >= 2
            } else if secondsSinceAdded <= thirtyDaysSec && track.playCount >= 2 {
                tag = "Discovery"
            // 4. Genre Highlight: track matches user's top 3 most-listened genres
            } else if !track.genre.isEmpty && topGenres.contains(track.genre) && track.playCount > 0 {
                tag = "Genre Highlight"
            // 5. Top Pick: track play count >= 8 or is favorite
            } else if track.playCount >= 8 || track.isFavorite {
                tag = "Top Pick"
            } else {
                // Strict Fallback: Do NOT show a fake tag badge on its card!
                tag = nil
            }
            
            results.append(RecommendedTrackItem(track: track, badgeTag: tag))
            if results.count >= 12 { break }
        }
        
        recommendedItems = results
    }
}

struct RecommendedTrackItem: Identifiable {
    var id: UUID { track.id }
    let track: LocalTrack
    let badgeTag: String?
}

struct MadeForYouCard: View {
    let track: LocalTrack
    let badgeTag: String?
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            state.setQueue(tracks: [track], startTrack: track)
            engine.playTrack(track)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .center) {
                    AsyncFlexibleThumbnailView(track: track, maxPixelSize: 320, theme: state.theme, cornerRadius: 10)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .brightness(isHovered ? 0.08 : 0.0)
                    
                    if isHovered {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(state.theme.textPrimary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(state.theme.textSecondary)
                        .lineLimit(1)
                    
                    if let badgeTag = badgeTag {
                        Text(badgeTag)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(state.theme.accent.opacity(0.15))
                            .foregroundColor(state.theme.accent)
                            .cornerRadius(4)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(12)
            .background(state.theme.cardBackground.opacity(isHovered ? 0.8 : 0.4))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovered ? state.theme.accent.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct StatCardOS: View {
    let title: String
    let value: String
    let icon: String
    let gradientColors: [Color]
    let theme: ThemeColor
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: gradientColors.first?.opacity(0.4) ?? .clear, radius: 6, x: 0, y: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

