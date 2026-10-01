//
//  LibraryViews.swift
//  Mesh Player iOS
//
//  Library tab: categories, Recently Added, and the album / artist / playlist / song screens.
//

import SwiftUI

struct LibraryHomeView: View {
    @EnvironmentObject var library: MobileLibrary
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(LibraryRoute.allCases, id: \.self) { route in
                        row(route)
                    }
                }
                .padding(.horizontal)

                Text("Recently Added")
                    .font(.title2.bold())
                    .padding(.horizontal)
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                    ForEach(Array(library.recentlyAddedAlbums.prefix(40))) { album in
                        NavigationLink(value: album) { AlbumGridCell(album: album) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Library")
        .libraryDestinations()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func row(_ route: LibraryRoute) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: route.icon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 30)
                    Text(route.title).font(.title3).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                Divider().padding(.leading, 44)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The category rows at the top of Library.
enum LibraryRoute: String, CaseIterable, Hashable {
    case playlists, artists, albums, songs, genres, favorites

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .playlists: return "music.note.list"
        case .artists: return "music.microphone"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .genres: return "guitars"
        case .favorites: return "star"
        }
    }
}

struct LibraryRouteView: View {
    let route: LibraryRoute
    @EnvironmentObject var library: MobileLibrary

    var body: some View {
        switch route {
        case .playlists: PlaylistsView()
        case .artists: ArtistsView()
        case .albums: AlbumsView()
        case .songs: SongsView(title: "Songs", songs: nil)
        case .genres: GenresView()
        case .favorites:
            if let favorites = library.playlists.first(where: \.isFavorites) {
                PlaylistView(playlistId: favorites.id)
            } else {
                ContentUnavailableView("No Favorites", systemImage: "star")
            }
        }
    }
}

struct AlbumGridCell: View {
    let album: MobileAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(key: album.representative.artworkKey, size: 180, cornerRadius: 10, seed: album.title)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 3)
            Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contextMenu {
            SongMenu(songs: album.songs)
        }
    }
}

struct RecentlyAddedView: View {
    @EnvironmentObject var library: MobileLibrary

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                ForEach(library.recentlyAddedAlbums) { album in
                    NavigationLink(value: album) { AlbumGridCell(album: album) }.buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Recently Added")
    }
}

// MARK: - Albums

struct AlbumsView: View {
    @EnvironmentObject var library: MobileLibrary
    @State private var query = ""
    @AppStorage("albumSort") private var sort = "title"

    var body: some View {
        let albums = sorted(library.albums.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) })
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) { AlbumGridCell(album: album) }.buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Albums")
        .searchable(text: $query, prompt: "Find in Albums")
        .toolbar {
            Menu {
                Picker("Sort", selection: $sort) {
                    Text("Title").tag("title")
                    Text("Artist").tag("artist")
                    Text("Recently Added").tag("added")
                    Text("Release Year").tag("year")
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
        }
        .overlay { if library.albums.isEmpty { ContentUnavailableView("No Albums", systemImage: "square.stack", description: Text("Sync from your Mac to add music.")) } }
    }

    private func sorted(_ list: [MobileAlbum]) -> [MobileAlbum] {
        switch sort {
        case "artist": return list.sorted { ($0.artist, $0.title) < ($1.artist, $1.title) }
        case "added": return list.sorted { $0.dateAdded > $1.dateAdded }
        case "year": return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        default: return list
        }
    }
}

// MARK: - Artists

struct ArtistsView: View {
    @EnvironmentObject var library: MobileLibrary
    @State private var query = ""

    var body: some View {
        List(library.artists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { artist in
            NavigationLink(value: artist) {
                HStack(spacing: 12) {
                    ArtworkImage(key: artist.songs.first?.artworkKey, size: 48, cornerRadius: 24, seed: artist.name)
                        .frame(width: 48, height: 48)
                    Text(artist.name)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Artists")
        .searchable(text: $query, prompt: "Find in Artists")
    }
}

// MARK: - Songs & genres

struct SongsView: View {
    let title: String
    /// nil shows the whole library.
    let songs: [Song]?
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var query = ""
    @AppStorage("songSort") private var sort = "added"

    var body: some View {
        let base = songs ?? library.availableSongs
        let filtered = base.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) || $0.album.localizedCaseInsensitiveContains(query) }
        let list = sorted(filtered)
        List {
            Section {
                PlayShuffleButtons(songs: list)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
            }
            ForEach(list) { song in
                Button { player.play(list, startAt: song) } label: { SongRow(song: song, showsMenu: true) }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 14))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 68 }
                    .contextMenu { SongMenu(songs: [song]) }
                    .swipeActions(edge: .leading) {
                        Button { player.playNext([song]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }.tint(.indigo)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { library.removeSongs([song.id]) } label: { Label("Delete", systemImage: "trash") }
                        Button { library.toggleFavorite(song.id) } label: { Label("Favorite", systemImage: song.isFavorite ? "star.slash" : "star") }.tint(.pink)
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Find in \(title)")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Text("Title").tag("title")
                        Text("Artist").tag("artist")
                        Text("Recently Added").tag("added")
                        Text("Most Played").tag("plays")
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .tint(.primary)
                Menu {
                    Button { player.playNext(list) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                    Button { player.playLater(list) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
                } label: { Image(systemName: "ellipsis") }
                    .tint(.primary)
            }
        }
    }

    private func sorted(_ list: [Song]) -> [Song] {
        switch sort {
        case "artist": return list.sorted { ($0.artist, $0.title) < ($1.artist, $1.title) }
        case "added": return list.sorted { $0.info.dateAdded > $1.info.dateAdded }
        case "plays": return list.sorted { $0.playCount > $1.playCount }
        default: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

struct GenresView: View {
    @EnvironmentObject var library: MobileLibrary

    var body: some View {
        List(library.genres, id: \.name) { genre in
            NavigationLink {
                SongsView(title: genre.name, songs: genre.songs)
            } label: {
                HStack {
                    Text(genre.name)
                    Spacer()
                    Text("\(genre.songs.count)").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Genres")
    }
}

// MARK: - Playlists

struct GeneratedPlaylistCover: View {
    let title: String
    let artworkKey: String?
    @State private var colors: [Color]?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(white: 0.06), colors?.first ?? Color(white: 0.2), colors?.last ?? Color(white: 0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.45)
                Text(title)
                    .font(.system(size: geo.size.width * 0.13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .padding(geo.size.width * 0.08)
            }
        }
        .task(id: artworkKey) { colors = await ArtworkPalette.colors(for: artworkKey, darken: 0.7) }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject var library: MobileLibrary
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        List {
            Button { newName = ""; showNew = true } label: {
                Label("New Playlist…", systemImage: "plus").foregroundStyle(.tint)
            }
            ForEach(library.playlists) { playlist in
                NavigationLink(value: playlist) {
                    HStack(spacing: 12) {
                        Group {
                            if let key = playlist.artworkKey {
                                ArtworkImage(key: key, size: 56, cornerRadius: 8, seed: playlist.name)
                            } else {
                                PlaylistCoverView(songs: library.songs(of: playlist), isFavorites: playlist.isFavorites)
                            }
                        }
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                            Text(Format.songs(library.songs(of: playlist).count)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    if !playlist.isFavorites {
                        Button(role: .destructive) { library.deletePlaylist(playlist.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Playlists")
        .alert("New Playlist", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { if !newName.isEmpty { library.createPlaylist(name: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct PlaylistCoverView: View {
    let songs: [Song]
    var isFavorites = false
    /// When set, draws Apple Music's generated cover: the playlist's colors with its name on top.
    var title: String? = nil

    var body: some View {
        if let title, !isFavorites {
            GeneratedPlaylistCover(title: title, artworkKey: songs.first?.artworkKey)
        } else {
            mosaic
        }
    }

    private var mosaic: some View {
        var seen = Set<String>()
        let keys = songs.map(\.artworkKey).filter { seen.insert($0).inserted }.prefix(4)
        return GeometryReader { geo in
            let half = geo.size.width / 2
            ZStack {
                if keys.count >= 4 {
                    let k = Array(keys)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ArtworkImage(key: k[0], size: half, cornerRadius: 0).frame(width: half, height: half)
                            ArtworkImage(key: k[1], size: half, cornerRadius: 0).frame(width: half, height: half)
                        }
                        HStack(spacing: 0) {
                            ArtworkImage(key: k[2], size: half, cornerRadius: 0).frame(width: half, height: half)
                            ArtworkImage(key: k[3], size: half, cornerRadius: 0).frame(width: half, height: half)
                        }
                    }
                } else if let first = keys.first {
                    ArtworkImage(key: first, size: geo.size.width, cornerRadius: 0)
                } else {
                    LinearGradient(colors: isFavorites ? [.pink, .red] : [.gray.opacity(0.5), .gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: isFavorites ? "star.fill" : "music.note.list").font(.system(size: geo.size.width * 0.35)).foregroundStyle(.white))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AddSongsSheet: View {
    let playlistId: UUID
    @EnvironmentObject var library: MobileLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: [UUID] = []

    var body: some View {
        NavigationStack {
            List(library.availableSongs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }.sorted { $0.title < $1.title }) { song in
                Button {
                    if let i = selected.firstIndex(of: song.id) { selected.remove(at: i) } else { selected.append(song.id) }
                } label: {
                    HStack {
                        SongRow(song: song)
                        Image(systemName: selected.contains(song.id) ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(.tint).font(.title3)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query)
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        library.add(selected, to: playlistId)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
