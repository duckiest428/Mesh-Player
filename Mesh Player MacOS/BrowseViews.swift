//
//  BrowseViews.swift
//  Mesh Player
//
//  Apple Music–style browsing: the artist page, search results, "See All" lists, All Playlists,
//  the shared song / album shelves they use, and the remove-from-library confirmation.
//

import AppKit
import SwiftUI

// MARK: - Removing songs and playlists

extension View {
    /// One confirmation for removing songs or deleting a playlist, with the option to move the
    /// audio files to the Trash as well.
    func removalDialog(state: AppStateManager) -> some View {
        modifier(RemovalDialog(state: state))
    }
}

private struct RemovalDialog: ViewModifier {
    @ObservedObject var state: AppStateManager
    @State private var trashFailures = 0

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: Binding(get: { state.pendingRemoval != nil }, set: { if !$0 { state.pendingRemoval = nil } }), titleVisibility: .visible, presenting: state.pendingRemoval) { removal in
                switch removal {
                case .songs(let tracks):
                    let ids = Set(tracks.map(\.id))
                    Button("Remove from Library") { state.removeFromLibrary(ids, trashFiles: false) }
                    Button("Remove and Move \(tracks.count == 1 ? "File" : "Files") to Trash", role: .destructive) {
                        trashFailures = state.removeFromLibrary(ids, trashFiles: true)
                    }
                    Button("Cancel", role: .cancel) {}
                case .playlist(let playlist):
                    Button("Delete Playlist Only") { state.deletePlaylist(playlist.id, songs: .keep) }
                    Button("Delete Playlist and Remove Its Songs from Library") { state.deletePlaylist(playlist.id, songs: .removeFromLibrary) }
                    Button("Delete Playlist and Move Its Songs to Trash", role: .destructive) { state.deletePlaylist(playlist.id, songs: .moveFilesToTrash) }
                    Button("Cancel", role: .cancel) {}
                }
            } message: { removal in
                switch removal {
                case .songs(let tracks):
                    Text("Removing keeps the \(tracks.count == 1 ? "file" : "files") on disk. Moving to the Trash deletes \(tracks.count == 1 ? "it" : "them") from your Mac too (you can still restore from the Trash).")
                case .playlist(let playlist):
                    let count = state.resolvedTracks(of: playlist).count
                    Text("“\(playlist.name)” has \(Fmt.songs(count)). You can keep them, remove them from your library, or also move their files to the Trash.")
                }
            }
            .alert("Some files couldn't be moved to the Trash", isPresented: Binding(get: { trashFailures > 0 }, set: { if !$0 { trashFailures = 0 } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(trashFailures) \(trashFailures == 1 ? "file" : "files") couldn't be moved. They were still removed from your library.")
            }
    }

    private var title: String {
        switch state.pendingRemoval {
        case .songs(let tracks)?:
            return tracks.count == 1 ? "Remove “\(tracks[0].title)” from your library?" : "Remove \(tracks.count) songs from your library?"
        case .playlist(let playlist)?:
            return "Delete “\(playlist.name)”?"
        case nil:
            return ""
        }
    }
}

// MARK: - Song shelf (columns of rows, like Apple Music's Songs / Top Songs)

struct SongShelf: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let tracks: [LocalTrack]
    var rows = 3
    var columnWidth: CGFloat = 330
    var subtitle: (LocalTrack) -> String = { $0.artist }

    var body: some View {
        let theme = state.theme
        let columns = stride(from: 0, to: tracks.count, by: rows).map { Array(tracks[$0..<min($0 + rows, tracks.count)]) }
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 18) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 0) {
                        ForEach(Array(column.enumerated()), id: \.element.id) { index, track in
                            SongShelfRow(state: state, engine: engine, track: track, subtitle: subtitle(track), theme: theme) {
                                state.play(tracks, startingAt: track, engine: engine)
                            }
                            if index < column.count - 1 {
                                Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 60)
                            }
                        }
                    }
                    .frame(width: columnWidth, alignment: .top)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 4)
        }
    }
}

struct SongShelfRow: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let track: LocalTrack
    let subtitle: String
    let theme: ThemeColor
    let onPlay: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, pixelSize: 96, cornerRadius: 5)
                .frame(width: 46, height: 46)
                .overlay {
                    if hovering {
                        RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.45))
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .onTapGesture(perform: onPlay)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if track.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(theme.accent)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Menu {
                TrackMenuItems(state: state, engine: engine, tracks: [track])
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(hovering ? theme.accent : theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(hovering ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu { TrackMenuItems(state: state, engine: engine, tracks: [track]) }
    }
}

/// The usual song actions, shared by shelves and lists.
struct TrackMenuItems: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let tracks: [LocalTrack]

    var body: some View {
        Button("Play Next") { state.playNext(tracks, engine: engine) }
        Button("Play Later") { state.playLater(tracks, engine: engine) }
        Divider()
        Menu("Add to Playlist") {
            Button("New Playlist") { state.createNewPlaylist(name: tracks.count == 1 ? tracks[0].title : "New Playlist", tracks: tracks) }
            Divider()
            ForEach(state.editablePlaylists) { playlist in
                Button(playlist.name) { state.addTracksToPlaylist(tracks, playlistId: playlist.id) }
            }
        }
        if let track = tracks.first, tracks.count == 1 {
            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") { state.toggleFavorite(track: track) }
            Divider()
            Button("Go to Album") { state.showAlbum(of: track) }
            Button("Go to Artist") { state.showArtist(track.artist) }
        }
        Divider()
        Button("Show in Finder") {
            let urls = tracks.compactMap(\.fileURL)
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
        Button(tracks.count == 1 ? "Remove from Library…" : "Remove \(tracks.count) Songs from Library…", role: .destructive) {
            state.confirmRemoval(of: tracks)
        }
    }
}

// MARK: - Album shelf

struct AlbumShelf: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let albums: [LocalAlbum]
    var subtitle: (LocalAlbum) -> String? = { _ in nil }

    var body: some View {
        let theme = state.theme
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(albums) { album in
                    AlbumCell(album: album, theme: theme, subtitle: subtitle(album)) {
                        state.showAlbum(album.key)
                    } onPlay: {
                        state.play(state.albumTracks(named: album.key), engine: engine)
                    }
                    .frame(width: 170)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
        }
    }
}

struct ArtistCircle: View {
    let name: String
    let representative: LocalTrack?
    let theme: ThemeColor
    var size: CGFloat = 150
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            CachedArtistProfileView(artistName: name, themeAccent: theme.accent, size: size, fallbackTrack: representative)
                .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 10, y: 5)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(width: size)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .hoverLift(1.04)
    }
}

// MARK: - Artist data

/// Everything the artist page shows, worked out from the library in one pass.
struct ArtistCatalog {
    let name: String
    /// Songs by the artist (artist or album artist).
    let songs: [LocalTrack]
    /// Albums credited to the artist, newest first (no singles / EPs).
    let albums: [LocalAlbum]
    let singles: [LocalAlbum]
    /// Other artists' albums the artist features on.
    let appearsOn: [LocalAlbum]
    let appearsOnSongs: [LocalTrack]
    let mostPlayedSongs: [LocalTrack]
    let mostPlayedAlbums: [LocalAlbum]
    let playlists: [Playlist]
    let totalPlays: Int

    init(name: String, state: AppStateManager) {
        self.name = name
        let lower = name.lowercased()
        let library = state.libraryTracks
        let songs = library.filter { state.displayArtist($0.artist) == name || $0.albumArtist == name }
        self.songs = songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let mainIds = Set(songs.map(\.id))
        // "feat." credits and "A & B" collaborations.
        appearsOnSongs = library.filter { track in
            !mainIds.contains(track.id) && Self.credits(track.artist).contains(lower)
        }

        let byKey = Dictionary(state.albumsList.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let ownAlbumKeys = Set(songs.map { state.albumKey(for: $0) })
        let own = ownAlbumKeys.compactMap { byKey[$0] }.filter { album in
            album.artist == name || Self.credits(album.artist).contains(lower) || songs.contains { state.albumKey(for: $0) == album.key && $0.albumArtist == nil }
        }
        let isSingle: (LocalAlbum) -> Bool = { album in
            if album.name.hasSuffix(" - Single") || album.name.hasSuffix(" - EP") { return true }
            let titles = Set(state.albumTracks(named: album.key).map { AnimatedArtworkService.normalize($0.title).lowercased() })
            return album.tracksCount <= 3 && titles.contains(AnimatedArtworkService.normalize(album.name).lowercased())
        }
        let newestFirst: (LocalAlbum, LocalAlbum) -> Bool = { ($0.yearRecorded ?? 0, $0.name) > ($1.yearRecorded ?? 0, $1.name) }
        albums = own.filter { !isSingle($0) }.sorted(by: newestFirst)
        singles = own.filter(isSingle).sorted(by: newestFirst)
        let ownKeys = Set(own.map(\.key))
        appearsOn = Set(appearsOnSongs.map { state.albumKey(for: $0) }).subtracting(ownKeys).compactMap { byKey[$0] }.sorted(by: newestFirst)

        mostPlayedSongs = Array(songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(30))
        var albumPlays: [String: Int] = [:]
        for track in songs { albumPlays[state.albumKey(for: track), default: 0] += track.playCount }
        mostPlayedAlbums = own.filter { (albumPlays[$0.key] ?? 0) > 0 }.sorted { (albumPlays[$0.key] ?? 0) > (albumPlays[$1.key] ?? 0) }
        totalPlays = songs.reduce(0) { $0 + $1.playCount }

        let allIds = mainIds.union(appearsOnSongs.map(\.id))
        playlists = state.playlists.filter { playlist in
            !playlist.isSmart && playlist.playlistTracks.contains { allIds.contains($0.track.id) }
        }
    }

    /// Lowercased artist names credited in an artist field ("A & B feat. C" → a, b, c).
    static func credits(_ artist: String) -> Set<String> {
        let separators = [" & ", ", ", " feat. ", " ft. ", " featuring ", " x ", " with ", " and "]
        var parts = [artist.lowercased()]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return Set(parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}

// MARK: - Artist page

struct ArtistPageView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let name: String

    @State private var catalog: CatalogArtistInfo?
    @Environment(\.pageTopInset) private var topInset
    @State private var banner: NSImage?

    var body: some View {
        let theme = state.theme
        let data = ArtistCatalog(name: name, state: state)

        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header(data, theme: theme)

                if !data.mostPlayedSongs.isEmpty {
                    section("Most Played Songs", .mostPlayedSongs, theme: theme) {
                        SongShelf(state: state, engine: engine, tracks: Array(data.mostPlayedSongs.prefix(12))) { track in
                            "\(track.album) · \(Fmt.count(track.playCount)) play\(track.playCount == 1 ? "" : "s")"
                        }
                    }
                }

                if !data.mostPlayedAlbums.isEmpty {
                    section("Most Played Albums", .mostPlayedAlbums, theme: theme) {
                        AlbumShelf(state: state, engine: engine, albums: Array(data.mostPlayedAlbums.prefix(12))) { album in
                            album.yearRecorded.map(String.init)
                        }
                    }
                }

                if !data.albums.isEmpty {
                    section("Albums", .albums, theme: theme) {
                        AlbumShelf(state: state, engine: engine, albums: data.albums) { album in
                            album.yearRecorded.map(String.init) ?? "Album"
                        }
                    }
                }

                if !data.singles.isEmpty {
                    section("Singles & EPs", .singles, theme: theme) {
                        AlbumShelf(state: state, engine: engine, albums: data.singles) { album in
                            album.yearRecorded.map(String.init) ?? "Single"
                        }
                    }
                }

                if !data.songs.isEmpty {
                    section("Songs", .songs, theme: theme) {
                        SongShelf(state: state, engine: engine, tracks: Array(data.songs.prefix(24))) { $0.album }
                    }
                }

                if !data.appearsOn.isEmpty {
                    section("Appears On", .appearsOn, theme: theme) {
                        AlbumShelf(state: state, engine: engine, albums: data.appearsOn) { $0.artist }
                    }
                }

                if let essentials = catalog?.essentialAlbums, !essentials.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Essential Albums", subtitle: "From Apple Music", theme: theme)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 20) {
                                ForEach(essentials) { album in
                                    EssentialAlbumCell(album: album, theme: theme, inLibrary: localAlbum(for: album) != nil) {
                                        openEssential(album)
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                        }
                    }
                }

                if !data.playlists.isEmpty {
                    section("Found in Your Playlists", .playlists, theme: theme) {
                        PlaylistShelf(state: state, playlists: data.playlists)
                    }
                }

                if let bio = catalog?.bio, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About \(name)")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(bio)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: 760, alignment: .leading)
                    }
                    .padding(.horizontal, 28)
                } else {
                    ArtistBioView(artistName: name, themeAccent: theme.accent, textColor: theme.textPrimary)
                        .padding(.horizontal, 28)
                }
            }
            .padding(.bottom, 48)
        }
        .background(theme.background)
        .task(id: name) { await loadCatalog() }
    }

    // MARK: Header

    private func header(_ data: ArtistCatalog, theme: ThemeColor) -> some View {
        let isFavorite = state.favoriteArtists.contains(name)
        return ZStack(alignment: .bottom) {
            Group {
                if let banner {
                    Image(nsImage: banner).resizable().scaledToFill()
                } else if let first = data.songs.first ?? data.appearsOnSongs.first {
                    ArtworkView(track: first, pixelSize: 96, cornerRadius: 0, placeholderSymbol: nil)
                        .blur(radius: 50, opaque: true)
                        .scaleEffect(1.3)
                } else {
                    theme.cardBackground
                }
            }
            .frame(height: 380 + topInset)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.15), location: 0.45),
                .init(color: theme.background.opacity(0.85), location: 0.85),
                .init(color: theme.background, location: 1)
            ], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 14) {
                Text(name)
                    .font(.system(size: 50, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 3)
                Text(summary(data))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 6)
                HStack(spacing: 18) {
                    circleButton("shuffle", size: 44, help: "Shuffle") {
                        state.play(data.songs, shuffled: true, engine: engine)
                    }
                    Button {
                        state.play(data.songs, shuffled: false, engine: engine)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: 2)
                            .frame(width: 72, height: 72)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    }
                    .buttonStyle(PressableStyle())
                    .help("Play")
                    circleButton(isFavorite ? "heart.fill" : "heart", size: 44, help: isFavorite ? "Remove from Favorite Artists" : "Add to Favorite Artists") {
                        if isFavorite { state.favoriteArtists.remove(name) } else { state.favoriteArtists.insert(name) }
                    }
                }
                .disabled(data.songs.isEmpty)
            }
            .padding(.bottom, 26)
            .padding(.horizontal, 28)
        }
        .frame(height: 380 + topInset)
        .environment(\.colorScheme, .dark)
    }

    private func circleButton(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }

    private func summary(_ data: ArtistCatalog) -> String {
        var parts = [Fmt.songs(data.songs.count)]
        let albumCount = data.albums.count + data.singles.count
        if albumCount > 0 { parts.append("\(albumCount) release\(albumCount == 1 ? "" : "s")") }
        if data.totalPlays > 0 { parts.append("\(Fmt.count(data.totalPlays)) plays") }
        return parts.joined(separator: " · ")
    }

    private func section<Content: View>(_ title: String, _ kind: ArtistSection, theme: ThemeColor, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, theme: theme) {
                state.open(tab: "artists", filter: "artistSection", value: kind.rawValue + "\u{1}" + name)
            }
            content()
        }
    }

    // MARK: Apple Music

    private func loadCatalog() async {
        catalog = AppleMusicCatalog.shared.cachedArtist(named: name)
        banner = nil
        let fetched = await AppleMusicCatalog.shared.artist(named: name)
        guard !Task.isCancelled else { return }
        if fetched != catalog { withAnimation(.easeOut(duration: 0.2)) { catalog = fetched } }
        await loadBanner()
    }

    private func loadBanner() async {
        let url = catalog?.bannerURL(width: 2400) ?? catalog?.artworkURL(1600)
        if let url, let image = await Self.image(from: url) {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { banner = image }
            return
        }
        // Fall back to the existing banner lookup.
        guard let file = try? await CachedArtistBannerService.shared.fetchAndCacheArtistBanner(for: name) else { return }
        let image = await Task.detached(priority: .utility) { ArtworkStore.downsample(url: file, maxPixel: 1800) }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { banner = image }
    }

    /// Downloads (and caches on disk) a catalog image.
    static func image(from url: URL) async -> NSImage? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player/Catalog Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let file = caches.appendingPathComponent(String(format: "%016llx", url.absoluteString.hashValue.magnitude) + ".jpg")
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? data.write(to: file, options: .atomic)
        }
        return await Task.detached(priority: .utility) { ArtworkStore.downsample(url: file, maxPixel: 2400) }.value
    }

    private func localAlbum(for album: CatalogAlbumInfo) -> LocalAlbum? {
        let wanted = AnimatedArtworkService.normalize(album.name)
        return state.albumsList.first { AnimatedArtworkService.normalize($0.name).caseInsensitiveCompare(wanted) == .orderedSame }
    }

    private func openEssential(_ album: CatalogAlbumInfo) {
        if let local = localAlbum(for: album) {
            state.showAlbum(local.key)
        } else {
            state.getMusicQuery = "\(album.name) \(album.artist)"
            state.selectedTab = "getMusic"
        }
    }
}

enum ArtistSection: String {
    case mostPlayedSongs, mostPlayedAlbums, albums, singles, songs, appearsOn, playlists

    var title: String {
        switch self {
        case .mostPlayedSongs: return "Most Played Songs"
        case .mostPlayedAlbums: return "Most Played Albums"
        case .albums: return "Albums"
        case .singles: return "Singles & EPs"
        case .songs: return "Songs"
        case .appearsOn: return "Appears On"
        case .playlists: return "Found in Your Playlists"
        }
    }
}

private struct EssentialAlbumCell: View {
    let album: CatalogAlbumInfo
    let theme: ThemeColor
    let inLibrary: Bool
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: album.artworkURL(600)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkPlaceholder(seed: album.name, symbol: "music.note")
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !inLibrary {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, theme.accent)
                        .padding(8)
                        .opacity(hovering ? 1 : 0.85)
                        .help("Not in your library — opens Get Music")
                }
            }
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let notes = album.notesShort {
                    Text(notes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let year = album.year {
                    Text(year).font(.system(size: 11.5)).foregroundStyle(theme.textSecondary)
                }
            }
        }
        .frame(width: 220, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .hoverLift(1.02)
    }
}

// MARK: - Playlists shelf / All Playlists

struct PlaylistShelf: View {
    @ObservedObject var state: AppStateManager
    let playlists: [Playlist]

    var body: some View {
        let theme = state.theme
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(playlists) { playlist in
                    PlaylistCell(state: state, playlist: playlist, theme: theme)
                        .frame(width: 170)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
        }
    }
}

struct PlaylistCell: View {
    @ObservedObject var state: AppStateManager
    let playlist: Playlist
    let theme: ThemeColor

    var body: some View {
        let tracks = state.resolvedTracks(of: playlist)
        VStack(alignment: .leading, spacing: 8) {
            PlaylistCover(playlist: playlist, tracks: tracks, state: state, theme: theme)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.1), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(playlist.isSmart ? "Smart Playlist · \(Fmt.songs(tracks.count))" : Fmt.songs(tracks.count))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectedTab = "playlist-\(playlist.id.uuidString)" }
        .contextMenu {
            Button("Open") { state.selectedTab = "playlist-\(playlist.id.uuidString)" }
            if !playlist.isAppleMusicFavorites {
                Button("Delete Playlist…", role: .destructive) { state.confirmDeletion(of: playlist) }
            }
        }
        .hoverLift(1.03)
    }
}

struct AllPlaylistsView: View {
    @ObservedObject var state: AppStateManager
    @State private var sort: Sort = .manual

    enum Sort: String, CaseIterable, Identifiable {
        case manual = "Sidebar Order"
        case name = "Name"
        case recent = "Recently Modified"
        case size = "Most Songs"
        var id: String { rawValue }
    }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 22, alignment: .top)]

    var body: some View {
        let theme = state.theme
        let query = state.searchKeyword.trimmingCharacters(in: .whitespaces)
        let playlists = sorted(state.playlists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "All Playlists", subtitle: "\(playlists.count) playlist\(playlists.count == 1 ? "" : "s")", theme: theme) {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .fixedSize()
                    Menu {
                        Button("New Playlist") { state.createNewPlaylist(name: "New Playlist", tracks: []) }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .fixedSize()
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    ForEach(playlists) { playlist in
                        PlaylistCell(state: state, playlist: playlist, theme: theme)
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }

    private func sorted(_ list: [Playlist]) -> [Playlist] {
        switch sort {
        case .manual: return list
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent: return list.sorted { ($0.dateModified ?? $0.dateCreated ?? .distantPast) > ($1.dateModified ?? $1.dateCreated ?? .distantPast) }
        case .size: return list.sorted { state.resolvedTracks(of: $0).count > state.resolvedTracks(of: $1).count }
        }
    }
}

// MARK: - "See All" pages

/// Full list for one of the artist page's sections.
struct ArtistSectionView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let section: ArtistSection
    let name: String

    var body: some View {
        let theme = state.theme
        let data = ArtistCatalog(name: name, state: state)
        switch section {
        case .mostPlayedSongs:
            TrackListPage(state: state, engine: engine, title: section.title, subtitle: name, tracks: data.mostPlayedSongs, showPlays: true)
        case .songs:
            TrackListPage(state: state, engine: engine, title: "Songs", subtitle: name, tracks: data.songs + data.appearsOnSongs, showPlays: false)
        case .mostPlayedAlbums:
            AlbumGridPage(state: state, engine: engine, title: section.title, subtitle: name, albums: data.mostPlayedAlbums)
        case .albums:
            AlbumGridPage(state: state, engine: engine, title: section.title, subtitle: name, albums: data.albums)
        case .singles:
            AlbumGridPage(state: state, engine: engine, title: section.title, subtitle: name, albums: data.singles)
        case .appearsOn:
            AlbumGridPage(state: state, engine: engine, title: section.title, subtitle: name, albums: data.appearsOn, showArtist: true)
        case .playlists:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: section.title, subtitle: name, theme: theme) { EmptyView() }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 22, alignment: .top)], alignment: .leading, spacing: 26) {
                        ForEach(data.playlists) { PlaylistCell(state: state, playlist: $0, theme: theme) }
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 32)
            }
            .background(theme.background)
        }
    }
}

struct AlbumGridPage: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let title: String
    let subtitle: String
    let albums: [LocalAlbum]
    var showArtist = false

    var body: some View {
        let theme = state.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: title, subtitle: "\(subtitle) · \(albums.count) album\(albums.count == 1 ? "" : "s")", theme: theme) { EmptyView() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 22, alignment: .top)], alignment: .leading, spacing: 26) {
                    ForEach(albums) { album in
                        AlbumCell(album: album, theme: theme, subtitle: showArtist ? album.artist : (album.yearRecorded.map(String.init) ?? album.artist)) {
                            state.showAlbum(album.key)
                        } onPlay: {
                            state.play(state.albumTracks(named: album.key), engine: engine)
                        }
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }
}

struct TrackListPage: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let title: String
    let subtitle: String
    let tracks: [LocalTrack]
    var showPlays = false

    var body: some View {
        let theme = state.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: title, subtitle: "\(subtitle) · \(Fmt.songs(tracks.count))", theme: theme) {
                    Button { state.play(tracks, shuffled: false, engine: engine) } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
                    Button { state.play(tracks, shuffled: true, engine: engine) } label: { Label("Shuffle", systemImage: "shuffle") }
                        .buttonStyle(PillButtonStyle(kind: .secondary, theme: theme, compact: true))
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackListRow(state: state, engine: engine, index: index + 1, track: track, showPlays: showPlays, theme: theme) {
                            state.play(tracks, startingAt: track, engine: engine)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .background(theme.background)
    }
}

private struct TrackListRow: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let index: Int
    let track: LocalTrack
    let showPlays: Bool
    let theme: ThemeColor
    let onPlay: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 28, alignment: .trailing)
            ArtworkView(track: track, pixelSize: 80, cornerRadius: 4)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textPrimary).lineLimit(1)
                Text(track.artist).font(.system(size: 11.5)).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.album)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)
            if showPlays {
                Text("\(Fmt.count(track.playCount)) plays")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 80, alignment: .trailing)
            }
            Text(Fmt.time(track.duration))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu { TrackMenuItems(state: state, engine: engine, tracks: [track]) }
    }
}

// MARK: - Search

/// Apple Music–style search results: artists, albums, songs and playlists from the library, or
/// the Apple Music catalog (downloads go through Get Music).
struct SearchResultsView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    @ObservedObject private var downloader = AmdlDownloader.shared

    enum Scope: String, CaseIterable, Identifiable {
        case library = "Library"
        case appleMusic = "Apple Music"
        var id: String { rawValue }
    }

    @AppStorage("search.scope") private var scope: Scope = .library
    @State private var catalogResults: [CatalogItem] = []
    @State private var isSearchingCatalog = false

    private var query: String { state.searchKeyword.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let theme = state.theme
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Text(query.isEmpty ? "Type in the search field to find music" : "Results for “\(query)”")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 14)

            switch scope {
            case .library: libraryResults(theme)
            case .appleMusic: catalogSection(theme)
            }
        }
        .background(theme.background)
        .task(id: scope == .appleMusic ? query : "") {
            guard scope == .appleMusic, query.count >= 2 else { catalogResults = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearchingCatalog = true
            let found = await CatalogSearch.search(query)
            guard !Task.isCancelled else { return }
            catalogResults = found
            isSearchingCatalog = false
        }
    }

    // MARK: Library

    @ViewBuilder
    private func libraryResults(_ theme: ThemeColor) -> some View {
        let results = SearchMatches(query: query, state: state)
        if results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Text(query.isEmpty ? "Search your library" : "No results in your library")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                if !query.isEmpty {
                    Button("Search Apple Music") { scope = .appleMusic }
                        .buttonStyle(PillButtonStyle(kind: .secondary, theme: theme, compact: true))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !results.artists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Artists", theme: theme) { seeAll(.artists) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 22) {
                                    ForEach(results.artists.prefix(16)) { artist in
                                        ArtistCircle(name: artist.name, representative: artist.trackRepresentative, theme: theme, size: 150) {
                                            state.showArtist(artist.name)
                                        }
                                    }
                                }
                                .padding(.horizontal, 28)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Albums", theme: theme) { seeAll(.albums) }
                            AlbumShelf(state: state, engine: engine, albums: Array(results.albums.prefix(16))) { $0.artist }
                        }
                    }
                    if !results.songs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Songs", theme: theme) { seeAll(.songs) }
                            SongShelf(state: state, engine: engine, tracks: Array(results.songs.prefix(24)))
                        }
                    }
                    if !results.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Playlists", theme: theme) { seeAll(.playlists) }
                            PlaylistShelf(state: state, playlists: Array(results.playlists.prefix(16)))
                        }
                    }
                    if !results.genres.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Genres", theme: theme)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(results.genres) { genre in
                                        Button(genre.name) { state.showGenre(genre.name) }
                                            .buttonStyle(PillButtonStyle(kind: .secondary, theme: theme, compact: true))
                                    }
                                }
                                .padding(.horizontal, 28)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func seeAll(_ kind: SearchSection) {
        state.open(tab: "search", filter: "searchSection", value: kind.rawValue + "\u{1}" + query)
    }

    // MARK: Apple Music

    @ViewBuilder
    private func catalogSection(_ theme: ThemeColor) -> some View {
        if catalogResults.isEmpty {
            VStack(spacing: 10) {
                if isSearchingCatalog {
                    ProgressView()
                } else {
                    Image(systemName: "applelogo")
                        .font(.system(size: 34))
                        .foregroundStyle(theme.textTertiary)
                    Text(query.count >= 2 ? "No results on Apple Music" : "Search the Apple Music catalog")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text("Download anything with am-dl and it's added to your library automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(catalogResults) { item in
                        CatalogRow(item: item, theme: theme, inLibrary: state.hasCatalogItem(item), job: downloader.jobs.first { $0.item.id == item.id }) {
                            downloader.enqueue(item, state: state)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .onAppear { downloader.prepare() }
        }
    }
}

enum SearchSection: String {
    case artists, albums, songs, playlists

    var title: String { rawValue.capitalized }
}

/// Library matches for a search, best matches first (name starts with the query, then a word
/// starts with it, then it appears anywhere).
struct SearchMatches {
    let artists: [LocalArtist]
    let albums: [LocalAlbum]
    let songs: [LocalTrack]
    let playlists: [Playlist]
    let genres: [LocalGenre]

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty && playlists.isEmpty && genres.isEmpty }

    init(query: String, state: AppStateManager) {
        let q = query.lowercased()
        guard !q.isEmpty else {
            artists = []; albums = []; songs = []; playlists = []; genres = []
            return
        }
        func rank(_ text: String) -> Int? {
            let t = text.lowercased()
            if t.hasPrefix(q) { return 0 }
            if t.range(of: " " + q) != nil || t.range(of: "(" + q) != nil { return 1 }
            if t.contains(q) { return 2 }
            return nil
        }
        func ranked<T>(_ items: [T], _ text: (T) -> String, _ secondary: ((T) -> String)? = nil) -> [T] {
            items.compactMap { item -> (T, Int)? in
                if let r = rank(text(item)) { return (item, r) }
                if let secondary, let r = rank(secondary(item)) { return (item, r + 3) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        }
        artists = ranked(state.artistsList, \.name)
        albums = ranked(state.albumsList, \.name, \.artist)
        songs = ranked(state.libraryTracks, \.title) { "\($0.artist) \($0.album)" }
        playlists = ranked(state.playlists, \.name)
        genres = ranked(state.genresList, \.name)
    }
}

struct SearchSectionView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let section: SearchSection
    let query: String

    var body: some View {
        let theme = state.theme
        let results = SearchMatches(query: query, state: state)
        switch section {
        case .songs:
            TrackListPage(state: state, engine: engine, title: "Songs", subtitle: "“\(query)”", tracks: results.songs)
        case .albums:
            AlbumGridPage(state: state, engine: engine, title: "Albums", subtitle: "“\(query)”", albums: results.albums, showArtist: true)
        case .artists, .playlists:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: section.title, subtitle: "“\(query)”", theme: theme) { EmptyView() }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 22, alignment: .top)], alignment: .leading, spacing: 26) {
                        if section == .artists {
                            ForEach(results.artists) { artist in
                                ArtistCircle(name: artist.name, representative: artist.trackRepresentative, theme: theme, size: 150) {
                                    state.showArtist(artist.name)
                                }
                            }
                        } else {
                            ForEach(results.playlists) { PlaylistCell(state: state, playlist: $0, theme: theme) }
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 32)
            }
            .background(theme.background)
        }
    }
}

// MARK: - Genre page

/// A genre's page: a colored header, then its most played songs, albums, artists, recent
/// additions and every song.
struct GenrePageView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager
    let name: String

    var body: some View {
        let theme = state.theme
        let tint = GenreStyle.tint(for: name)
        let m = makeModel()
        let songs = m.songs, albums = m.albums, artists = m.artists, topAlbums = m.topAlbums, topArtists = m.topArtists
        let mostPlayed = m.mostPlayed, recent = m.recent, allSongs = m.allSongs, totalPlays = m.totalPlays, minutes = m.minutes

        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                // Header
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [tint, tint.opacity(0.55), theme.background], startPoint: .topLeading, endPoint: .bottom)
                    GenreCoverFan(tracks: topAlbums.prefix(3).map(\.trackRepresentative), size: 150)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 48)
                        .padding(.bottom, 40)
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Genre", color: .white.opacity(0.8))
                        Text(name)
                            .font(.system(size: 50, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("\(Fmt.songs(songs.count)) · \(albums.count) album\(albums.count == 1 ? "" : "s") · \(artists.count) artist\(artists.count == 1 ? "" : "s") · \(minutes) min\(totalPlays > 0 ? " · \(Fmt.count(totalPlays)) plays" : "")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 8) {
                            Button { state.play(allSongs, shuffled: false, engine: engine) } label: { Label("Play", systemImage: "play.fill") }
                                .buttonStyle(PillButtonStyle(kind: .primary, theme: theme))
                            Button { state.play(allSongs, shuffled: true, engine: engine) } label: { Label("Shuffle", systemImage: "shuffle") }
                                .buttonStyle(PillButtonStyle(kind: .ghost, theme: ThemeCatalog.theme(named: "True Black")))
                        }
                        .padding(.top, 4)
                        .disabled(songs.isEmpty)
                    }
                    .padding(28)
                }
                .frame(height: 300)
                .environment(\.colorScheme, .dark)

                if !mostPlayed.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Most Played", theme: theme)
                        SongShelf(state: state, engine: engine, tracks: Array(mostPlayed.prefix(12))) { track in
                            "\(track.artist) · \(Fmt.count(track.playCount)) play\(track.playCount == 1 ? "" : "s")"
                        }
                    }
                }
                if !topAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Albums", theme: theme)
                        AlbumShelf(state: state, engine: engine, albums: topAlbums) { $0.artist }
                    }
                }
                if !topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Artists", theme: theme)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 22) {
                                ForEach(topArtists) { artist in
                                    ArtistCircle(name: artist.name, representative: artist.trackRepresentative, theme: theme, size: 130) {
                                        state.showArtist(artist.name)
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 6)
                        }
                    }
                }
                if recent.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Recently Added", theme: theme)
                        AlbumShelf(state: state, engine: engine, albums: Array(recent.prefix(12))) { album in
                            "Added \(Fmt.relative(album.trackRepresentative.dateAdded))"
                        }
                    }
                }
                if !allSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "All Songs", theme: theme) {
                            state.open(tab: "genres", filter: "genreSongs", value: name)
                        }
                        SongShelf(state: state, engine: engine, tracks: Array(allSongs.prefix(24)))
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .background(theme.background)
    }
    private struct Model {
        var songs: [LocalTrack] = []
        var albums: [LocalAlbum] = []
        var artists: [LocalArtist] = []
        var topAlbums: [LocalAlbum] = []
        var topArtists: [LocalArtist] = []
        var mostPlayed: [LocalTrack] = []
        var recent: [LocalAlbum] = []
        var allSongs: [LocalTrack] = []
        var totalPlays = 0
        var minutes = 0
    }

    private func makeModel() -> Model {
        let songs = state.libraryTracks.filter { $0.genre == name }
        let albumKeys = Set(songs.map { state.albumKey(for: $0) })
        let albums = state.albumsList.filter { albumKeys.contains($0.key) }
        var plays: [String: Int] = [:]
        for track in songs { plays[state.albumKey(for: track), default: 0] += track.playCount }
        let topAlbums = albums.sorted { (plays[$0.key] ?? 0, $0.name) > (plays[$1.key] ?? 0, $1.name) }
        let artistNames = Set(songs.map { state.displayArtist($0.artist) })
        let artists = state.artistsList.filter { artistNames.contains($0.name) }
        var artistPlays: [String: Int] = [:]
        for track in songs { artistPlays[state.displayArtist(track.artist), default: 0] += track.playCount }
        let topArtists = artists.sorted { (artistPlays[$0.name] ?? 0) > (artistPlays[$1.name] ?? 0) }
        let mostPlayed = songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }
        let recent = albums.sorted { $0.trackRepresentative.dateAdded > $1.trackRepresentative.dateAdded }
        let allSongs = songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let totalPlays = songs.reduce(0) { $0 + $1.playCount }
        let minutes = Int(songs.reduce(0) { $0 + $1.duration } / 60)

        return Model(songs: songs, albums: albums, artists: artists, topAlbums: topAlbums, topArtists: topArtists, mostPlayed: mostPlayed,
                     recent: recent, allSongs: allSongs, totalPlays: totalPlays, minutes: minutes)
    }

}

enum GenreStyle {
    static let tints: [Color] = [
        Color(red: 0.93, green: 0.27, blue: 0.40), Color(red: 0.36, green: 0.45, blue: 0.98), Color(red: 0.98, green: 0.55, blue: 0.20),
        Color(red: 0.15, green: 0.70, blue: 0.60), Color(red: 0.62, green: 0.40, blue: 0.95), Color(red: 0.90, green: 0.35, blue: 0.75),
        Color(red: 0.20, green: 0.60, blue: 0.90), Color(red: 0.55, green: 0.70, blue: 0.25)
    ]

    static func tint(for genre: String) -> Color {
        tints[Int(UInt(bitPattern: genre.utf8.reduce(7) { ($0 &* 31) &+ Int($1) }) % UInt(tints.count))]
    }
}

/// Up to three album covers fanned out, used on genre tiles and the genre header.
struct GenreCoverFan: View {
    let tracks: [LocalTrack]
    var size: CGFloat = 70

    var body: some View {
        ZStack {
            ForEach(Array(tracks.enumerated().reversed()), id: \.offset) { index, track in
                ArtworkView(track: track, pixelSize: size * 2, cornerRadius: size * 0.08)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .rotationEffect(.degrees(Double(index) * 9 - 4))
                    .offset(x: CGFloat(index) * -size * 0.32, y: CGFloat(index) * size * 0.04)
            }
        }
    }
}
