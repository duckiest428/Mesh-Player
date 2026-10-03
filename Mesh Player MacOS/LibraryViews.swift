import AVFoundation
import AVKit
import Combine
import CoreAudio
import SwiftUI

internal import UniformTypeIdentifiers

// MARK: - SongTableView.swift
//
//  SongTableView.swift
//  macOS Music Player
//
//  Songs / playlists / genre drill-downs. Backed by SwiftUI `Table` (NSTableView), which only
//  materialises visible rows, so libraries with tens of thousands of songs scroll smoothly.
//  This view observes the app state only; per-row "now playing" indicators observe the engine
//  individually so playback changes don't rebuild the table.
//

struct SongTableView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTracks: [LocalTrack] = []
    @State private var columnCustomization = TableColumnCustomization<LocalTrack>()
    @State private var editingPlaylist: Playlist?
    @State private var tableIdentity = TableIdentity()
    /// ⌘+ / ⌘- zoom. The table itself is never scaled (AppKit tables re-measure their rows
    /// endlessly when scaled); its text, icons and row height grow instead.
    @AppStorage(ContentZoom.key) private var zoom = 1.0

    /// Tracks what the table last showed. NSTableView measures every *inserted* row, which made
    /// large diffs (leaving a playlist, clearing a search, importing) freeze the app for seconds.
    /// Anything other than rows disappearing gets a fresh table (a cheap reload) instead.
    final class TableIdentity {
        var order: [UUID] = []
        var context = ""
        var token = 0
        /// Set just before a drag-reorder so moving a few rows animates instead of reloading.
        var acceptReorder = false
    }

    private func tableToken(for tracks: [LocalTrack], context: String) -> Int {
        let newOrder = tracks.map(\.id)
        let reordered = tableIdentity.acceptReorder && newOrder.count == tableIdentity.order.count && Set(newOrder) == Set(tableIdentity.order)
        if context != tableIdentity.context || (!reordered && !Self.isSubsequence(newOrder, of: tableIdentity.order)) {
            tableIdentity.token &+= 1
        }
        if newOrder != tableIdentity.order { tableIdentity.acceptReorder = false }
        tableIdentity.order = newOrder
        tableIdentity.context = context
        return tableIdentity.token
    }

    private static func isSubsequence(_ small: [UUID], of big: [UUID]) -> Bool {
        guard small.count <= big.count else { return false }
        var i = 0
        for id in big where i < small.count && small[i] == id { i += 1 }
        return i == small.count
    }

    var body: some View {
        let theme = state.theme
        let tracks = state.filteredTracks
        let context = "\(state.selectedTab ?? "")|\(state.activeFilterType ?? "")|\(state.activeFilterValue ?? "")"

        VStack(spacing: 0) {
            header(theme: theme, tracks: tracks)
                .contentZoom()

            if tracks.isEmpty {
                emptyState(theme)
                    .contentZoom()
            } else {
                table(theme: theme, tracks: tracks)
                    .id(tableToken(for: tracks, context: context))
            }
        }
        .background(theme.background)
        .onAppear(perform: applyColumnPreferences)
        .onChange(of: columnPreferenceSignature) { _, _ in applyColumnPreferences() }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    state.createNewPlaylist(name: newPlaylistName, tracks: pendingPlaylistTracks)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new playlist.")
        }
        .sheet(item: $editingPlaylist) { playlist in
            PlaylistEditorSheet(state: state, playlist: playlist)
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(theme: ThemeColor, tracks: [LocalTrack]) -> some View {
        let totalDuration = tracks.reduce(0) { $0 + $1.duration }
        let summary = "\(Fmt.songs(tracks.count)) · \(Fmt.longDuration(totalDuration))"

        if let playlist = state.currentPlaylist, state.activeFilterType == nil {
            HStack(alignment: .bottom, spacing: 24) {
                PlaylistCover(playlist: playlist, tracks: tracks, state: state, theme: theme)
                    .frame(width: 180, height: 180)
                    .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 16, y: 8)
                    .onTapGesture(count: 2) { if !playlist.isAppleMusicFavorites { editingPlaylist = playlist } }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: playlistKind(playlist), color: theme.accent)
                    Text(playlist.name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    if !playlist.description.isEmpty {
                        Text(playlist.description)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(3)
                    }
                    HStack(spacing: 6) {
                        Text(summary)
                        if playlist.hidesSongsFromLibrary {
                            Label("Hidden from Library", systemImage: "eye.slash")
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(theme.hover, in: Capsule())
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    HStack(spacing: 8) {
                        playButtons(theme: theme, tracks: tracks)
                        playlistMenu(playlist, tracks: tracks, theme: theme)
                        Spacer(minLength: 0)
                        sortMenu(playlist, theme: theme)
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 20)
            .background(alignment: .top) {
                if let first = tracks.first {
                    ArtworkBackdrop(track: first, theme: theme)
                }
            }
        } else {
            PageHeader(title: headerTitle, subtitle: summary, theme: theme) {
                playButtons(theme: theme, tracks: tracks)
            }
        }
    }

    private func playlistKind(_ playlist: Playlist) -> String {
        if playlist.isSmart { return "Smart Playlist" }
        if playlist.isImported { return "Playlist · Apple Music" }
        return "Playlist"
    }

    private func playlistMenu(_ playlist: Playlist, tracks: [LocalTrack], theme: ThemeColor) -> some View {
        Menu {
            Button("Play Next") { state.playNext(tracks, engine: engine) }
            Button("Play Later") { state.playLater(tracks, engine: engine) }
            Divider()
            if !playlist.isAppleMusicFavorites {
                Button(playlist.isSmart ? "Edit Rules…" : "Edit Details…") { editingPlaylist = playlist }
                Toggle("Hide Songs from Library", isOn: Binding(
                    get: { playlist.hidesSongsFromLibrary },
                    set: { value in state.updatePlaylist(playlist.id) { $0.excludeFromLibrary = value } }
                ))
            }
            Button("Duplicate") { state.duplicatePlaylist(playlist.id) }
            Divider()
            Button("Export to Apple Music…") { AppleMusicSync.shared.presentExport(playlists: [playlist.id], state: state) }
            Button("Export as M3U…") { exportM3U(playlist) }
            if !playlist.isAppleMusicFavorites {
                Divider()
                Button("Delete Playlist…", role: .destructive) { state.confirmDeletion(of: playlist) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.hover, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func sortMenu(_ playlist: Playlist, theme: ThemeColor) -> some View {
        let sort = state.playlistSort(for: playlist.id)
        let options: [(String, String)] = [("playlistOrder", "Playlist Order"), ("title", "Title"), ("artist", "Artist"), ("album", "Album"), ("dateAdded", "Date Added"), ("playCount", "Plays"), ("duration", "Time")]
        return Menu {
            Picker("Sort By", selection: Binding(
                get: { sort.criteria },
                set: { state.playlistSorts[playlist.id] = .init(criteria: $0, ascending: $0 == "playlistOrder" || !["dateAdded", "playCount"].contains($0)) }
            )) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.inline)
            if sort.criteria != "playlistOrder" {
                Divider()
                Picker("Order", selection: Binding(
                    get: { sort.ascending },
                    set: { state.playlistSorts[playlist.id] = .init(criteria: sort.criteria, ascending: $0) }
                )) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(options.first(where: { $0.0 == sort.criteria })?.1 ?? "Sort", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort this playlist")
    }

    private func exportM3U(_ playlist: Playlist) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LibraryFiles.sanitize(playlist.name, fallback: "Playlist") + ".m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { try? state.exportPlaylistM3U(playlist, to: url) }
        }
    }

    private var headerTitle: String {
        if let type = state.activeFilterType, let value = state.activeFilterValue {
            return type == "genre" ? value : "\(value)"
        }
        if !state.searchKeyword.isEmpty { return "Results for “\(state.searchKeyword)”" }
        return "Songs"
    }

    private func playButtons(theme: ThemeColor, tracks: [LocalTrack]) -> some View {
        HStack(spacing: 8) {
            Button {
                state.play(tracks, shuffled: false, engine: engine)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(PillButtonStyle(kind: .primary, theme: theme))

            Button {
                state.play(tracks, shuffled: true, engine: engine)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(PillButtonStyle(kind: .secondary, theme: theme))
        }
        .disabled(tracks.isEmpty)
    }

    private func emptyState(_ theme: ThemeColor) -> some View {
        let playlist = state.currentPlaylist
        return VStack(spacing: 10) {
            Image(systemName: state.searchKeyword.isEmpty ? (playlist?.isSmart == true ? "gearshape" : "music.note.list") : "magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            Text(state.searchKeyword.isEmpty ? (playlist != nil ? (playlist!.isSmart ? "No songs match these rules" : "This playlist is empty") : "No songs yet") : "No matches")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(state.searchKeyword.isEmpty ? (playlist?.isSmart == true ? "Edit the rules from the ••• menu." : "Drag songs onto a playlist in the sidebar, right-click a song and choose Add to Playlist, or import music.") : "Try a different title, artist, album or genre.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Table

    private var canReorder: Bool {
        guard let playlist = state.currentPlaylist, state.activeFilterType == nil, !playlist.isSmart, !playlist.isAppleMusicFavorites else { return false }
        return state.playlistSort(for: playlist.id).criteria == "playlistOrder" && state.searchKeyword.isEmpty
    }

    private func table(theme: ThemeColor, tracks: [LocalTrack]) -> some View {
        let reorderable = canReorder
        let playlistId = state.currentPlaylist?.id
        return Table(of: LocalTrack.self, selection: $state.selectedTrackIds, sortOrder: sortBinding, columnCustomization: $columnCustomization) {
            TableColumn("Title", value: \.title) { track in
                TitleCell(track: track, engine: engine, theme: theme, zoom: zoom)
            }
            .width(min: 160, ideal: 280)
            .customizationID("title")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .width(min: 90, ideal: 170)
            .customizationID("artist")

            TableColumn("Album", value: \.album) { track in
                Text(track.album).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .width(min: 90, ideal: 190)
            .customizationID("album")

            TableColumn("Genre", value: \.genre) { track in
                Text(track.genre).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .width(min: 60, ideal: 100)
            .customizationID("genre")

            TableColumn("Year", value: \.sortYear) { track in
                Text(track.year.map(String.init) ?? "—").monospacedDigit().foregroundStyle(theme.textSecondary)
            }
            .width(min: 40, ideal: 50, max: 70)
            .customizationID("year")

            TableColumn("Plays", value: \.playCount) { track in
                Text(track.playCount > 0 ? Fmt.count(track.playCount) : "—").monospacedDigit().foregroundStyle(theme.textSecondary)
            }
            .width(min: 40, ideal: 52, max: 80)
            .customizationID("plays")

            TableColumn("Date Added", value: \.dateAdded) { track in
                Text(Fmt.date(track.dateAdded)).monospacedDigit().foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .width(min: 80, ideal: 100, max: 140)
            .customizationID("dateAdded")

            TableColumn("Quality", value: \.format) { track in
                FormatBadge(track: track, theme: theme, zoom: zoom)
            }
            .width(min: 60, ideal: 110, max: 150)
            .customizationID("format")

            TableColumn("♥", value: \.favoriteRank) { track in
                FavoriteCell(track: track, theme: theme, zoom: zoom) { state.toggleFavorite(track: track) }
            }
            .width(28)
            .alignment(.center)
            .customizationID("favorite")

            TableColumn("Time", value: \.duration) { track in
                Text(Fmt.time(track.duration)).monospacedDigit().foregroundStyle(theme.textSecondary)
            }
            .width(min: 44, ideal: 52, max: 70)
            .alignment(.trailing)
            .customizationID("time")
        } rows: {
            ForEach(tracks) { track in
                TableRow(track)
                    .draggable(TrackDrag.payload(for: track.id))
            }
            .dropDestination(for: String.self) { index, items in
                guard reorderable, let playlistId else { return }
                let ids = items.compactMap(TrackDrag.trackId(from:))
                tableIdentity.acceptReorder = true
                state.movePlaylistTracks(playlistId, trackIds: ids, toIndex: index)
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, (30 * zoom).rounded())
        .font(.system(size: 12.5 * zoom))
        .contextMenu(forSelectionType: LocalTrack.ID.self) { ids in
            contextMenu(for: ids, in: tracks)
        } primaryAction: { ids in
            guard let id = ids.first, let track = tracks.first(where: { $0.id == id }) else { return }
            state.play(tracks, startingAt: track, engine: engine)
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>, in tracks: [LocalTrack]) -> some View {
        let targets = tracks.filter { ids.contains($0.id) }
        if let first = targets.first {
            Button("Play") { state.play(tracks, startingAt: first, engine: engine) }
            Button(targets.count > 1 ? "Play \(targets.count) Songs" : "Play Only This") {
                state.play(targets, startingAt: first, engine: engine)
            }
            Button("Play Next") { state.playNext(targets, engine: engine) }
            Button("Play Later") { state.playLater(targets, engine: engine) }
            Divider()
            Menu(targets.count > 1 ? "Add \(targets.count) Songs to Playlist" : "Add to Playlist") {
                Button("New Playlist…") {
                    pendingPlaylistTracks = targets
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                }
                Divider()
                ForEach(state.editablePlaylists) { playlist in
                    Button(playlist.name) { state.addTracksToPlaylist(targets, playlistId: playlist.id) }
                }
            }
            if targets.count == 1 {
                Button(first.isFavorite ? "Remove from Favorites" : "Add to Favorites") { state.toggleFavorite(track: first) }
                Divider()
                Button("Go to Album") { state.showAlbum(of: first) }
                Button("Go to Artist") { state.showArtist(first.artist) }
            }
            Divider()
            if let playlist = state.currentPlaylist, state.activeFilterType == nil, !playlist.isSmart {
                Button(targets.count > 1 ? "Remove \(targets.count) Songs from Playlist" : "Remove from Playlist") {
                    state.removeTracksFromPlaylist(targets.map(\.id), playlistId: playlist.id)
                }
            }
            Button("Show in Finder") {
                let urls = targets.compactMap(\.fileURL)
                if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            }
            Button(targets.count > 1 ? "Remove \(targets.count) Songs from Library…" : "Remove from Library…", role: .destructive) {
                state.confirmRemoval(of: targets)
            }
        }
    }

    // MARK: Sorting & columns

    private var sortBinding: Binding<[KeyPathComparator<LocalTrack>]> {
        Binding(
            get: {
                let sort = state.effectiveSort
                if sort.criteria == "playlistOrder" { return [] }
                return [Self.comparator(for: sort.criteria, ascending: sort.ascending)]
            },
            set: { newValue in
                guard let first = newValue.first else { return }
                let criteria = Self.criteria(for: first.keyPath)
                let ascending = first.order == .forward
                if state.activeFilterType == nil, let playlist = state.currentPlaylist {
                    state.playlistSorts[playlist.id] = .init(criteria: criteria, ascending: ascending)
                } else {
                    state.sortCriteria = criteria
                    state.sortAscending = ascending
                }
            }
        )
    }

    private static func comparator(for criteria: String, ascending: Bool) -> KeyPathComparator<LocalTrack> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch criteria {
        case "title": return KeyPathComparator(\LocalTrack.title, order: order)
        case "artist": return KeyPathComparator(\LocalTrack.artist, order: order)
        case "album": return KeyPathComparator(\LocalTrack.album, order: order)
        case "genre": return KeyPathComparator(\LocalTrack.genre, order: order)
        case "year": return KeyPathComparator(\LocalTrack.sortYear, order: order)
        case "playCount": return KeyPathComparator(\LocalTrack.playCount, order: order)
        case "format": return KeyPathComparator(\LocalTrack.format, order: order)
        case "favourites", "favorites": return KeyPathComparator(\LocalTrack.favoriteRank, order: order)
        case "duration": return KeyPathComparator(\LocalTrack.duration, order: order)
        default: return KeyPathComparator(\LocalTrack.dateAdded, order: order)
        }
    }

    private static func criteria(for keyPath: PartialKeyPath<LocalTrack>) -> String {
        if keyPath == \LocalTrack.title { return "title" }
        if keyPath == \LocalTrack.artist { return "artist" }
        if keyPath == \LocalTrack.album { return "album" }
        if keyPath == \LocalTrack.genre { return "genre" }
        if keyPath == \LocalTrack.sortYear { return "year" }
        if keyPath == \LocalTrack.playCount { return "playCount" }
        if keyPath == \LocalTrack.format { return "format" }
        if keyPath == \LocalTrack.favoriteRank { return "favorites" }
        if keyPath == \LocalTrack.duration { return "duration" }
        return "dateAdded"
    }

    private var columnPreferenceSignature: [Bool] {
        [state.showArtistColumn, state.showAlbumColumn, state.showGenreColumn, state.showYearColumn,
         state.showPlaysColumn, state.showDateAddedColumn, state.showFormatColumn, state.showFavoritesColumn, state.showTimeColumn]
    }

    private func applyColumnPreferences() {
        let pairs: [(String, Bool)] = [
            ("artist", state.showArtistColumn), ("album", state.showAlbumColumn), ("genre", state.showGenreColumn),
            ("year", state.showYearColumn), ("plays", state.showPlaysColumn), ("dateAdded", state.showDateAddedColumn),
            ("format", state.showFormatColumn), ("favorite", state.showFavoritesColumn), ("time", state.showTimeColumn)
        ]
        for (id, visible) in pairs {
            columnCustomization[visibility: id] = visible ? .visible : .hidden
        }
    }
}

/// Drag payload for songs: a prefixed UUID string, so it never collides with ordinary text drops.
nonisolated enum TrackDrag {
    static let prefix = "mesh-track:"
    static func payload(for id: UUID) -> String { prefix + id.uuidString }
    static func trackId(from string: String) -> UUID? {
        guard string.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(string.dropFirst(prefix.count)))
    }
}

/// Title cell: shows the playing indicator. Observes the engine on its own so only visible
/// title cells update when playback changes.
private struct TitleCell: View {
    let track: LocalTrack
    @ObservedObject var engine: AudioEngineManager
    let theme: ThemeColor
    var zoom: Double = 1

    var body: some View {
        let isCurrent = engine.currentTrack?.id == track.id
        HStack(spacing: 8) {
            ZStack {
                if isCurrent {
                    AnimatedEQView(color: theme.accent, isPlaying: engine.isPlaying, height: 11 * zoom)
                }
            }
            .frame(width: 14 * zoom)
            Text(track.title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary)
                .lineLimit(1)
            if track.isExplicit == true {
                ExplicitBadge(size: 10 * zoom, color: theme.textTertiary)
            }
            if track.isAtmos {
                DolbyAtmosBadge(color: theme.textSecondary, scale: 0.85 * zoom, showText: false)
            }
        }
    }
}

private struct FavoriteCell: View {
    let track: LocalTrack
    let theme: ThemeColor
    var zoom: Double = 1
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 11 * zoom, weight: .semibold))
                .foregroundStyle(track.isFavorite ? theme.accent : theme.textTertiary)
                .opacity(track.isFavorite || hovering ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(track.isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}

struct FormatBadge: View {
    let track: LocalTrack
    let theme: ThemeColor
    var zoom: Double = 1

    var body: some View {
        if track.isAtmos {
            DolbyAtmosBadge(color: theme.textSecondary, scale: 0.85 * zoom, showText: true)
        } else if track.format.localizedCaseInsensitiveContains("lossless") {
            HStack(spacing: 3) {
                QualityLogoImage(logo: .lossless, height: 10 * zoom)
                Text(track.format.localizedCaseInsensitiveContains("hi-res") ? "Hi-Res" : "Lossless")
                    .font(.system(size: 10.5 * zoom, weight: .semibold))
            }
            .foregroundStyle(theme.textSecondary)
        } else {
            Text(track.format)
                .font(.system(size: 10.5 * zoom, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
        }
    }
}

/// 2×2 artwork collage built from the first distinct albums in a list.
struct PlaylistMosaic: View {
    let tracks: [LocalTrack]
    let theme: ThemeColor

    var body: some View {
        var seen = Set<String>()
        let covers = tracks.filter { seen.insert($0.artworkKey).inserted }.prefix(4)
        return Group {
            if covers.count >= 4 {
                let items = Array(covers)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ArtworkView(track: items[0], pixelSize: 200, cornerRadius: 0)
                        ArtworkView(track: items[1], pixelSize: 200, cornerRadius: 0)
                    }
                    HStack(spacing: 0) {
                        ArtworkView(track: items[2], pixelSize: 200, cornerRadius: 0)
                        ArtworkView(track: items[3], pixelSize: 200, cornerRadius: 0)
                    }
                }
            } else if let first = covers.first {
                ArtworkView(track: first, pixelSize: 400, cornerRadius: 0)
            } else {
                ArtworkPlaceholder(seed: "playlist", symbol: "music.note.list")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Soft blurred artwork wash used behind album / playlist headers.
struct ArtworkBackdrop: View {
    let track: LocalTrack
    let theme: ThemeColor
    var height: CGFloat = 340

    var body: some View {
        ArtworkView(track: track, pixelSize: 128, cornerRadius: 0, placeholderSymbol: nil)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .blur(radius: 70, opaque: true)
            .opacity(theme.isDark ? 0.45 : 0.35)
            .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            .clipped()
            .allowsHitTesting(false)
    }
}

/// Apple Music's now playing bars. Drawn from a clock rather than a repeating SwiftUI
/// animation: a repeating animation also animates the bars' position, so while a page slid in
/// they bounced around outside their row.
struct AnimatedEQView: View {
    let color: Color
    let isPlaying: Bool
    var height: CGFloat = 12

    private static let bars: [(speed: Double, offset: Double)] = [(5.1, 0.0), (6.7, 1.7), (4.3, 3.1), (5.9, 4.6)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let count = Self.bars.count
                let gap = size.width * 0.12
                let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                for (i, bar) in Self.bars.enumerated() {
                    // Two waves per bar, so the pattern doesn't visibly repeat.
                    let wave = isPlaying ? (sin(t * bar.speed + bar.offset) + sin(t * bar.speed * 0.53 + bar.offset * 2)) / 4 + 0.5 : 0
                    let level = isPlaying ? 0.25 + 0.75 * wave : [0.45, 0.8, 0.6, 0.35][i]
                    let h = max(width, size.height * level)
                    let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - h, width: width, height: h)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
                }
            }
        }
        .frame(width: height * 1.1, height: height)
        .accessibilityHidden(true)
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
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
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
    let engine: AudioEngineManager
    /// Album key (the name, plus the album artist when two albums share a name).
    var albumName: String
    private var title: String { AppStateManager.albumName(fromKey: albumName) }

    @State private var fetchedCopyright: String? = nil
    @State private var copyrightLookupDone = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var pendingTracks: [LocalTrack] = []
    @State private var showArtworkViewer = false
    @State private var catalog: CatalogAlbumInfo?
    @State private var showFullNotes = false
    @State private var pageWidth: CGFloat = 1000
    /// Also list the album's songs that aren't in the library (from Apple Music), greyed out.
    @AppStorage("showCompleteAlbums") private var showCompleteAlbum = false
    @ObservedObject private var downloader = AmdlDownloader.shared
    @Environment(\.pageTopInset) private var topInset

    private var albumTracks: [LocalTrack] { state.albumTracks(named: albumName) }

    /// A row in the track list: a song you have, or one only on Apple Music.
    private enum Row: Identifiable {
        case local(LocalTrack, CatalogTrackInfo?)
        case missing(CatalogTrackInfo)
        var id: String {
            switch self {
            case .local(let track, _): return track.id.uuidString
            case .missing(let item): return "am-" + item.id
            }
        }
        var disc: Int {
            switch self {
            case .local(let track, _): return track.discNumber
            case .missing(let item): return item.discNumber ?? 1
            }
        }
    }

    /// Pairs local songs with the album's Apple Music tracks: by title first (ignoring case,
    /// accents and "(feat. …)" parts), then by disc and track number.
    private func catalogShelf(_ title: String, _ items: [CatalogShelfItem], _ theme: ThemeColor, seeAll: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // SectionHeader brings 28pt of its own; the cards start at 36.
            SectionHeader(title: title, theme: theme, action: seeAll)
                .padding(.horizontal, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        CatalogShelfCell(item: item, theme: theme, inLibrary: localAlbumKey(for: item) != nil) {
                            open(item)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 12)
            }
        }
        .padding(.top, 30)
    }

    /// The library album matching a shelf album, by title and artist.
    private func localAlbumKey(for item: CatalogShelfItem) -> String? {
        guard item.kind == .album else { return nil }
        let wanted = AnimatedArtworkService.normalize(item.name.replacingOccurrences(of: " - Single", with: "").replacingOccurrences(of: " - EP", with: ""))
        return state.albumsList.first {
            AnimatedArtworkService.normalize($0.name).caseInsensitiveCompare(wanted) == .orderedSame
                && AnimatedArtworkService.artistsMatch($0.artist, item.subtitle)
        }?.key
    }

    /// Albums you have open in the library, others in Get Music; playlists open in Apple Music.
    private func open(_ item: CatalogShelfItem) {
        switch item.kind {
        case .album:
            if let key = localAlbumKey(for: item) {
                state.showAlbum(key)
            } else {
                state.getMusicQuery = "\(item.name) \(item.subtitle)"
                state.selectedTab = "getMusic"
            }
        case .playlist:
            if let link = item.url, let url = URL(string: link) { NSWorkspace.shared.open(url) }
        }
    }

    static func matchCatalog(_ tracks: [LocalTrack], _ catalog: [CatalogTrackInfo]) -> [UUID: CatalogTrackInfo] {
        func key(_ title: String) -> String {
            title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        }
        var result: [UUID: CatalogTrackInfo] = [:]
        var used = Set<String>()
        for track in tracks {
            let exact = track.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if let hit = catalog.first(where: { !used.contains($0.id) && $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == exact })
                ?? catalog.first(where: { !used.contains($0.id) && key($0.name) == key(track.title) && !key(track.title).isEmpty }) {
                result[track.id] = hit
                used.insert(hit.id)
            }
        }
        for track in tracks where result[track.id] == nil && track.trackNumber > 0 {
            if let hit = catalog.first(where: { !used.contains($0.id) && $0.trackNumber == track.trackNumber && ($0.discNumber ?? 1) == track.discNumber }) {
                result[track.id] = hit
                used.insert(hit.id)
            }
        }
        return result
    }

    /// Album / EP / Single from the release itself when it isn't known from Apple Music: the
    /// highest track number counts (owning 4 songs of a 20-track album doesn't make it an EP).
    static func releaseKind(title: String, tracks: [LocalTrack]) -> String {
        if title.hasSuffix(" - Single") { return "Single" }
        if title.hasSuffix(" - EP") { return "EP" }
        let count = max(tracks.count, tracks.map(\.trackNumber).max() ?? 0)
        let total = tracks.reduce(0) { $0 + $1.duration }
        if count <= 3 && total < 30 * 60 && tracks.allSatisfy({ $0.duration < 10 * 60 }) { return "Single" }
        if count <= 6 && total < 30 * 60 { return "EP" }
        return "Album"
    }

    private func catalogItem(for track: CatalogTrackInfo) -> CatalogItem? {
        let link = track.url.flatMap(URL.init(string:))
            ?? catalog?.url.flatMap { URL(string: $0 + "?i=" + track.id) }
        guard let link else { return nil }
        return CatalogItem(id: "song-\(track.id)", kind: .song, title: track.name, artist: track.artist, album: title,
                           artworkURL: catalog?.artworkURL(300), appleMusicURL: link, year: catalog?.year,
                           trackCount: nil, isExplicit: track.isExplicit)
    }

    private func job(for track: CatalogTrackInfo) -> AmdlDownloader.Job? {
        downloader.jobs.first { $0.item.id == "song-\(track.id)" }
    }

    private func download(_ missing: [CatalogTrackInfo]) {
        for track in missing {
            if let item = catalogItem(for: track) { downloader.enqueue(item, state: state) }
        }
    }

    var body: some View {
        let theme = state.theme
        let tracks = albumTracks
        let rep = tracks.first
        let albumArtist = rep?.albumArtist ?? rep?.artist ?? "Unknown Artist"
        let totalSeconds = tracks.reduce(0) { $0 + $1.duration }
        let displayName = title.replacingOccurrences(of: " - Single", with: "").replacingOccurrences(of: " - EP", with: "")
        let kind = catalog?.kind ?? Self.releaseKind(title: title, tracks: tracks)
        let catalogTracks = catalog?.tracks ?? []
        let matches = Self.matchCatalog(tracks, catalogTracks)
        let matchedIds = Set(matches.values.map(\.id))
        let missing = catalogTracks.filter { !matchedIds.contains($0.id) }
        let rows: [Row] = {
            guard showCompleteAlbum, !missing.isEmpty else { return tracks.map { .local($0, matches[$0.id]) } }
            var byCatalogId: [String: LocalTrack] = [:]
            for (id, item) in matches { if let t = tracks.first(where: { $0.id == id }) { byCatalogId[item.id] = t } }
            let ordered: [Row] = catalogTracks.map { item in byCatalogId[item.id].map { .local($0, item) } ?? .missing(item) }
            return ordered + tracks.filter { matches[$0.id] == nil }.map { .local($0, nil) }
        }()
        let isMultiDisc = (rows.map(\.disc).max() ?? 1) > 1

        // The header grows with the window, like Apple Music's album pages.
        let art = min(max(pageWidth * 0.27, 260), 380)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .bottom, spacing: 34) {
                    ZStack {
                        if let rep {
                            ArtworkView(track: rep, pixelSize: 800, cornerRadius: 14)
                            if state.animatedArtworkEnabled {
                                AnimatedArtworkView(track: rep, cornerRadius: 14)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(width: art, height: art)
                    .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.18), radius: 22, y: 10)
                    .contentShape(Rectangle())
                    .onTapGesture { if rep != nil { showArtworkViewer = true } }
                    .help("View Artwork")

                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: kind, color: theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(displayName)
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(2)
                            if catalog?.isExplicit == true {
                                ExplicitBadge(size: 22, color: theme.textSecondary)
                                    .help("Explicit")
                            }
                        }
                        LinkText(text: albumArtist, font: .system(size: 24, weight: .semibold), color: theme.accent, hoverColor: theme.accent) {
                            state.showArtist(rep?.artist ?? albumArtist)
                        }
                        HStack(spacing: 6) {
                            let pieces = [rep?.genre, rep?.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty && $0 != "Unknown Genre" }
                            Text((pieces + [Fmt.songs(tracks.count), Fmt.longDuration(totalSeconds)]).joined(separator: " · "))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                            if let rep {
                                AudioQualityTagsView(track: rep, theme: theme, size: 1.1)
                            }
                        }
                        if let notes = catalog?.notesShort ?? catalog?.notesStandard, !notes.isEmpty {
                            // Apple Music's editor's notes for this album.
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(notes)
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: 600, alignment: .leading)
                                if catalog?.notesStandard != nil {
                                    Button("MORE") { showFullNotes = true }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(theme.accent)
                                        .popover(isPresented: $showFullNotes, arrowEdge: .bottom) {
                                            ScrollView {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text("Editor's Notes").font(.system(size: 14, weight: .bold))
                                                    Text(catalog?.notesStandard ?? notes)
                                                        .font(.system(size: 13))
                                                        .textSelection(.enabled)
                                                    Text("From Apple Music").font(.system(size: 11)).foregroundStyle(.secondary)
                                                }
                                                .padding(18)
                                            }
                                            .frame(width: 420)
                                            .frame(maxHeight: 420)
                                        }
                                }
                            }
                            .padding(.top, 2)
                            .transition(.opacity)
                        }
                        HStack(spacing: 10) {
                            Button {
                                state.play(tracks, shuffled: false, engine: engine)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, large: true))

                            Button {
                                state.play(tracks, shuffled: true, engine: engine)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(PillButtonStyle(kind: .secondary, theme: theme, large: true))

                            Menu {
                                Button("Play Next") { state.playNext(tracks, engine: engine) }
                                Button("Play Later") { state.playLater(tracks, engine: engine) }
                                Divider()
                                Button("Add Album to New Playlist…") {
                                    pendingTracks = tracks
                                    newPlaylistName = displayName
                                    showNewPlaylistAlert = true
                                }
                                Menu("Add Album to Playlist") {
                                    ForEach(state.editablePlaylists) { playlist in
                                        Button(playlist.name) { state.addTracksToPlaylist(tracks, playlistId: playlist.id) }
                                    }
                                }
                                if !missing.isEmpty {
                                    Divider()
                                    Toggle("Show Complete Album", isOn: $showCompleteAlbum)
                                    Button("Get \(missing.count) Missing Song\(missing.count == 1 ? "" : "s")…") { download(missing) }
                                }
                                Divider()
                                Button("Show in Finder") {
                                    let urls = tracks.compactMap(\.fileURL)
                                    if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(theme.hover, in: Circle())
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 36)
                .padding(.top, 36 + topInset)
                .padding(.bottom, 30)
                .background(alignment: .top) {
                    if let rep { ArtworkBackdrop(track: rep, theme: theme, height: art + 180 + topInset) }
                }

                // Tracks
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if isMultiDisc && (index == 0 || rows[index - 1].disc != row.disc) {
                            HStack {
                                Image(systemName: "opticaldisc").font(.system(size: 13))
                                Text("Disc \(row.disc)").font(.system(size: 14, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, index == 0 ? 0 : 18)
                            .padding(.bottom, 6)
                        }
                        switch row {
                        case .missing(let item):
                            MissingTrackRow(item: item, number: item.trackNumber ?? index + 1, showArtist: item.artist != (catalog?.artist ?? albumArtist),
                                            theme: theme, job: job(for: item)) {
                                download([item])
                            }
                        case .local(let track, let match):
                        AlbumTrackRow(
                            track: track,
                            number: track.parsedTrackNumber != 9999 ? track.parsedTrackNumber : (match?.trackNumber ?? index + 1),
                            isExplicit: match?.isExplicit == true,
                            showArtist: track.artist != albumArtist,
                            engine: engine,
                            theme: theme,
                            playlists: state.editablePlaylists,
                            onPlay: { state.play(tracks, startingAt: track, engine: engine) },
                            onPlayNext: { state.playNext([track], engine: engine) },
                            onPlayLater: { state.playLater([track], engine: engine) },
                            onToggleFavorite: { state.toggleFavorite(track: track) },
                            onAddToPlaylist: { state.addTrackToPlaylist(track: track, playlistId: $0) },
                            onNewPlaylist: {
                                pendingTracks = [track]
                                newPlaylistName = ""
                                showNewPlaylistAlert = true
                            },
                            onShowArtist: { state.showArtist(track.artist) }
                        )
                        }
                    }
                }
                .padding(.horizontal, 22)

                if !missing.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showCompleteAlbum.toggle() }
                    } label: {
                        Text(showCompleteAlbum ? "Hide Songs Not in Library" : "Show Complete Album (\(missing.count) more on Apple Music)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 36)
                    .padding(.top, 14)
                }

                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    // Like Apple Music: release date, length, copyright.
                    if let released = catalog?.releaseDateText {
                        Text(released)
                    } else if let date = tracks.map(\.dateAdded).min() {
                        Text("Added \(Fmt.date(date))")
                    }
                    Text("\(Fmt.songs(tracks.count)), \(Int((totalSeconds / 60).rounded())) minute\(Int((totalSeconds / 60).rounded()) == 1 ? "" : "s")")
                    // Reserve the line while looking it up so the artist name never flashes in first.
                    Text(copyrightText(for: tracks) ?? " ")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 36)
                .padding(.top, 20)

                // Apple Music's shelves, as at the bottom of its album pages. Without them (offline,
                // or not on Apple Music), the artist's other albums in your library.
                let related = catalog?.related
                if let moreBy = related?.moreByArtist, !moreBy.isEmpty {
                    catalogShelf("More By \(catalog?.artist ?? albumArtist)", moreBy, theme) {
                        state.showArtist(rep?.artist ?? albumArtist)
                    }
                } else {
                    let others = state.albumsList.filter { $0.artist == albumArtist && $0.key != albumName }
                    if !others.isEmpty {
                        SectionHeader(title: "More by \(albumArtist)", theme: theme) {
                            state.showArtist(rep?.artist ?? albumArtist)
                        }
                        .padding(.top, 36)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(others) { album in
                                    AlbumCell(album: album, theme: theme, subtitle: album.yearRecorded.map(String.init) ?? "Album") {
                                        state.showAlbum(album.key)
                                    } onPlay: {
                                        state.play(state.albumTracks(named: album.key), engine: engine)
                                    }
                                    .frame(width: 190)
                                }
                            }
                            .padding(.horizontal, 36)
                            .padding(.vertical, 12)
                        }
                    }
                }
                if let featured = related?.featuredOn, !featured.isEmpty {
                    catalogShelf("Featured On", featured, theme)
                }
                if let similar = related?.youMightAlsoLike, !similar.isEmpty {
                    catalogShelf("You Might Also Like", similar, theme)
                }
            }
            .padding(.bottom, 40)
        }
        .background(theme.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .task(id: albumName) { await resolveCopyright() }
        .task(id: albumName) {
            guard let rep = albumTracks.first else { return }
            let artist = rep.albumArtist ?? rep.artist
            catalog = AppleMusicCatalog.shared.cachedAlbum(named: title, artist: artist)
            let fetched = await AppleMusicCatalog.shared.album(named: title, artist: artist)
            if !Task.isCancelled, fetched != catalog { withAnimation(.easeOut(duration: 0.2)) { catalog = fetched } }
            // Songs whose files carry no explicit tag get it from Apple Music.
            if let items = fetched?.tracks, !items.isEmpty {
                let matches = Self.matchCatalog(albumTracks, items)
                state.setExplicitFlags(matches.filter { _, item in item.isExplicit }.mapValues { _ in true })
            }
        }
        .sheet(isPresented: $showArtworkViewer) {
            if let rep = albumTracks.first {
                ArtworkViewerSheet(track: rep, title: title, theme: state.theme)
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    state.createNewPlaylist(name: newPlaylistName, tracks: pendingTracks)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new playlist.")
        }
    }

    /// nil while a lookup is still running.
    private func copyrightText(for tracks: [LocalTrack]) -> String? {
        if let explicit = tracks.first(where: { !($0.copyright ?? "").isEmpty })?.copyright { return explicit }
        if let fetched = fetchedCopyright, !fetched.isEmpty { return fetched }
        guard copyrightLookupDone else { return nil }
        let rep = tracks.first
        let yearStr = rep?.year.map(String.init) ?? ""
        return "℗ \(yearStr) \(rep?.albumArtist ?? rep?.artist ?? "")".trimmingCharacters(in: .whitespaces)
    }

    /// Copyright comes from the file's own tags first (instant), then the iTunes catalog.
    /// Whatever is found is saved on the album's songs, so the next visit needs no lookup.
    private func resolveCopyright() async {
        let tracks = albumTracks
        guard let rep = tracks.first, tracks.allSatisfy({ ($0.copyright ?? "").isEmpty }) else {
            copyrightLookupDone = true
            return
        }
        let album = albumName
        if let found = await CopyrightResolver.shared.copyright(for: rep, in: tracks), !Task.isCancelled {
            fetchedCopyright = found
            state.setCopyright(found, forAlbum: album)
        }
        copyrightLookupDone = true
    }
}

/// A song from the album that isn't in the library, with a button to get it through am-dl.
/// An album or playlist on an Apple Music shelf at the bottom of an album page.
private struct CatalogShelfCell: View {
    let item: CatalogShelfItem
    let theme: ThemeColor
    let inLibrary: Bool
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: item.artworkURL(400)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkPlaceholder(seed: item.name, symbol: item.kind == .playlist ? "music.note.list" : "music.note")
            }
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.hairline, lineWidth: 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                if item.kind == .album && !inLibrary && hovering {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, theme.accent)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.1), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name.replacingOccurrences(of: " - Single", with: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    if item.isExplicit {
                        ExplicitBadge(size: 10, color: theme.textTertiary)
                    }
                }
                Text(item.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 180, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .hoverLift(1.02)
        .help(item.kind == .playlist ? "Open in Apple Music" : (inLibrary ? "Open album" : "Not in your library — opens Get Music"))
    }
}

private struct MissingTrackRow: View {
    let item: CatalogTrackInfo
    let number: Int
    let showArtist: Bool
    let theme: ThemeColor
    let job: AmdlDownloader.Job?
    let onGet: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Text("\(number)")
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.textTertiary.opacity(0.7))
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                    if item.isExplicit {
                        ExplicitBadge(size: 11, color: theme.textTertiary.opacity(0.7))
                    }
                }
                if showArtist {
                    Text(item.artist).font(.system(size: 13)).foregroundStyle(theme.textTertiary.opacity(0.8)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let job {
                JobBadge(job: job, theme: theme)
                    .frame(width: 26, height: 26)
                    .help(job.isFinished ? "" : "Downloading with am-dl")
            } else {
                Button(action: onGet) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(hovering ? theme.accent : theme.textSecondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Get this song with am-dl")
            }
            Text(Fmt.time(item.duration))
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 50, alignment: .trailing)
            Color.clear.frame(width: 26)
        }
        .padding(.horizontal, 12)
        .frame(height: showArtist ? 58 : 50)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? theme.hover.opacity(0.5) : .clear))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 56)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("Not in your library")
    }
}

private struct AlbumTrackRow: View {
    let track: LocalTrack
    let number: Int
    var isExplicit = false
    let showArtist: Bool
    @ObservedObject var engine: AudioEngineManager
    let theme: ThemeColor
    let playlists: [Playlist]
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void
    let onToggleFavorite: () -> Void
    let onAddToPlaylist: (UUID) -> Void
    let onNewPlaylist: () -> Void
    let onShowArtist: () -> Void

    @State private var hovering = false

    var body: some View {
        let isCurrent = engine.currentTrack?.id == track.id
        let ink = theme.accent.contrastingInk

        HStack(spacing: 16) {
            ZStack {
                if hovering {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else if isCurrent {
                    AnimatedEQView(color: ink, isPlaying: engine.isPlaying, height: 14)
                } else {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(width: 28, alignment: .trailing)

            // The playing song's row is filled with the accent colour and its text turns white,
            // like Apple Music.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? ink : theme.textPrimary)
                        .lineLimit(1)
                    if isExplicit || track.isExplicit == true {
                        ExplicitBadge(size: 11, color: isCurrent ? ink.opacity(0.75) : theme.textTertiary)
                    }
                    if track.isAtmos {
                        DolbyAtmosBadge(color: isCurrent ? ink.opacity(0.85) : theme.textSecondary, scale: 1, showText: false)
                    }
                }
                if showArtist {
                    LinkText(text: track.artist, font: .system(size: 13), color: isCurrent ? ink.opacity(0.8) : theme.textSecondary, hoverColor: isCurrent ? ink : theme.accent, action: onShowArtist)
                }
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrent ? ink : (track.isFavorite ? theme.accent : theme.textSecondary))
            }
            .buttonStyle(.plain)
            .opacity(track.isFavorite || hovering ? 1 : 0)

            Text(Fmt.time(track.duration))
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(isCurrent ? ink.opacity(0.85) : theme.textSecondary)
                .frame(width: 50, alignment: .trailing)

            Menu {
                Button("Play", action: onPlay)
                Button("Play Next", action: onPlayNext)
                Button("Play Later", action: onPlayLater)
                Menu("Add to Playlist") {
                    Button("New Playlist…", action: onNewPlaylist)
                    Divider()
                    ForEach(playlists) { playlist in
                        Button(playlist.name) { onAddToPlaylist(playlist.id) }
                    }
                }
                Button("Go to Artist", action: onShowArtist)
                Divider()
                Button("Show in Finder") {
                    if let url = track.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isCurrent ? ink : theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: showArtist ? 58 : 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? theme.accent : (hovering ? theme.hover : .clear))
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 56).opacity(hovering || isCurrent ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Play", action: onPlay)
            Button("Play Next", action: onPlayNext)
            Button("Play Later", action: onPlayLater)
            Divider()
            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
            Menu("Add to Playlist") {
                Button("New Playlist…", action: onNewPlaylist)
                Divider()
                ForEach(playlists) { playlist in
                    Button(playlist.name) { onAddToPlaylist(playlist.id) }
                }
            }
            Divider()
            Button("Show in Finder") {
                if let url = track.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
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

        for size in sizes {
            if currentX + size.width > width {
                currentX = 0
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            maxRowHeight = max(maxRowHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(width: width, height: currentY + maxRowHeight)
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

struct SidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var importer = LibraryImporter.shared
    @Binding var showSettings: Bool
    let engine: AudioEngineManager

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var renamingPlaylist: Playlist?
    @State private var renameText = ""
    @State private var editingPlaylist: Playlist?
    @State private var newSmartPlaylist: Playlist?
    @State private var dropTarget: UUID?

    var body: some View {
        let theme = state.theme

        List(selection: $state.selectedTab) {
            Section("Library") {
                row("Home", icon: "house.fill", tag: "home")
                row("Songs", icon: "music.note", tag: "songs")
                row("Albums", icon: "square.stack.fill", tag: "albums")
                row("Artists", icon: "music.mic", tag: "artists")
                row("Genres", icon: "guitars.fill", tag: "genres")
                row("Recently Added", icon: "clock.fill", tag: "recently-added")
            }

            Section("Discover") {
                row("Get Music", icon: "arrow.down.circle.fill", tag: "getMusic")
                row("Mesh Replay", icon: "sparkles", tag: "meshReplay")
                row("Statistics", icon: "chart.bar.fill", tag: "statistics")
            }

            Section {
                row("All Playlists", icon: "square.grid.2x2.fill", tag: "allPlaylists")
                ForEach(state.playlists) { playlist in
                    playlistRow(playlist, theme: theme)
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Menu {
                        Button("New Playlist…") {
                            newPlaylistName = ""
                            showNewPlaylistAlert = true
                        }
                        Button("New Smart Playlist…") {
                            newSmartPlaylist = state.createSmartPlaylist(name: "Smart Playlist", rules: SmartPlaylistRules())
                        }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New Playlist")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.sidebarBackground.opacity(0.55))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer(theme)
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    let playlist = state.createNewPlaylist(name: newPlaylistName, tracks: [])
                    state.selectedTab = "playlist-\(playlist.id.uuidString)"
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: Binding(get: { renamingPlaylist != nil }, set: { if !$0 { renamingPlaylist = nil } })) {
            TextField("Playlist Name", text: $renameText)
            Button("Rename") {
                if let playlist = renamingPlaylist, !renameText.isEmpty {
                    state.updatePlaylist(playlist.id) { $0.name = renameText }
                }
                renamingPlaylist = nil
            }
            Button("Cancel", role: .cancel) { renamingPlaylist = nil }
        }
        .sheet(item: $editingPlaylist) { playlist in
            PlaylistEditorSheet(state: state, playlist: playlist)
        }
        .sheet(item: $newSmartPlaylist) { playlist in
            PlaylistEditorSheet(state: state, playlist: playlist, isNew: true)
        }
    }

    private func row(_ title: String, icon: String, tag: String) -> some View {
        Label(title, systemImage: icon).tag(tag)
    }

    private func playlistIcon(_ playlist: Playlist) -> String {
        if playlist.isAppleMusicFavorites { return "heart.fill" }
        if playlist.isSmart { return "gearshape" }
        return "music.note.list"
    }

    private func playlistRow(_ playlist: Playlist, theme: ThemeColor) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(playlist.name).lineLimit(1)
                if playlist.hidesSongsFromLibrary {
                    Spacer(minLength: 2)
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .help("Songs from this playlist are hidden from your library")
                }
            }
        } icon: {
            Image(systemName: playlistIcon(playlist))
        }
        .tag("playlist-\(playlist.id.uuidString)")
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(dropTarget == playlist.id ? theme.accent.opacity(0.25) : .clear)
                .padding(.horizontal, 10)
        )
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(TrackDrag.trackId(from:))
            let songs = ids.compactMap { state.track(withId: $0) }
            guard !songs.isEmpty, !playlist.isSmart else { return false }
            state.addTracksToPlaylist(songs, playlistId: playlist.id)
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = playlist.id } else if dropTarget == playlist.id { dropTarget = nil }
        }
        .contextMenu {
            let songs = state.resolvedTracks(of: playlist)
            Button("Play") { state.play(songs, shuffled: false, engine: engine) }
            Button("Shuffle") { state.play(songs, shuffled: true, engine: engine) }
            Button("Play Next") { state.playNext(songs, engine: engine) }
            Button("Play Later") { state.playLater(songs, engine: engine) }
            Divider()
            if !playlist.isAppleMusicFavorites {
                Button(playlist.isSmart ? "Edit Rules…" : "Edit Details…") { editingPlaylist = playlist }
                Button("Rename…") {
                    renameText = playlist.name
                    renamingPlaylist = playlist
                }
                if !playlist.isSmart {
                    Toggle("Hide Songs from Library", isOn: Binding(
                        get: { playlist.hidesSongsFromLibrary },
                        set: { value in state.updatePlaylist(playlist.id) { $0.excludeFromLibrary = value } }
                    ))
                }
            }
            Button("Duplicate") { state.duplicatePlaylist(playlist.id) }
            Button("Export to Apple Music…") { AppleMusicSync.shared.presentExport(playlists: [playlist.id], state: state) }
            if !playlist.isAppleMusicFavorites {
                Divider()
                Button("Delete Playlist…", role: .destructive) { state.confirmDeletion(of: playlist) }
            }
        }
    }

    private func footer(_ theme: ThemeColor) -> some View {
        VStack(spacing: 8) {
            ImportStatusCard(importer: importer, theme: theme)
            DownloadStatusCard(theme: theme)

            HStack(spacing: 6) {
                Menu {
                    Button {
                        state.showImportOptions = true
                    } label: {
                        Label("Import Apple Music Library…", systemImage: "music.note")
                    }
                    Button {
                        importer.chooseFolderAndImport(into: state)
                    } label: {
                        Label("Import Folder or Files…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        state.selectedTab = "getMusic"
                    } label: {
                        Label("Get Music with am-dl", systemImage: "arrow.down.circle")
                    }
                    Divider()
                    Button {
                        AppleMusicSync.shared.presentExport(playlists: nil, state: state)
                    } label: {
                        Label("Sync Changes to Apple Music…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        state.showSyncWindow = true
                    } label: {
                        Label("Sync iPhone…", systemImage: "iphone")
                    }
                    Divider()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([LibraryManager.shared.autoAddDirectory])
                    } label: {
                        Label("Show “Automatically Add” Folder", systemImage: "tray.and.arrow.down")
                    }
                } label: {
                    Label("Add Music", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(importer.isRunning)

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle(theme: theme, size: 28))
                .help("Settings")
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.25), value: importer.isRunning)
    }
}

// MARK: - Side panels

struct PanelHeader: View {
    let title: String
    let theme: ThemeColor
    var isFullscreen = false
    var onClose: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isFullscreen ? .white : theme.textPrimary)
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(IconButtonStyle(theme: theme, size: 24))
                .help("Close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - LyricsSidebarView

struct LyricsSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker

    @State private var activeLineId: UUID?
    @ObservedObject private var translator = LyricsTranslator.shared

    var body: some View {
        let theme = state.theme
        VStack(spacing: 0) {
            PanelHeader(title: "Lyrics", theme: theme) {
                withAnimation(.easeInOut(duration: 0.2)) { state.activeRightSidebar = .none }
            }

            if engine.parsedLyrics.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                    Text("No lyrics for this song")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text("Add a .lrc file with the same name next to the audio file to get synced lyrics.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(engine.parsedLyrics) { line in
                                let isActive = line.id == activeLineId
                                Group {
                                    if line.isBreak {
                                        InstrumentalBreakDots(engine: engine, breakStart: line.breakStart, breakEnd: line.breakEnd)
                                            .scaleEffect(0.6, anchor: .leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(line.text)
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(isActive ? theme.textPrimary : theme.textPrimary.opacity(0.28))
                                            if let translation = translator.translations[line.id] {
                                                Text(translation)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(isActive ? theme.textSecondary : theme.textPrimary.opacity(0.18))
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .animation(.easeOut(duration: 0.25), value: isActive)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { engine.seek(to: line.timestamp) }
                                .id(line.id)
                            }
                        }
                        .padding(.vertical, 120)
                        .padding(.horizontal, 18)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .onChange(of: timeTracker.currentTime) { _, newValue in
                        // Only react when the active line changes, not on every time tick.
                        guard let current = engine.parsedLyrics.last(where: { $0.timestamp <= newValue }),
                              current.id != activeLineId else { return }
                        activeLineId = current.id
                        if state.autoScrollLyrics {
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(current.id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(width: 300)
        .background(theme.sidebarBackground)
    }
}

// MARK: - QueueSidebarView

struct QueueSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    var isFullscreen: Bool = false

    private var upcomingTracks: ArraySlice<LocalTrack> {
        guard let currentTrack = engine.currentTrack,
              let currentIndex = state.activeQueue.firstIndex(where: { $0.id == currentTrack.id }) else { return [] }
        return state.activeQueue[(currentIndex + 1)...]
    }

    var body: some View {
        let theme = isFullscreen ? ThemeCatalog.theme(named: "True Black") : state.theme
        let upcoming = upcomingTracks

        VStack(spacing: 0) {
            PanelHeader(title: "Playing Next", theme: theme, isFullscreen: isFullscreen, onClose: isFullscreen ? nil : {
                withAnimation(.easeInOut(duration: 0.2)) { state.activeRightSidebar = .none }
            })

            if let current = engine.currentTrack {
                HStack(spacing: 12) {
                    ArtworkView(track: current, pixelSize: 96, cornerRadius: 6)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Now Playing", color: theme.accent)
                        Text(current.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(current.artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .card(theme, radius: 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            HStack {
                Text(upcoming.isEmpty ? "Up Next" : "Up Next · \(upcoming.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if !upcoming.isEmpty {
                    Button("Clear") {
                        if let current = engine.currentTrack { state.activeQueue = [current] }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            if upcoming.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                    Text("Nothing queued")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(upcoming.prefix(200)) { track in
                            QueueRow(track: track, theme: theme) {
                                engine.playTrack(track)
                            } onRemove: {
                                if let idx = state.activeQueue.firstIndex(where: { $0.id == track.id }) {
                                    state.activeQueue.remove(at: idx)
                                }
                            }
                        }
                        if upcoming.count > 200 {
                            Text("+ \(upcoming.count - 200) more")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: isFullscreen ? 420 : 300)
        .background {
            if isFullscreen {
                Rectangle().fill(.ultraThinMaterial).opacity(0.9)
            } else {
                theme.sidebarBackground
            }
        }
    }
}

private struct QueueRow: View {
    let track: LocalTrack
    let theme: ThemeColor
    let onPlay: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(track: track, pixelSize: 80, cornerRadius: 5)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .help("Remove from Queue")
            } else {
                Text(Fmt.time(track.duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Play Now", action: onPlay)
            Button("Remove from Queue", action: onRemove)
        }
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
    var isFullscreen: Bool = false

    var body: some View {
        let theme = isFullscreen ? ThemeCatalog.theme(named: "True Black") : state.theme

        VStack(spacing: 0) {
            PanelHeader(title: "Audio Output", theme: theme, isFullscreen: isFullscreen, onClose: isFullscreen ? nil : {
                withAnimation(.easeInOut(duration: 0.2)) { state.activeRightSidebar = .none }
            })

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nowPlayingCard(theme)
                    volumeCard(theme)

                    section("Speakers & Headphones", theme) {
                        VStack(spacing: 2) {
                            systemRow(theme)
                            ForEach(engine.availableOutputs) { device in
                                deviceRow(device, theme: theme)
                            }
                        }
                    }

                    section("AirPlay", theme) {
                        HStack(spacing: 12) {
                            AirPlayRouteButton(player: engine.avPlayer, tint: theme.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(theme.hover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AirPlay Speakers & TVs")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text("Click the icon to pick a HomePod, Apple TV or AirPlay speaker.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                    }

                    spatialCard(theme)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .frame(width: isFullscreen ? 420 : 300)
        .background {
            if isFullscreen {
                Rectangle().fill(.ultraThinMaterial).opacity(0.9)
            } else {
                theme.sidebarBackground
            }
        }
        .onAppear { engine.refreshAvailableDevices() }
    }

    // MARK: Cards

    /// Where the music is going right now, and what's playing, like Control Center's sound tile.
    private func nowPlayingCard(_ theme: ThemeColor) -> some View {
        let output = engine.currentOutput
        return VStack(spacing: 12) {
            Image(systemName: output.map(Self.symbol(for:)) ?? "speaker.wave.2.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(theme.accent.contrastingInk)
                .frame(width: 66, height: 66)
                .background(theme.accent, in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(spacing: 3) {
                Text(output?.name ?? "Mac Speakers")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(engine.activeOutputId == AudioDevices.systemID ? "Following your Mac's sound output" : (output?.model ?? ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textTertiary)
            }
            if let track = engine.currentTrack {
                AudioQualityTagsView(track: track, theme: theme)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .card(theme, radius: 14)
        .animation(.easeInOut(duration: 0.25), value: output?.id)
    }

    private func volumeCard(_ theme: ThemeColor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Volume")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("\(Int((engine.volume * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                ThinSlider(value: Binding(get: { Double(engine.volume) }, set: { engine.volume = Float($0) }), theme: theme, thickness: 6)
                    .frame(height: 18)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .card(theme, radius: 12)
    }

    private func spatialCard(_ theme: ThemeColor) -> some View {
        let supported = engine.currentOutput?.hasAtmos ?? false
        return section("Spatial Audio", theme, trailing: engine.isAtmosTrack ? AnyView(DolbyAtmosBadge(color: theme.textSecondary, scale: 0.9)) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $state.spatialAudioActive) {
                    Text("Off").tag(false)
                    Text("Spatialize Stereo").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!state.enableAtmos)
                Label {
                    Text(spatialNote(supported: supported))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: supported ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(supported ? theme.accent : theme.textTertiary)
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            }
            .padding(12)
        }
    }

    private func spatialNote(supported: Bool) -> String {
        if !state.enableAtmos { return "Turned off in Settings › Playback." }
        let name = engine.currentOutput?.name ?? "This output"
        if supported {
            return engine.isAtmosTrack
                ? "Playing in Dolby Atmos on \(name)."
                : (state.spatialAudioActive ? "Stereo songs are spatialized on \(name)." : "Dolby Atmos songs play in spatial audio on \(name).")
        }
        return "\(name) plays Dolby Atmos songs as a stereo mix. Spatial audio needs AirPods, Beats or a multichannel speaker setup."
    }

    // MARK: Rows

    private func section<Content: View>(_ title: String, _ theme: ThemeColor, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 4)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(theme, radius: 12)
        }
    }

    private func systemRow(_ theme: ThemeColor) -> some View {
        row(id: AudioDevices.systemID,
            symbol: "gearshape.fill",
            name: "System Output",
            detail: engine.systemOutput.map { "Now: \($0.name)" } ?? "Follows your Mac's Sound settings",
            theme: theme)
    }

    private func deviceRow(_ device: SwiftOutputDevice, theme: ThemeColor) -> some View {
        row(id: device.id, symbol: Self.symbol(for: device), name: device.name, detail: device.model, theme: theme)
    }

    private func row(id: String, symbol: String, name: String, detail: String, theme: ThemeColor) -> some View {
        let isActive = engine.activeOutputId == id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { engine.setOutputDevice(id: id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isActive ? theme.accent.contrastingInk : theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(isActive ? theme.accent : theme.hover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(OutputRowStyle(theme: theme))
    }

    /// The SF Symbol for a device, down to the AirPods model.
    static func symbol(for device: SwiftOutputDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("homepod") { return "homepod.fill" }
        if name.contains("apple tv") { return "appletv.fill" }
        switch device.type {
        case "built-in": return name.contains("macbook") ? "laptopcomputer" : "desktopcomputer"
        case "wired-headphones", "bluetooth": return "headphones"
        case "airplay": return "airplayaudio"
        case "display": return "tv"
        case "virtual": return "waveform"
        default: return "hifispeaker.fill"
        }
    }
}

private struct OutputRowStyle: ButtonStyle {
    let theme: ThemeColor
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, theme: theme)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let theme: ThemeColor
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(hovering || configuration.isPressed ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .padding(3)
                .onHover { hovering = $0 }
        }
    }
}

/// macOS's AirPlay picker, routing the player to the chosen speaker or TV.
struct AirPlayRouteButton: NSViewRepresentable {
    let player: AVPlayer?
    let tint: Color

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
        view.setRoutePickerButtonColor(NSColor(tint), for: .normal)
        view.setRoutePickerButtonColor(NSColor(tint), for: .active)
    }
}
