//
//  MainApp.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

// MARK: - Window content

struct macOSMusicPlayerContentView: View {
    @EnvironmentObject var state: AppStateManager
    /// Held as a plain reference: the window chrome doesn't need to redraw when playback state changes.
    let engine: AudioEngineManager
    @ObservedObject private var importer = LibraryImporter.shared
    @ObservedObject private var appleMusicSync = AppleMusicSync.shared
    @State private var isDropTargeted = false
    @State private var tabBeforeSearch: String?

    var body: some View {
        let theme = state.theme

        ZStack {
            VStack(spacing: 0) {
                NavigationSplitView {
                    SidebarView(state: state, showSettings: $state.showSettingsSheet, engine: engine)
                        .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 320)
                } detail: {
                    HStack(spacing: 0) {
                        DetailRouter(state: state, engine: engine)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if state.activeRightSidebar != .none {
                            Rectangle().fill(theme.hairline).frame(width: 1)
                            rightPanel
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .contentZoom()
                    .background(theme.background)
                    .ignoresSafeArea(.container, edges: .top)
                }
                .toolbar(state.showFullscreenPlayer ? .hidden : .automatic, for: .windowToolbar)
                .searchable(text: $state.searchKeyword, placement: .sidebar, prompt: "Search Library")

                PlayerControlsView(
                    state: state,
                    engine: engine,
                    timeTracker: engine.timeTracker,
                    showFullscreen: $state.showFullscreenPlayer,
                    showSettings: $state.showSettingsSheet
                )
            }
            .overlay(alignment: .bottom) {
                ImportToast(importer: importer, theme: theme)
                    .padding(.bottom, 104)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: importer.summary)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            Label("Drop to add to your library", systemImage: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }

            if state.showFullscreenPlayer {
                FullLyricsView(state: state, engine: engine, timeTracker: engine.timeTracker, isPresented: $state.showFullscreenPlayer)
                    .contentZoom()
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .bottom).combined(with: .opacity)))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: state.showFullscreenPlayer)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .onChange(of: state.searchKeyword) { _, query in routeSearch(query) }
        .onAppear {
            LibraryManager.shared.startMonitoringAutoAddFolder { urls in
                MainActor.assumeIsolated {
                    LibraryImporter.shared.importFromAutoAddFolder(urls, into: state)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .sheet(isPresented: $state.showSettingsSheet) {
            PreferencesView(state: state, isPresented: $state.showSettingsSheet)
        }
        .sheet(isPresented: $state.showSyncWindow) {
            DeviceSyncView(state: state)
        }
        .sheet(isPresented: $state.showImportOptions) {
            AppleMusicImportSheet(state: state)
        }
        .sheet(isPresented: $appleMusicSync.isPresented) {
            AppleMusicSyncSheet(theme: theme)
        }
        .removalDialog(state: state)
    }

    @ViewBuilder
    private var rightPanel: some View {
        switch state.activeRightSidebar {
        case .lyrics:
            LyricsSidebarView(state: state, engine: engine, timeTracker: engine.timeTracker)
        case .queue:
            QueueSidebarView(state: state, engine: engine)
        case .output:
            OutputDeviceSidebarView(state: state, engine: engine)
        case .none:
            EmptyView()
        }
    }

    /// Typing in the sidebar search opens the search results (Songs and playlists filter their
    /// list in place instead). Clearing the search goes back to where you were.
    private func routeSearch(_ query: String) {
        let tab = state.selectedTab ?? "home"
        if query.isEmpty {
            if tab == "search", state.activeFilterType == nil {
                state.navigate(to: tabBeforeSearch ?? "home", keepingSearch: false)
            }
            return
        }
        if tab == "search", state.activeFilterType != nil {
            // Typing on a search "See All" page shows the new results.
            state.activeFilterType = nil
            state.activeFilterValue = nil
            return
        }
        let filtersInPlace = (tab == "songs" || tab.hasPrefix("playlist-") || tab == "allPlaylists") && state.activeFilterType == nil
        if !filtersInPlace && tab != "search" {
            if tab != "search" { tabBeforeSearch = tab }
            state.navigate(to: "search", keepingSearch: true)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.withLock { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                LibraryImporter.shared.importURLs(urls, into: state)
            }
        }
        return true
    }
}

/// Picks the page for the current sidebar selection / drill-down.
struct DetailRouter: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager

    var body: some View {
        let theme = state.theme
        let tab = state.selectedTab ?? "home"

        VStack(spacing: 0) {
            if state.activeFilterType != nil {
                HStack {
                    Button {
                        state.goBack()
                    } label: {
                        Label(state.backTitle, systemImage: "chevron.left")
                    }
                    .buttonStyle(PillButtonStyle(kind: .ghost, theme: theme, compact: true))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 2)
            }

            content(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func content(tab: String) -> some View {
        if tab == "songs" || tab.hasPrefix("playlist-") {
            SongTableView(state: state, engine: engine)
        } else if let filter = state.activeFilterType, let value = state.activeFilterValue {
            switch filter {
            case "album":
                AlbumDetailView(state: state, engine: engine, albumName: value)
                    .id(value)
            case "artist" where tab == "albums":
                AlbumGridView(state: state, engine: engine)
            case "artist":
                ArtistPageView(state: state, engine: engine, name: value)
                    .id(value)
            case "genre":
                GenrePageView(state: state, engine: engine, name: value)
                    .id(value)
            case "genreSongs":
                TrackListPage(state: state, engine: engine, title: "Songs", subtitle: value,
                              tracks: state.libraryTracks.filter { $0.genre == value }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
                    .id(value)
            case "artistSection":
                let parts = value.components(separatedBy: "\u{1}")
                if parts.count == 2, let section = ArtistSection(rawValue: parts[0]) {
                    ArtistSectionView(state: state, engine: engine, section: section, name: parts[1])
                        .id(value)
                }
            case "searchSection":
                let parts = value.components(separatedBy: "\u{1}")
                if parts.count == 2, let section = SearchSection(rawValue: parts[0]) {
                    SearchSectionView(state: state, engine: engine, section: section, query: parts[1])
                        .id(value)
                }
            default:
                SongTableView(state: state, engine: engine)
            }
        } else {
            switch tab {
            case "recently-added":
                AlbumGridView(state: state, engine: engine, isRecentlyAdded: true)
            case "albums":
                AlbumGridView(state: state, engine: engine)
            case "artists":
                ArtistGridView(state: state)
            case "genres":
                GenreGridView(state: state)
            case "meshReplay":
                MeshReplayView(state: state, stats: Self.replayStats(for: state))
            case "getMusic":
                GetMusicView(state: state)
            case "search":
                SearchResultsView(state: state, engine: engine)
            case "statistics":
                StatisticsView(state: state, engine: engine)
            case "allPlaylists":
                AllPlaylistsView(state: state)
            default:
                HomeView(state: state, engine: engine)
            }
        }
    }

    static func replayStats(for state: AppStateManager) -> ReplayStats {
        let played = state.libraryTracks.filter { $0.playCount > 0 }
        let topTracks = played.sorted { $0.playCount > $1.playCount }.prefix(10).map {
            TrackPlayHistory(trackId: $0.id, title: $0.title, artist: $0.artist, playCount: $0.playCount, totalListenDuration: $0.duration * Double($0.playCount))
        }
        var artistPlays: [String: Int] = [:]
        for track in played { artistPlays[track.artist, default: 0] += track.playCount }
        let topArtists = artistPlays.sorted { $0.value > $1.value }.prefix(10).map { ArtistMilestone(name: $0.key, playCount: $0.value, badge: nil) }
        return ReplayStats(
            year: Calendar.current.component(.year, from: Date()),
            totalListeningTimeSeconds: state.libraryStats.listeningSeconds,
            topTracks: Array(topTracks),
            topArtists: Array(topArtists),
            topAlbums: [:],
            topGenres: [:],
            monthlyTrends: []
        )
    }
}

// MARK: - Settings

struct PreferencesView: View {
    @ObservedObject var state: AppStateManager
    @Binding var isPresented: Bool
    @ObservedObject private var lastFM = LastFMService.shared
    @ObservedObject private var musicMirror = MusicAppMirror.shared
    @AppStorage("dev_bypass_replay_timegate") var bypassReplayTimegate: Bool = false
    @State private var section: Section = .appearance
    @State private var confirm: Confirmation?
    @State private var notice: String?

    enum Section: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case playback = "Playback"
        case library = "Library"
        case appleMusic = "Apple Music"
        case scrobbling = "Last.fm"
        case devices = "iPhone Sync"
        case songs = "Songs List"
        case advanced = "Advanced"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .playback: return "play.circle.fill"
            case .library: return "music.note.house.fill"
            case .appleMusic: return "music.note"
            case .scrobbling: return "dot.radiowaves.left.and.right"
            case .devices: return "iphone"
            case .songs: return "list.bullet.rectangle.fill"
            case .advanced: return "wrench.and.screwdriver.fill"
            }
        }
    }

    enum Confirmation: String, Identifiable {
        case clearLibrary, resetPlays, clearHistory, clearFavorites, clearArtwork, resetSettings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clearLibrary: return "Clear your entire library?"
            case .resetPlays: return "Reset all play counts?"
            case .clearHistory: return "Clear listening history?"
            case .clearFavorites: return "Remove every song from Favorites?"
            case .clearArtwork: return "Clear the artwork cache?"
            case .resetSettings: return "Reset all settings?"
            }
        }
        var message: String {
            switch self {
            case .clearLibrary: return "All songs, playlists, favorites and listening history are removed from Mesh Player. Your audio files stay on disk, so you can import them again."
            case .resetPlays: return "Play counts and last-played dates go back to zero for every song. Mesh Replay history is cleared too."
            case .clearHistory: return "Mesh Replay's listening history is deleted. Play counts are kept."
            case .clearFavorites: return "Every song is removed from Favorites."
            case .clearArtwork: return "Cached album art and animated artwork lookups are deleted and rebuilt as you browse."
            case .resetSettings: return "Theme, columns and playback options go back to their defaults. Your library isn't touched."
            }
        }
        var button: String {
            switch self {
            case .clearLibrary: return "Clear Library"
            case .resetPlays: return "Reset Play Counts"
            case .clearHistory: return "Clear History"
            case .clearFavorites: return "Clear Favorites"
            case .clearArtwork: return "Clear Cache"
            case .resetSettings: return "Reset Settings"
            }
        }
    }

    var body: some View {
        let theme = state.theme
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                        notice = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(section == item ? theme.onAccent : theme.accent)
                                .frame(width: 24, height: 24)
                                .background(section == item ? theme.accent : theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(section == item ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
                    .keyboardShortcut(.defaultAction)
                    .padding(.horizontal, 8)
            }
            .padding(16)
            .frame(width: 210)
            .background(theme.sidebarBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(section.rawValue)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    content(theme)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.background)
        }
        .frame(width: 800, height: 600)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { item in
            Button(item.button, role: .destructive) { perform(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }

    private func perform(_ item: Confirmation) {
        switch item {
        case .clearLibrary:
            state.clearLibrary()
            notice = "Library cleared."
        case .resetPlays:
            state.resetPlayCounts()
            notice = "Play counts reset."
        case .clearHistory:
            state.clearPlayHistory()
            notice = "Listening history cleared."
        case .clearFavorites:
            state.clearFavorites()
            notice = "Favorites cleared."
        case .clearArtwork:
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player")
            for name in ["Artwork", "animated-artwork.json"] { try? FileManager.default.removeItem(at: caches.appendingPathComponent(name)) }
            notice = "Artwork cache cleared. It rebuilds after a relaunch."
        case .resetSettings:
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("settings.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            notice = "Settings reset. Relaunch Mesh Player to apply every default."
        }
    }

    @ViewBuilder
    private func content(_ theme: ThemeColor) -> some View {
        switch section {
        case .appearance:
            settingsGroup(theme, title: "Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(ThemeCatalog.names, id: \.self) { name in
                        ThemeSwatch(name: name, isSelected: state.currentThemeName == name, currentTheme: theme) {
                            withAnimation(.easeInOut(duration: 0.25)) { state.currentThemeName = name }
                        }
                    }
                }
            }
            settingsGroup(theme, title: "Display") {
                Toggle("Animated album artwork", isOn: $state.animatedArtworkEnabled)
                caption("Plays Apple Music's motion artwork on album pages and in the full screen player when an album has it.", theme)
                Toggle("Show album artwork in the Dock while playing", isOn: $state.showDockArtwork)
                Toggle("Automatically scroll synced lyrics", isOn: $state.autoScrollLyrics)
            }
        case .playback:
            settingsGroup(theme, title: "Spatial Audio") {
                Toggle("Play Dolby Atmos and multichannel songs in spatial audio", isOn: $state.enableAtmos)
                Toggle("Spatialize stereo songs", isOn: $state.spatialAudioActive)
                    .disabled(!state.enableAtmos)
                caption("Takes effect from the next song. Spatial rendering needs supported headphones or speakers.", theme)
            }
            settingsGroup(theme, title: "Play Counts") {
                caption("A play is counted once you've heard half of a song. Last.fm scrobbles after half the song or 4 minutes, whichever comes first.", theme)
            }
        case .library:
            let stats = state.libraryStats
            settingsGroup(theme, title: "Import") {
                caption("Files inside your Music folder are used in place; files from elsewhere are copied into ~/Music/Mesh Player.", theme)
                HStack(spacing: 8) {
                    Button {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { state.showImportOptions = true }
                    } label: {
                        Label("Import Apple Music Library…", systemImage: "music.note")
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
                    Button {
                        isPresented = false
                        LibraryImporter.shared.chooseFolderAndImport(into: state)
                    } label: {
                        Label("Import Folder…", systemImage: "folder")
                    }
                    .buttonStyle(PillButtonStyle(kind: .ghost, theme: theme, compact: true))
                }
            }
            settingsGroup(theme, title: "Your Library") {
                Text("\(Fmt.songs(stats.songs)) · \(Fmt.count(stats.albums)) albums · \(Fmt.count(stats.artists)) artists · \(state.playlists.count) playlists")
                    .foregroundStyle(theme.textSecondary)
                Toggle("List collaborations under the first artist", isOn: $state.mergeCollaborationArtists)
                caption("Songs by “Kanye West & Kodak Black” or “Drake feat. Rihanna” appear under Kanye West or Drake in Artists instead of getting their own entry.", theme)
                HStack(spacing: 8) {
                    Button("Show Mesh Library in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([LibraryManager.shared.libraryDirectory])
                    }
                    Button("Remove Missing Songs") {
                        let removed = state.removeMissingTracks()
                        notice = removed == 0 ? "No missing songs found." : "Removed \(Fmt.songs(removed)) whose files are gone."
                    }
                    .help("Removes songs whose audio file no longer exists on disk.")
                    Button("Clear Artwork Cache…") { confirm = .clearArtwork }
                }
            }
            settingsGroup(theme, title: "Reset") {
                caption("These can't be undone.", theme)
                HStack(spacing: 8) {
                    Button("Reset Play Counts…") { confirm = .resetPlays }
                    Button("Clear Listening History…") { confirm = .clearHistory }
                    Button("Clear Favorites…") { confirm = .clearFavorites }
                }
                Button {
                    confirm = .clearLibrary
                } label: {
                    Label("Clear Entire Library…", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                caption("Removes every song, playlist and statistic from Mesh Player. Audio files on disk are kept.", theme)
            }
        case .appleMusic:
            settingsGroup(theme, title: "Send Changes to Apple Music") {
                caption("Adds songs you brought into Mesh Player to the Music app, mirrors your playlists (same songs, same order), and marks your Favorites as loved. You review every change before anything is sent.", theme)
                Button {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppleMusicSync.shared.presentExport(playlists: nil, state: state) }
                } label: {
                    Label("Sync Changes to Apple Music…", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
                caption("Single playlists can be sent from their ••• menu. macOS asks once for permission to control the Music app.", theme)
            }
            settingsGroup(theme, title: "Get Music") {
                Picker("Download quality", selection: Binding(get: { AmdlDownloader.shared.quality }, set: { AmdlDownloader.shared.quality = $0 })) {
                    ForEach(AmdlDownloader.Quality.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 320)
                caption("Used when downloading through am-dl from the Get Music page.", theme)
            }
        case .scrobbling:
            lastFMSettings(theme)
        case .devices:
            settingsGroup(theme, title: "iPhone") {
                caption("Open Mesh Player on your iPhone, then sync over Wi-Fi or a USB cable. Your songs, artwork, lyrics, playlists and favorites are copied; plays and favorites from the iPhone come back to your Mac.", theme)
                Button {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { state.showSyncWindow = true }
                } label: {
                    Label("Sync iPhone…", systemImage: "iphone")
                }
                .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
            }
        case .songs:
            settingsGroup(theme, title: "Visible Columns") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    Toggle("Artist", isOn: $state.showArtistColumn)
                    Toggle("Album", isOn: $state.showAlbumColumn)
                    Toggle("Genre", isOn: $state.showGenreColumn)
                    Toggle("Year", isOn: $state.showYearColumn)
                    Toggle("Plays", isOn: $state.showPlaysColumn)
                    Toggle("Date Added", isOn: $state.showDateAddedColumn)
                    Toggle("Quality", isOn: $state.showFormatColumn)
                    Toggle("Favorite", isOn: $state.showFavoritesColumn)
                    Toggle("Time", isOn: $state.showTimeColumn)
                }
                caption("Tip: click a column header to sort, drag headers to reorder, and right-click them to hide columns.", theme)
            }
        case .advanced:
            settingsGroup(theme, title: "Developer") {
                Toggle("Disable Replay time-gating", isOn: $bypassReplayTimegate)
                caption("Bypasses calendar restrictions on Yearly, Monthly, and Weekly Replays for testing.", theme)
            }
            settingsGroup(theme, title: "Settings") {
                Button("Reset All Settings…") { confirm = .resetSettings }
            }
        }
    }

    @ViewBuilder
    private func lastFMSettings(_ theme: ThemeColor) -> some View {
        settingsGroup(theme, title: "Account") {
            switch lastFM.status {
            case .connected:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected as \(lastFM.username ?? "")").font(.system(size: 13, weight: .semibold))
                        Text(lastFM.pending.isEmpty ? (lastFM.lastScrobbled.map { "Last scrobble: \($0)" } ?? "Ready to scrobble") : "\(lastFM.pending.count) scrobble\(lastFM.pending.count == 1 ? "" : "s") waiting to send")
                            .font(.system(size: 11.5)).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    if !lastFM.pending.isEmpty { Button("Send Now") { lastFM.flushNow() } }
                    Button("Open Profile") {
                        if let name = lastFM.username, let url = URL(string: "https://www.last.fm/user/\(name)") { NSWorkspace.shared.open(url) }
                    }
                    Button("Disconnect") { lastFM.disconnect() }
                }
                Toggle("Scrobble songs I play", isOn: $lastFM.isEnabled)
                Toggle("Love tracks on Last.fm when I add them to Favorites", isOn: $lastFM.syncLoves)
            case .waitingForApproval:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Approve Mesh Player in your browser (“Yes, allow access”). This page updates by itself.")
                        .font(.system(size: 12.5))
                    Spacer()
                    Button("Cancel") { lastFM.cancelConnect() }
                }
            default:
                if case .failed(let message) = lastFM.status {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                caption("Last.fm needs an API account for Mesh Player. It's free and takes a minute: create one, then paste the API key and shared secret below. Leave the callback URL empty.", theme)
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.last.fm/api/account/create")!)
                } label: {
                    Label("Create a Last.fm API Account", systemImage: "arrow.up.right.square")
                }
                TextField("API key", text: $lastFM.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                SecureField("Shared secret", text: $lastFM.apiSecret)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                Button {
                    lastFM.connect()
                } label: {
                    Label("Connect to Last.fm", systemImage: "link")
                }
                .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
                .disabled(!lastFM.hasCredentials)
            }
        }
        settingsGroup(theme, title: "How scrobbling works") {
            caption("Mesh Player tells Last.fm what's playing as each song starts, and scrobbles it after half the song or 4 minutes (songs shorter than 30 seconds are skipped). Scrobbles made offline are saved and sent later, up to two weeks after the play.", theme)
        }
        settingsGroup(theme, title: "Through the Music App") {
            Toggle("Play along silently in the Music app", isOn: $musicMirror.isEnabled)
            switch musicMirror.status {
            case .mirroring(let title):
                Label("Mirroring “\(title)” in Music", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12)).foregroundStyle(.green)
            case .notInMusic(let title):
                Label("“\(title)” isn't in your Music library, so it can't be mirrored", systemImage: "questionmark.circle")
                    .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            default:
                EmptyView()
            }
            caption("Another way to scrobble: while Mesh Player plays a song, the Music app plays the same song from your Music library in step with it — pausing, seeking and skipping along — with Music's volume at zero. Music then counts the play itself, so Apple Music Replay, Music's play counts and any scrobbler that watches the Music app pick it up. Music's volume is restored when you turn this off or quit. Songs that aren't in your Music library are skipped.", theme)
        }
    }

    private func caption(_ text: String, _ theme: ThemeColor) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsGroup<Content: View>(_ theme: ThemeColor, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.textSecondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 13))
            .foregroundStyle(theme.textPrimary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(theme)
        }
    }
}

private struct ThemeSwatch: View {
    let name: String
    let isSelected: Bool
    let currentTheme: ThemeColor
    let action: () -> Void

    var body: some View {
        let t = ThemeCatalog.theme(named: name)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    t.sidebarBackground
                        .frame(width: 34)
                        .overlay(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    Capsule().fill(i == 0 ? t.accent : t.textSecondary.opacity(0.5)).frame(width: 18, height: 3)
                                }
                            }
                            .padding(.top, 10)
                        }
                    ZStack(alignment: .topLeading) {
                        t.background
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(t.textPrimary).frame(width: 50, height: 5)
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 3).fill(t.accent).frame(width: 22, height: 22)
                                RoundedRectangle(cornerRadius: 3).fill(t.cardBackground).frame(width: 22, height: 22)
                                RoundedRectangle(cornerRadius: 3).fill(t.cardBackground).frame(width: 22, height: 22)
                            }
                            Capsule().fill(t.textSecondary.opacity(0.6)).frame(width: 40, height: 3)
                        }
                        .padding(10)
                    }
                }
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? currentTheme.accent : currentTheme.hairline, lineWidth: isSelected ? 2.5 : 1)
                )

                Text(name.replacingOccurrences(of: " (Apple Music)", with: "").replacingOccurrences(of: " (Frutiger Aero)", with: ""))
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? currentTheme.textPrimary : currentTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .hoverLift(1.03)
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var engine: AudioEngineManager?
    var state: AppStateManager?
    var dockIdleTimer: Timer?
    private var keyMonitor: Any?
    private var dockTrackKey: String?

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

        // Space toggles playback unless a text field is being edited; ⌘+ / ⌘- / ⌘0 zoom the page.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection([.command, .option, .control]) == .command,
               let key = event.charactersIgnoringModifiers {
                switch key {
                case "=", "+": ContentZoom.zoomIn(); return nil
                case "-", "_": ContentZoom.zoomOut(); return nil
                case "0": ContentZoom.reset(); return nil
                default: break
                }
            }
            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            if let responder = event.window?.firstResponder, responder is NSText || responder is NSTextView { return event }
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return nil
        }
    }

    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleFavourite() {
        guard let track = engine?.currentTrack, let state else { return }
        state.toggleFavorite(track: track)
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
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Mesh Player")
        if let track = track {
            let maxLen = 40
            let titleStr = track.title.count > maxLen ? String(track.title.prefix(maxLen)) + "…" : track.title
            button.title = " \(titleStr)"
        } else {
            button.title = ""
        }
    }

    func updateDockTile(for track: LocalTrack?, isPlaying: Bool) {
        let dockTile = NSApplication.shared.dockTile
        let shouldShowArtwork = state?.showDockArtwork ?? false

        if shouldShowArtwork, let track = track, isPlaying {
            dockIdleTimer?.invalidate()
            dockIdleTimer = nil
            let key = track.artworkKey
            guard key != dockTrackKey || dockTile.contentView == nil else { return }
            dockTrackKey = key
            Task {
                let image = await ArtworkStore.shared.image(for: track, pixelSize: 256)
                guard self.dockTrackKey == key else { return }
                let imageView = NSImageView()
                imageView.image = image ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
                imageView.imageScaling = .scaleProportionallyUpOrDown
                dockTile.contentView = imageView
                dockTile.display()
            }
        } else if dockIdleTimer == nil && dockTile.contentView != nil {
            dockIdleTimer = Timer.scheduledTimer(withTimeInterval: shouldShowArtwork ? 10.0 : 0.0, repeats: false) { [weak self] _ in
                dockTile.contentView = nil
                dockTile.display()
                MainActor.assumeIsolated {
                    self?.dockTrackKey = nil
                    self?.dockIdleTimer = nil
                }
            }
        }
    }
}

// MARK: - App

@main
struct macOSMusicPlayerApp: App {
    @StateObject private var state = AppStateManager()
    @StateObject private var engine = AudioEngineManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            macOSMusicPlayerContentView(engine: engine)
                .frame(minWidth: 1000, minHeight: 640)
                .environmentObject(state)
                .environmentObject(engine)
                .onAppear {
                    appDelegate.engine = engine
                    appDelegate.state = state

                    engine.onPlayNext = {
                        appDelegate.playNext()
                    }
                    engine.onPlayPrevious = {
                        appDelegate.playPrevious()
                    }
                    engine.onTrackStarted = { track in
                        LastFMService.shared.nowPlaying(track)
                        MusicAppMirror.shared.trackStarted(track)
                    }
                    engine.onSeek = { time in
                        MusicAppMirror.shared.seeked(to: time)
                    }
                    MusicAppMirror.shared.attach(to: engine)
                    engine.onScrobblePoint = { track, startedAt in
                        LastFMService.shared.scrobble(track, startedAt: startedAt)
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
                            var merged = updatedTrack
                            // Keep library-side state that may have changed while the track played.
                            merged.isFavorite = state.tracks[idx].isFavorite
                            merged.playCount = state.tracks[idx].playCount
                            merged.lastPlayedDate = state.tracks[idx].lastPlayedDate
                            state.tracks[idx] = merged
                        }
                    }
                }
                .onChange(of: engine.currentTrack?.id) { _, _ in
                    appDelegate.updateStatusItem(for: engine.currentTrack)
                    appDelegate.updateDockTile(for: engine.currentTrack, isPlaying: engine.isPlaying)
                }
                .onChange(of: engine.isPlaying) { _, isPlaying in
                    appDelegate.updateDockTile(for: engine.currentTrack, isPlaying: isPlaying)
                }
                .onChange(of: state.showDockArtwork) { _, _ in
                    appDelegate.updateDockTile(for: engine.currentTrack, isPlaying: engine.isPlaying)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Apple Music Library…") {
                    state.showImportOptions = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Sync Changes to Apple Music…") {
                    AppleMusicSync.shared.presentExport(playlists: nil, state: state)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Get Music…") {
                    state.selectedTab = "getMusic"
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Add to Library…") {
                    LibraryImporter.shared.chooseFolderAndImport(into: state)
                }
                .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Sync iPhone…") {
                    state.showSyncWindow = true
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Close") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { state.showSettingsSheet = true }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .toolbar) {
                // The key monitor in AppDelegate handles these shortcuts (so ⌘= works as ⌘+ too).
                Button("Zoom In") { ContentZoom.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { ContentZoom.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { ContentZoom.reset() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("Show Lyrics") {
                    state.activeRightSidebar = state.activeRightSidebar == .lyrics ? .none : .lyrics
                }
                .keyboardShortcut("u", modifiers: [.command, .control])
                Button("Show Playing Next") {
                    state.activeRightSidebar = state.activeRightSidebar == .queue ? .none : .queue
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
                Button("Full Screen Player") {
                    if engine.currentTrack != nil { state.showFullscreenPlayer.toggle() }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Enter Full Screen") {
                    NSApplication.shared.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }

            CommandMenu("Controls") {
                Button("Play / Pause") { appDelegate.togglePlayPause() }
                Button("Stop") { appDelegate.engine?.pause() }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Next Track") { appDelegate.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Track") { appDelegate.playPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Shuffle") { state.toggleShuffle(currentTrack: engine.currentTrack) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Cycle Repeat") { state.repeatMode = (state.repeatMode + 1) % 3 }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                Button("Go to Current Song") {
                    if let track = engine.currentTrack { state.showAlbum(of: track) }
                }
                .keyboardShortcut("l", modifiers: .command)
                Divider()
                Button("Volume Up") { engine.volume = min(1, engine.volume + 0.1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Volume Down") { engine.volume = max(0, engine.volume - 0.1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
            }

            CommandGroup(after: .windowList) {
                Button("Mini Player") {
                    if let window = NSApplication.shared.windows.first(where: { $0.title == "Mini Player" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
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
        .defaultSize(width: 340, height: 96)
        .windowResizability(.contentSize)
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject var state: AppStateManager
    @EnvironmentObject var engine: AudioEngineManager

    var body: some View {
        let theme = state.theme
        HStack(spacing: 12) {
            ArtworkView(track: engine.currentTrack, pixelSize: 140, cornerRadius: 8)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(engine.currentTrack?.title ?? "Not Playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(engine.currentTrack?.artist ?? "Mesh Player")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Button { state.playPrevious(engine: engine) } label: {
                        Image(systemName: "backward.fill").font(.system(size: 12))
                    }
                    .buttonStyle(IconButtonStyle(theme: theme, size: 26))
                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(theme: theme, isActive: true, size: 28, activeColor: theme.textPrimary))
                    Button { state.playNext(engine: engine) } label: {
                        Image(systemName: "forward.fill").font(.system(size: 12))
                    }
                    .buttonStyle(IconButtonStyle(theme: theme, size: 26))
                }
                .disabled(engine.currentTrack == nil)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 340, height: 96)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.background.opacity(0.55)
            }
        }
        .preferredColorScheme(theme.colorScheme)
    }
}

// MARK: - Albums

struct AlbumGridView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    var isRecentlyAdded: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 22, alignment: .top)]

    private func groupAlbums(_ albums: [LocalAlbum]) -> [(String, [LocalAlbum])] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let startOfMonth = calendar.date(byAdding: .month, value: -1, to: startOfToday)!

        var buckets: [(String, [LocalAlbum])] = [("Today", []), ("This Week", []), ("This Month", []), ("Earlier", [])]
        for album in albums {
            let date = album.trackRepresentative.dateAdded
            let index = date >= startOfToday ? 0 : (date >= startOfWeek ? 1 : (date >= startOfMonth ? 2 : 3))
            buckets[index].1.append(album)
        }
        return buckets.filter { !$0.1.isEmpty }
    }

    private var artistFilter: String? {
        state.activeFilterType == "artist" ? state.activeFilterValue : nil
    }

    private var sortedAlbums: [LocalAlbum] {
        var baseList = isRecentlyAdded ? state.recentlyAddedAlbumsList : state.albumsList
        if let artist = artistFilter {
            baseList = baseList.filter { $0.artist == artist || $0.trackRepresentative.artist == artist }
        }
        let query = state.searchKeyword.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            baseList = baseList.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
        }
        if isRecentlyAdded { return baseList }
        switch state.albumSortCriteria {
        case .dateAdded:
            return baseList.sorted { $0.trackRepresentative.dateAdded > $1.trackRepresentative.dateAdded }
        case .yearReleased:
            return baseList.sorted { ($0.trackRepresentative.year ?? 0) > ($1.trackRepresentative.year ?? 0) }
        case .title:
            return baseList.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist:
            return baseList.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        }
    }

    var body: some View {
        let theme = state.theme
        let albums = sortedAlbums

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    title: isRecentlyAdded ? "Recently Added" : (artistFilter.map { "Albums by \($0)" } ?? "Albums"),
                    subtitle: "\(Fmt.count(albums.count)) album\(albums.count == 1 ? "" : "s")",
                    theme: theme
                ) {
                    if !isRecentlyAdded {
                        Menu {
                            Picker("Sort By", selection: $state.albumSortCriteria) {
                                ForEach(AppStateManager.AlbumSortCriteria.allCases, id: \.self) { criteria in
                                    Text(criteria.rawValue).tag(criteria)
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label(state.albumSortCriteria.rawValue, systemImage: "arrow.up.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }

                if albums.isEmpty {
                    emptyState(theme)
                } else if isRecentlyAdded {
                    ForEach(groupAlbums(albums), id: \.0) { group in
                        Text(group.0)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 28)
                            .padding(.top, 10)
                            .padding(.bottom, 12)
                        grid(group.1, theme: theme)
                            .padding(.bottom, 16)
                    }
                } else {
                    grid(albums, theme: theme)
                }
            }
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }

    private func grid(_ albums: [LocalAlbum], theme: ThemeColor) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
            ForEach(albums) { album in
                AlbumCell(album: album, theme: theme) {
                    state.showAlbum(album.key)
                } onPlay: {
                    state.play(state.albumTracks(named: album.key), shuffled: false, engine: engine)
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private func emptyState(_ theme: ThemeColor) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            Text(state.searchKeyword.isEmpty ? "No albums yet" : "No albums match “\(state.searchKeyword)”")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

struct AlbumCell: View {
    let album: LocalAlbum
    let theme: ThemeColor
    var subtitle: String? = nil
    var pillTag: String? = nil
    let onOpen: () -> Void
    var onPlay: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkTile(track: album.trackRepresentative, theme: theme, pixelSize: 460, cornerRadius: 10, onPlay: onPlay)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let pillTag {
                    Text(pillTag)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.accent.opacity(0.13), in: Capsule())
                } else {
                    Text(subtitle ?? album.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - Artists

struct ArtistGridView: View {
    @ObservedObject var state: AppStateManager

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 24, alignment: .top)]

    var body: some View {
        let theme = state.theme
        let query = state.searchKeyword.trimmingCharacters(in: .whitespaces)
        let artists = query.isEmpty ? state.artistsList : state.artistsList.filter { $0.name.localizedCaseInsensitiveContains(query) }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Artists", subtitle: "\(Fmt.count(artists.count)) artists", theme: theme)

                LazyVGrid(columns: columns, alignment: .center, spacing: 26) {
                    ForEach(artists) { artist in
                        Button {
                            state.showArtist(artist.name)
                        } label: {
                            VStack(spacing: 10) {
                                CachedArtistProfileView(artistName: artist.name, themeAccent: theme.accent, size: 140, fallbackTrack: artist.trackRepresentative)
                                    .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 10, y: 5)
                                VStack(spacing: 2) {
                                    Text(artist.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                    Text(Fmt.songs(artist.tracksCount))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverLift(1.04)
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }
}

// MARK: - Genres

struct GenreGridView: View {
    @ObservedObject var state: AppStateManager

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 20)]

    var body: some View {
        let theme = state.theme
        let query = state.searchKeyword.trimmingCharacters(in: .whitespaces)
        let genres = state.genresList.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let covers = coverTracks()

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Genres", subtitle: "\(Fmt.count(genres.count)) genres", theme: theme) { EmptyView() }

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(genres) { genre in
                        GenreTile(genre: genre, covers: covers[genre.name] ?? [genre.trackRepresentative]) {
                            state.showGenre(genre.name)
                        }
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }

    /// Covers of each genre's three most played albums.
    private func coverTracks() -> [String: [LocalTrack]] {
        var byGenre: [String: [String: (track: LocalTrack, plays: Int)]] = [:]
        for track in state.libraryTracks {
            let key = state.albumKey(for: track)
            var albums = byGenre[track.genre, default: [:]]
            let current = albums[key]
            albums[key] = (current?.track ?? track, (current?.plays ?? 0) + track.playCount)
            byGenre[track.genre] = albums
        }
        return byGenre.mapValues { albums in
            albums.values.sorted { $0.plays > $1.plays }.prefix(3).map(\.track)
        }
    }
}

private struct GenreTile: View {
    let genre: LocalGenre
    let covers: [LocalTrack]
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let tint = GenreStyle.tint(for: genre.name)
        ZStack(alignment: .topLeading) {
            Color.black
            LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft glow behind the covers.
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 30, y: 40)
            GenreCoverFan(tracks: covers, size: 78)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 18)
                .padding(.bottom, 16)
                .scaleEffect(hovering ? 1.05 : 1, anchor: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(genre.name)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                Text(Fmt.songs(genre.tracksCount))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .frame(maxWidth: 150, alignment: .leading)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: tint.opacity(hovering ? 0.45 : 0.2), radius: hovering ? 16 : 8, y: 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hovering)
    }
}

// MARK: - Artist avatar

struct CachedArtistProfileView: View {
    let artistName: String
    let themeAccent: Color
    var size: CGFloat = 100
    var fallbackTrack: LocalTrack? = nil

    @State private var loadedImage: NSImage? = nil

    var body: some View {
        ZStack {
            if let nsImage = loadedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else if let fallbackTrack {
                ArtworkView(track: fallbackTrack, pixelSize: size * 2, cornerRadius: 0)
                    .overlay(Color.black.opacity(0.15))
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .task(id: artistName) {
            await fetchArtistArtwork()
        }
    }

    private var fallbackView: some View {
        let initial = artistName.first.map { String($0).uppercased() } ?? "A"
        return ZStack {
            ArtworkPlaceholder(seed: artistName, symbol: "person.fill")
            Text(initial)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private func fetchArtistArtwork() async {
        guard !artistName.isEmpty && artistName != "Unknown Artist" && artistName != "Local Artist" else { return }

        let cacheKey = NSString(string: "artist_avatar_\(artistName)_\(Int(size))")
        if let cached = ThumbnailGenerator.shared.cache.object(forKey: cacheKey) {
            loadedImage = cached
            return
        }

        do {
            guard let url = try await ArtistProfilePictureService.shared.fetchAndCacheProfilePicture(for: artistName) else { return }
            let pixel = size * 2
            let decoded = await Task.detached(priority: .utility) { ArtworkStore.downsample(url: url, maxPixel: pixel) }.value
            if let img = decoded {
                ThumbnailGenerator.shared.cache.setObject(img, forKey: cacheKey)
                withAnimation(.easeOut(duration: 0.2)) { loadedImage = img }
            }
        } catch {
            print("Failed to fetch artist profile picture: \(error)")
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager

    @State private var recommendedItems: [RecommendedTrackItem] = []
    @State private var onlineFacts: [UUID: String] = [:]

    private var recentTracks: [LocalTrack] {
        let played = state.libraryTracks.filter { $0.playCount > 0 }
        return Array(played.sorted { ($0.lastPlayedDate ?? $0.dateAdded) > ($1.lastPlayedDate ?? $1.dateAdded) }.prefix(12))
    }

    var body: some View {
        let theme = state.theme

        Group {
            if state.tracks.isEmpty {
                if state.isLibraryLoaded {
                    EmptyLibraryView(theme: theme) {
                        state.showImportOptions = true
                    } onImportFolder: {
                        LibraryImporter.shared.chooseFolderAndImport(into: state)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                content(theme)
            }
        }
        .background(theme.background)
        .onAppear {
            if recommendedItems.isEmpty && !state.tracks.isEmpty { generateRecommendations() }
        }
        .task(id: state.isLibraryLoaded) {
            guard state.isLibraryLoaded, onlineFacts.isEmpty else { return }
            let facts = await loadOnlineFacts()
            guard !facts.isEmpty, !Task.isCancelled else { return }
            onlineFacts = facts
            withAnimation(.easeInOut(duration: 0.25)) { generateRecommendations() }
        }
        .onChange(of: state.tracks.count) { _, _ in
            if recommendedItems.isEmpty && !state.tracks.isEmpty { generateRecommendations() }
        }
    }

    private func content(_ theme: ThemeColor) -> some View {
        let stats = state.libraryStats
        let recents = recentTracks
        let carousel = recents.isEmpty ? Array(state.libraryTracks.prefix(12)) : recents
        let recentAlbums = Array(state.recentlyAddedAlbumsList.prefix(14))

        return ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PageHeader(title: Fmt.greeting(), subtitle: Date().formatted(date: .complete, time: .omitted), theme: theme)
                    .padding(.bottom, -18)

                SectionHeader(title: "Your Stats", theme: theme) {
                    state.selectedTab = "statistics"
                }
                .padding(.bottom, -22)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    StatCardOS(title: "Songs", value: Fmt.count(stats.songs), icon: "music.note", gradientColors: [Color(red: 0.99, green: 0.33, blue: 0.47), Color(red: 0.85, green: 0.2, blue: 0.35)], theme: theme)
                    StatCardOS(title: "Albums", value: Fmt.count(stats.albums), icon: "square.stack.fill", gradientColors: [Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.42, blue: 0.2)], theme: theme)
                    StatCardOS(title: "Artists", value: Fmt.count(stats.artists), icon: "music.mic", gradientColors: [Color(red: 0.62, green: 0.45, blue: 1.0), Color(red: 0.42, green: 0.3, blue: 0.9)], theme: theme)
                    StatCardOS(title: "Plays", value: Fmt.count(stats.plays), icon: "play.fill", gradientColors: [Color(red: 0.2, green: 0.78, blue: 0.62), Color(red: 0.1, green: 0.6, blue: 0.5)], theme: theme)
                    StatCardOS(title: "Listening time", value: "~" + Fmt.listening(stats.listeningSeconds), icon: "clock.fill", gradientColors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.2, green: 0.42, blue: 0.9)], theme: theme)
                }
                .contentShape(Rectangle())
                .onTapGesture { state.selectedTab = "statistics" }
                .help("Open Statistics")
                .padding(.horizontal, 28)

                if !carousel.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: recents.isEmpty ? "Start Listening" : "Jump Back In", subtitle: recents.isEmpty ? "A few songs from your library" : "Recently played", theme: theme)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(carousel) { track in
                                    TrackCard(track: track, theme: theme) {
                                        state.play(carousel, startingAt: track, engine: engine)
                                    } onOpen: {
                                        state.showAlbum(of: track)
                                    }
                                    .frame(width: 156)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                        }
                    }
                }

                if !recentAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Recently Added", theme: theme) {
                            state.selectedTab = "recently-added"
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(recentAlbums) { album in
                                    AlbumCell(album: album, theme: theme) {
                                        state.showAlbum(album.key)
                                    } onPlay: {
                                        state.play(state.albumTracks(named: album.key), engine: engine)
                                    }
                                    .frame(width: 156)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader(title: "From Your Library", subtitle: "Each pick says why it was chosen", theme: theme)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { generateRecommendations() }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(IconButtonStyle(theme: theme, size: 28))
                        .help("Refresh")
                        .padding(.trailing, 24)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(recommendedItems) { item in
                            TrackCard(track: item.track, theme: theme, badge: item.badgeTag) {
                                state.play(recommendedItems.map(\.track), startingAt: item.track, engine: engine)
                            } onOpen: {
                                state.showAlbum(of: item.track)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                }
            }
            .padding(.bottom, 40)
        }
    }

    /// Picks songs for "From Your Library". Every pick is labelled with the real reason it was
    /// chosen — play counts, favorites, dates, your listening history, or (when online) Apple
    /// Music's top songs for your most played artists. Nothing is invented.
    private func generateRecommendations() {
        let now = Date()
        let cal = Calendar.current
        let library = state.libraryTracks
        guard !library.isEmpty else { recommendedItems = []; return }
        func item(_ track: LocalTrack, _ tag: String) -> RecommendedTrackItem { RecommendedTrackItem(track: track, badgeTag: tag) }
        func plural(_ n: Int, _ word: String) -> String { "\(Fmt.count(n)) \(word)\(n == 1 ? "" : "s")" }

        var pools: [[RecommendedTrackItem]] = []

        // Your most played songs and favorites.
        pools.append(library.filter { $0.playCount >= 3 }.sorted { $0.playCount > $1.playCount }.prefix(40).shuffled()
            .map { item($0, "Played \(plural($0.playCount, "time"))") })
        pools.append(library.filter(\.isFavorite).shuffled().map { item($0, "In your Favorites") })

        // On repeat this week (from the play history).
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var weekCounts: [UUID: Int] = [:]
        for entry in state.playHistoryLog where entry.timestamp >= weekAgo { weekCounts[entry.trackId, default: 0] += 1 }
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        pools.append(weekCounts.filter { $0.value >= 2 }.compactMap { id, n in byId[id].map { item($0, "Played \(plural(n, "time")) this week") } }.shuffled())

        // New and not played yet; played a lot but not lately.
        pools.append(library.filter { $0.playCount == 0 && now.timeIntervalSince($0.dateAdded) < 60 * 86_400 }.shuffled()
            .map { item($0, "Added \(Fmt.relative($0.dateAdded)) · not played yet") })
        pools.append(library.filter { t in
            guard t.playCount >= 3, let last = t.lastPlayedDate else { return false }
            return now.timeIntervalSince(last) > 60 * 86_400
        }.shuffled().map { item($0, "Last played \(Fmt.relative($0.lastPlayedDate ?? now))") })

        // Deeper cuts by the artists you play most.
        var artistPlays: [String: Int] = [:]
        for t in library { artistPlays[state.displayArtist(t.artist), default: 0] += t.playCount }
        let topArtists = artistPlays.filter { $0.value >= 5 }.sorted { $0.value > $1.value }.prefix(6)
        pools.append(topArtists.flatMap { artist, plays in
            library.filter { state.displayArtist($0.artist) == artist && $0.playCount <= 1 }.shuffled().prefix(3)
                .map { item($0, "You've played \(artist) \(plural(plays, "time"))") }
        }.shuffled())

        // Albums you're partway through.
        var albums: [String: [LocalTrack]] = [:]
        for t in library { albums[state.albumKey(for: t), default: []].append(t) }
        pools.append(albums.values.compactMap { songs -> RecommendedTrackItem? in
            let played = songs.filter { $0.playCount > 0 }.count
            guard songs.count >= 4, played * 2 >= songs.count, played < songs.count,
                  let next = songs.filter({ $0.playCount == 0 }).randomElement() else { return nil }
            return item(next, "\(played) of \(songs.count) songs on this album played")
        }.shuffled())

        // Anniversaries: added on this day in an earlier year; released a round number of years ago.
        let today = cal.dateComponents([.month, .day], from: now)
        let thisYear = cal.component(.year, from: now)
        pools.append(library.filter { t in
            let c = cal.dateComponents([.year, .month, .day], from: t.dateAdded)
            return c.month == today.month && c.day == today.day && (c.year ?? thisYear) < thisYear
        }.shuffled().map { t in
            let years = thisYear - cal.component(.year, from: t.dateAdded)
            return item(t, "Added \(plural(years, "year")) ago today")
        })
        pools.append(library.filter { t in
            guard let year = t.year, year < thisYear else { return false }
            return (thisYear - year) % 10 == 0
        }.shuffled().prefix(20).map { t in item(t, "Released \(thisYear - (t.year ?? thisYear)) years ago, in \(t.year ?? thisYear)") })

        // Genres your favorites come from.
        var favoriteGenres: [String: Int] = [:]
        for t in library where t.isFavorite && !t.genre.isEmpty { favoriteGenres[t.genre, default: 0] += 1 }
        if let (genre, count) = favoriteGenres.filter({ $0.value >= 3 }).randomElement() {
            pools.append(library.filter { $0.genre == genre && !$0.isFavorite && $0.playCount <= 2 }.shuffled().prefix(6)
                .map { item($0, "\(genre) — the genre of \(count) of your favorites") })
        }

        // Online: Apple Music's top songs for your top artists, when they're in your library.
        pools.append(onlineFacts.compactMap { id, tag in byId[id].map { item($0, tag) } }.shuffled())

        pools = pools.filter { !$0.isEmpty }.shuffled()

        // Round-robin across the reasons, one song per album, for a varied grid.
        var results: [RecommendedTrackItem] = []
        var seenAlbums = Set<String>()
        var seenTracks = Set<UUID>()
        while results.count < 12 && !pools.isEmpty {
            for i in pools.indices.reversed() {
                guard results.count < 12 else { break }
                while let next = pools[i].first {
                    pools[i].removeFirst()
                    if seenTracks.insert(next.track.id).inserted && seenAlbums.insert(state.albumKey(for: next.track)).inserted {
                        results.append(next)
                        break
                    }
                }
                if pools[i].isEmpty { pools.remove(at: i) }
            }
        }
        // Small libraries: fill up with songs from albums not shown yet, labelled plainly.
        if results.count < 12 {
            for track in library.shuffled() where results.count < 12 && seenAlbums.insert(state.albumKey(for: track)).inserted {
                let tag = track.playCount > 0 ? "Played \(plural(track.playCount, "time"))" : "Added \(Fmt.relative(track.dateAdded))"
                results.append(item(track, tag))
            }
        }
        recommendedItems = results
    }

    /// Track id → "#2 of Kanye West's top songs on Apple Music", for songs in the library that are
    /// among Apple Music's top songs for the artists you play most.
    private func loadOnlineFacts() async -> [UUID: String] {
        var artistPlays: [String: Int] = [:]
        for t in state.libraryTracks { artistPlays[state.displayArtist(t.artist), default: 0] += t.playCount }
        let artists = artistPlays.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        var facts: [UUID: String] = [:]
        for artist in artists {
            guard let top = await AppleMusicCatalog.shared.artist(named: artist)?.topSongs, !top.isEmpty else { continue }
            let songs = state.libraryTracks.filter { state.displayArtist($0.artist) == artist }
            for (rank, title) in top.prefix(15).enumerated() {
                let wanted = AnimatedArtworkService.normalize(title).lowercased()
                if let match = songs.first(where: { AnimatedArtworkService.normalize($0.title).lowercased() == wanted }) {
                    facts[match.id] = "#\(rank + 1) of \(artist)'s top songs on Apple Music"
                }
            }
        }
        return facts
    }
}

struct RecommendedTrackItem: Identifiable {
    var id: UUID { track.id }
    let track: LocalTrack
    let badgeTag: String?
}

/// Square artwork card for a single song.
struct TrackCard: View {
    let track: LocalTrack
    let theme: ThemeColor
    var badge: String? = nil
    let onPlay: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkTile(track: track, theme: theme, pixelSize: 400, cornerRadius: 10, onPlay: onPlay)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.accent.opacity(0.13), in: Capsule())
                        .padding(.top, 3)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onTapGesture(perform: onOpen)
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
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: (gradientColors.first ?? .clear).opacity(0.35), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card(theme, radius: 14)
    }
}

// MARK: - Page zoom

/// ⌘+ / ⌘- zoom for the page and the full screen player (the sidebar and player bar stay as they are).
enum ContentZoom {
    static let key = "contentZoom"
    static let range: ClosedRange<Double> = 0.6...2.0
    /// Small 5% steps near normal size, larger ones further out.
    private static let steps: [Double] = [0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.3, 1.4, 1.5, 1.75, 2.0]

    static var current: Double { UserDefaults.standard.object(forKey: key) as? Double ?? 1 }

    static func zoomIn() { set(steps.first { $0 > current + 0.001 } ?? range.upperBound) }
    static func zoomOut() { set(steps.last { $0 < current - 0.001 } ?? range.lowerBound) }
    static func reset() { set(1) }

    private static func set(_ value: Double) {
        UserDefaults.standard.set(min(max(value, range.lowerBound), range.upperBound), forKey: key)
    }
}

private struct ContentZoomModifier: ViewModifier {
    @AppStorage(ContentZoom.key) private var zoom = 1.0

    func body(content: Content) -> some View {
        // Lays the content out at size / zoom and scales it back up, so it reflows like a browser zoom.
        GeometryReader { geo in
            content
                .frame(width: geo.size.width / zoom, height: geo.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .animation(.easeOut(duration: 0.18), value: zoom)
    }
}

extension View {
    func contentZoom() -> some View { modifier(ContentZoomModifier()) }
}
