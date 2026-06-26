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
                    SidebarView(state: state)
                        .frame(minWidth: 200)
                        .navigationTitle("Library")
                } detail: {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if state.selectedTab == "expand-library" {
                                LibraryExpanderWebView()
                            } else if state.selectedTab == "songs" || state.selectedTab?.hasPrefix("playlist-") == true || state.selectedTab == "recently-added" {
                                SongTableView(state: state, engine: engine)
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
                                LyricsSidebarView(state: state, engine: engine)
                                    .transition(.move(edge: .trailing))
                            case .queue:
                                QueueSidebarView(state: state, engine: engine)
                                    .transition(.move(edge: .trailing))
                            case .output:
                                OutputDeviceSidebarView(state: state, engine: engine)
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
                PlayerControlsView(state: state, engine: engine, showFullscreen: $showFullscreen, showSettings: $showSettings)
            }
            .ignoresSafeArea(.container, edges: .top)
            
            if showFullscreen {
                FullLyricsView(state: state, engine: engine, isPresented: $showFullscreen)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
            
            // Global Keyboard Shortcuts
            Group {
                Button("") { engine.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                
                Button("") {
                    if let current = engine.currentTrack, let idx = state.tracks.firstIndex(where: { $0.id == current.id }) {
                        let nextIdx = (idx + 1) % state.tracks.count
                        engine.playTrack(state.tracks[nextIdx])
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                
                Button("") {
                    if let current = engine.currentTrack, let idx = state.tracks.firstIndex(where: { $0.id == current.id }) {
                        let prevIdx = (idx - 1 + state.tracks.count) % state.tracks.count
                        engine.playTrack(state.tracks[prevIdx])
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                
                Button("") {
                    state.selectedTab = "songs"
                    // Search focus could be complex in pure SwiftUI across tabs, but switching to the main view implies it will be visible.
                }
                .keyboardShortcut("f", modifiers: [.command])
                
                Button("") {
                    if state.activeRightSidebar == .lyrics {
                        state.activeRightSidebar = .none
                    } else {
                        state.activeRightSidebar = .lyrics
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
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
    
    let themes = ["Space Gray", "Midnight Indigo", "Sakura Blossom", "Sunset Glow", "Cyber Neon"]
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem(for: nil)
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Play / Pause", action: #selector(togglePlayPause), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
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
                }
                .onChange(of: engine.currentTrack) { track in
                    appDelegate.updateStatusItem(for: track)
                }
                .touchBar {
                    if let track = engine.currentTrack {
                        Text(track.title)
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
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "square.stack")
                        .font(.title3)
                        .foregroundColor(state.theme.accent)
                    Text("Albums")
                        .font(.title2)
                        .bold()
                        .foregroundColor(state.theme.textPrimary)
                }
                .padding(.top)
                
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(state.albumsList) { album in
                        Button(action: {
                            state.activeFilterType = "album"
                            state.activeFilterValue = album.name
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(state.theme.cardBackground)
                                        .aspectRatio(1.0, contentMode: .fit)
                                    
                                    if let artData = album.trackRepresentative.embeddedArtData, let nsImage = NSImage(data: artData) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .cornerRadius(10)
                                    } else if let imageURL = album.trackRepresentative.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .cornerRadius(10)
                                    } else {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 40))
                                            .foregroundColor(state.theme.accent.opacity(0.8))
                                    }
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
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(state.theme.background)
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
                                    
                                    if let artData = artist.trackRepresentative.embeddedArtData, let nsImage = NSImage(data: artData) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                    } else if let imageURL = artist.trackRepresentative.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                    } else {
                                        // Dynamic API Lookup using MusicCatalogResourceRequest from MusicKit
                                        MusicKitArtistImageView(artistName: artist.name, themeAccent: state.theme.accent)
                                    }
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
                                    
                                    if let artData = genre.trackRepresentative.embeddedArtData, let nsImage = NSImage(data: artData) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .cornerRadius(8)
                                    } else if let imageURL = genre.trackRepresentative.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .cornerRadius(8)
                                    } else {
                                        Image(systemName: "music.note")
                                            .font(.body)
                                            .foregroundColor(state.theme.accent)
                                    }
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
