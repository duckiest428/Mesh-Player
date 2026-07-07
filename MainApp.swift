//
//  MainApp.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import MusicKit

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
            
            if showFullscreen {
                FullLyricsView(state: state, engine: engine, timeTracker: engine.timeTracker, isPresented: $showFullscreen)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $showSettings) {
            PreferencesView(state: state, isPresented: $showSettings)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var state: AppStateManager
    @Binding var isPresented: Bool
    @State private var directPath = "~/Music/Music/Media.localized/Music"
    
    let themes = ["Space Gray", "Midnight Indigo", "Sakura Blossom", "Sunset Glow", "Cyber Neon", "True Black", "Midnight Blue", "Y2K / Skeuomorphic (Frutiger Aero)", "Cyberpunk", "Vaporwave", "Warm Coffee"]
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
                            Toggle("Audio Format", isOn: $state.showFormatColumn)
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .foregroundColor(state.theme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            
            Spacer()
        }
        .frame(width: 720, height: 500)
        .background(state.theme.background)
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
                button.title = " \(track.title)"
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
                        if let idx = state.tracks.firstIndex(where: { $0.id == track.id }) {
                            state.tracks[idx].playCount += 1
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
        let baseList = isRecentlyAdded ? state.recentlyAddedAlbumsList : state.albumsList
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(state.theme.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(album.artist) • \(album.tracksCount) tracks")
                        .font(.caption)
                        .foregroundColor(state.theme.textSecondary)
                        .lineLimit(1)
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
                                    Circle()
                                        .fill(state.theme.cardBackground)
                                        .frame(width: 100, height: 100)
                                    
                                    AsyncFlexibleThumbnailView(track: artist.trackRepresentative, maxPixelSize: 200, theme: state.theme, cornerRadius: 50)
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
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
struct MusicKitArtistImageView: View {
    let artistName: String
    let themeAccent: Color
    
    @State private var artworkURL: URL? = nil
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 100, height: 100)
            } else if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    case .failure, .empty:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .task {
            await fetchArtistArtwork()
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(themeAccent.opacity(0.15))
                .frame(width: 100, height: 100)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(themeAccent)
        }
    }
    
    private func fetchArtistArtwork() async {
        guard !artistName.isEmpty && artistName != "Unknown Artist" && artistName != "Local Artist" else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Initiate MusicCatalogSearchRequest
            let searchRequest = MusicCatalogSearchRequest(term: artistName, types: [Artist.self])
            let searchResponse = try await searchRequest.response()
            
            if let firstArtist = searchResponse.artists.first {
                // Look up artist structural object by ID using MusicCatalogResourceRequest
                let resourceRequest = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: firstArtist.id)
                let resourceResponse = try await resourceRequest.response()
                
                if let detailedArtist = resourceResponse.items.first {
                    // Access native .artwork attribute
                    if let artwork = detailedArtist.artwork {
                        if let url = artwork.url(width: 300, height: 300) {
                            self.artworkURL = url
                        }
                    }
                }
            }
        } catch {
            print("MusicKit Artist lookup failed for \(artistName): \(error.localizedDescription)")
        }
    }
}
import SwiftUI
import AppKit

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
            ($0.trackRepresentative.year ?? 0) > ($1.trackRepresentative.year ?? 0)
        }
    }
    
    var mostPlayedSongs: [LocalTrack] {
        artistSongs.sorted { $0.playCount > $1.playCount }.prefix(4).map { $0 }
    }
    
    var mostPlayedAlbums: [LocalAlbum] {
        artistAlbums.prefix(5).map { $0 } // Mock logic for most played
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
                    if let firstSong = artistSongs.first {
                        AsyncFlexibleThumbnailView(track: firstSong, maxPixelSize: 600, theme: state.theme, cornerRadius: 0)
                            .frame(height: 300)
                            .clipped()
                            .blur(radius: 20)
                            .overlay(Color.black.opacity(0.4))
                    }
                    
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
                }
                .padding(.horizontal, 24)
                
                // Most Played Songs Shelf
                if !mostPlayedSongs.isEmpty {
                    ShelfHeader(title: "Most Played Songs", action: {
                        state.activeFilterType = "artist"
                        // Handle navigation to dedicated list (not implemented fully as requested but chevron routes are requested)
                    })
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(mostPlayedSongs) { track in
                            HStack {
                                AsyncFlexibleThumbnailView(track: track, maxPixelSize: 96, theme: state.theme, cornerRadius: 4)
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading) {
                                    Text(track.title).font(.headline).lineLimit(1)
                                    Text("\(track.playCount) plays").font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(state.theme.cardBackground.opacity(0.5))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                // Most Played Albums Shelf
                if !mostPlayedAlbums.isEmpty {
                    ShelfHeader(title: "Most Played Albums", action: {})
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(mostPlayedAlbums) { album in
                                AlbumCell(album: album, state: state)
                                    .frame(width: 160)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Albums Shelf
                if !artistAlbums.isEmpty {
                    ShelfHeader(title: "Albums", action: {})
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(artistAlbums) { album in
                                AlbumCell(album: album, state: state)
                                    .frame(width: 160)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Songs Shelf
                if !artistSongs.isEmpty {
                    ShelfHeader(title: "Songs", action: {})
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
                    ShelfHeader(title: "Found in your playlists", action: {})
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
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
