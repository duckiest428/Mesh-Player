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
                    row("Playlists", icon: "music.note.list") { PlaylistsView() }
                    row("Artists", icon: "music.microphone") { ArtistsView() }
                    row("Albums", icon: "square.stack") { AlbumsView() }
                    row("Songs", icon: "music.note") { SongsView(title: "Songs", songs: nil) }
                    row("Genres", icon: "guitars") { GenresView() }
                    row("Favorites", icon: "star") {
                        if let favorites = library.playlists.first(where: \.isFavorites) { PlaylistView(playlistId: favorites.id) }
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

    private func row<Destination: View>(_ title: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 30)
                    Text(title).font(.title3).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
                Divider().padding(.leading, 44)
            }
        }
        .buttonStyle(.plain)
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

struct AlbumView: View {
    let album: MobileAlbum
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        let songs = library.albums.first(where: { $0.key == album.key })?.songs ?? album.songs
        let multiDisc = Set(songs.map(\.info.discNumber)).count > 1
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        ArtworkImage(key: album.representative.artworkKey, size: 280, cornerRadius: 12, seed: album.title)
                        MotionArtwork(song: album.representative)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(width: 270, height: 270)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    .padding(.top, 8)
                    VStack(spacing: 4) {
                        Text(album.title).font(.title2.bold()).multilineTextAlignment(.center)
                        NavigationLink(value: library.artists.first { $0.name == album.artist }) {
                            Text(album.artist).font(.title3).foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        Text([album.genre, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if let quality = album.representative.qualityLabel { QualityBadge(label: quality).padding(.top, 2) }
                    }
                    PlayShuffleButtons(songs: songs)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    VStack(alignment: .leading, spacing: 0) {
                        if multiDisc && (index == 0 || songs[index - 1].info.discNumber != song.info.discNumber) {
                            Text("Disc \(song.info.discNumber)").font(.subheadline.bold()).foregroundStyle(.secondary).padding(.vertical, 6)
                        }
                        Button { player.play(songs, startAt: song) } label: {
                            SongRow(song: song, number: song.info.trackNumber > 0 ? song.info.trackNumber : index + 1,
                                    subtitle: song.artist != album.artist ? song.artist : Format.time(song.duration))
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu { SongMenu(songs: [song]) }
                    .swipeActions(edge: .leading) {
                        Button { player.playNext([song]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }.tint(.indigo)
                    }
                    .swipeActions(edge: .trailing) {
                        Button { player.playLater([song]) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }.tint(.orange)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Format.songs(songs.count)), \(Format.length(songs.reduce(0) { $0 + $1.duration }))")
                    if let copyright = album.representative.info.copyright { Text(copyright) }
                }
                .font(.footnote)
                .padding(.top, 8)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                SongMenu(songs: songs)
            } label: { Image(systemName: "ellipsis") }
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

struct ArtistView: View {
    let artist: MobileArtist
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        let albums = library.albums.filter { $0.artist == artist.name }.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        let top = artist.songs.sorted { $0.playCount > $1.playCount }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(key: artist.songs.first?.artworkKey, size: 400, cornerRadius: 0, seed: artist.name)
                        .frame(height: 300)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    Text(artist.name).font(.largeTitle.bold()).foregroundStyle(.white).padding()
                }
                .frame(height: 300)

                PlayShuffleButtons(songs: artist.songs).padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Songs").font(.title2.bold()).padding(.horizontal)
                    ForEach(Array(top.prefix(6))) { song in
                        Button { player.play(top, startAt: song) } label: {
                            SongRow(song: song, subtitle: song.playCount > 0 ? "\(song.album) · \(song.playCount) play\(song.playCount == 1 ? "" : "s")" : song.album)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { SongMenu(songs: [song]) }
                    }
                }

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Albums").font(.title2.bold()).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(albums) { album in
                                    NavigationLink(value: album) { AlbumTile(album: album) }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
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
    @AppStorage("songSort") private var sort = "title"

    var body: some View {
        let base = songs ?? library.availableSongs
        let filtered = base.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) || $0.album.localizedCaseInsensitiveContains(query) }
        let list = sorted(filtered)
        List {
            Section {
                PlayShuffleButtons(songs: list)
                    .listRowSeparator(.hidden)
            }
            ForEach(list) { song in
                Button { player.play(list, startAt: song) } label: { SongRow(song: song) }
                    .buttonStyle(.plain)
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
            Menu {
                Picker("Sort", selection: $sort) {
                    Text("Title").tag("title")
                    Text("Artist").tag("artist")
                    Text("Recently Added").tag("added")
                    Text("Most Played").tag("plays")
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
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
                        PlaylistCoverView(songs: library.songs(of: playlist), isFavorites: playlist.isFavorites)
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

    var body: some View {
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

struct PlaylistView: View {
    let playlistId: UUID
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var showAddSongs = false
    @State private var renaming = false
    @State private var newName = ""
    @Environment(\.editMode) private var editMode

    var body: some View {
        if let playlist = library.playlists.first(where: { $0.id == playlistId }) {
            let songs = library.songs(of: playlist)
            List {
                Section {
                    VStack(spacing: 12) {
                        PlaylistCoverView(songs: songs, isFavorites: playlist.isFavorites)
                            .frame(width: 240, height: 240)
                            .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                        Text(playlist.name).font(.title2.bold())
                        if !playlist.description.isEmpty {
                            Text(playlist.description).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        Text("\(Format.songs(songs.count)) · \(Format.length(songs.reduce(0) { $0 + $1.duration }))")
                            .font(.caption).foregroundStyle(.secondary)
                        PlayShuffleButtons(songs: songs)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(songs) { song in
                        Button { player.play(songs, startAt: song) } label: { SongRow(song: song) }
                            .buttonStyle(.plain)
                            .contextMenu { SongMenu(songs: [song]) }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { songs[$0].id }
                        if playlist.isFavorites {
                            for id in ids { library.toggleFavorite(id) }
                        } else {
                            library.updatePlaylist(playlist.id) { p in p.songIds.removeAll { ids.contains($0) } }
                        }
                    }
                    .onMove(perform: playlist.isFavorites || playlist.isSmart ? nil : { from, to in
                        library.updatePlaylist(playlist.id) { $0.songIds.move(fromOffsets: from, toOffset: to) }
                    })
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !playlist.isSmart && !playlist.isFavorites {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !playlist.isSmart && !playlist.isFavorites {
                            Button { showAddSongs = true } label: { Label("Add Songs", systemImage: "plus") }
                            Button { newName = playlist.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        }
                        Button { player.playNext(songs) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { player.playLater(songs) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
                        if !playlist.isFavorites {
                            Divider()
                            Button(role: .destructive) { library.deletePlaylist(playlist.id) } label: { Label("Delete Playlist", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .sheet(isPresented: $showAddSongs) { AddSongsSheet(playlistId: playlist.id) }
            .alert("Rename Playlist", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { if !newName.isEmpty { library.updatePlaylist(playlist.id) { $0.name = newName } } }
                Button("Cancel", role: .cancel) {}
            }
            .overlay {
                if songs.isEmpty {
                    ContentUnavailableView(playlist.isFavorites ? "No Favorites Yet" : "Empty Playlist", systemImage: playlist.isFavorites ? "star" : "music.note.list",
                                           description: Text(playlist.isFavorites ? "Tap the star on a song to add it here." : "Add songs from the ••• menu."))
                        .padding(.top, 300)
                }
            }
        } else {
            ContentUnavailableView("Playlist Removed", systemImage: "music.note.list")
        }
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
