//
//  DetailPages.swift
//  Mesh Player iOS
//
//  Album, playlist and artist pages laid out like Apple Music on iOS: a centered cover, title and
//  artist, round Shuffle / Play / ••• buttons, a plain track list and a footer, over a background
//  tinted by the cover.
//

import SwiftUI

// MARK: - Shared header

/// Cover, title, subtitle and the Shuffle / Play / third-button row.
struct DetailHeader<Cover: View, Subtitle: View, Trailing: View>: View {
    let title: String
    let caption: String?
    let songs: [Song]
    @ViewBuilder let cover: () -> Cover
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let trailingButton: () -> Trailing
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        VStack(spacing: 0) {
            cover()
                .frame(width: 264, height: 264)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                .padding(.top, 8)
                .padding(.bottom, 22)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            subtitle()
                .padding(.top, 2)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            HStack(spacing: 16) {
                RoundButton(symbol: "shuffle") { player.play(songs, shuffled: true) }
                Button { player.play(songs) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(width: 180, height: 54)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                trailingButton()
            }
            .disabled(songs.isEmpty)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

struct RoundButton: View {
    let symbol: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.white.opacity(isOn ? 0.28 : 0.13), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

/// A row in an album or playlist: track number or cover, title, artist, and a ••• menu.
struct DetailTrackRow: View {
    let song: Song
    var number: Int? = nil
    var showArtist = true
    var extraMenu: (() -> AnyView)? = nil
    let onPlay: () -> Void
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        let isCurrent = player.current?.id == song.id
        HStack(spacing: 14) {
            if let number {
                Group {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(.tint)
                    } else {
                        Text("\(number)").foregroundStyle(.secondary)
                    }
                }
                .font(.body.monospacedDigit())
                .frame(width: 26, alignment: .leading)
            } else {
                ArtworkImage(key: song.artworkKey, size: 54, cornerRadius: 6, seed: song.album)
                    .frame(width: 54, height: 54)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.4))
                            Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: player.isPlaying).foregroundStyle(.white)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(number == nil ? .title3 : .body)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                if showArtist {
                    Text(song.artist)
                        .font(number == nil ? .body : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if song.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.tint)
            }
            Menu {
                SongMenu(songs: [song])
                if let extraMenu { extraMenu() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .tint(.primary)
        }
        .padding(.vertical, number == nil ? 8 : 13)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .contextMenu { SongMenu(songs: [song]) }
    }
}

// MARK: - Album

struct AlbumView: View {
    let album: MobileAlbum
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var catalog: CatalogAlbumInfo?
    @State private var showNotes = false

    var body: some View {
        let live = library.albums.first(where: { $0.key == album.key }) ?? album
        let songs = live.songs
        let multiDisc = Set(songs.map(\.info.discNumber)).count > 1
        let allFavorite = !songs.isEmpty && songs.allSatisfy(\.isFavorite)
        let artist = library.artists.first { $0.name == library.displayArtist(album.artist) }
        let others = library.albums.filter { $0.artist == album.artist && $0.key != album.key }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(title: album.title, caption: [album.genre, album.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty && !$0.hasPrefix("Unknown") }.joined(separator: " · "), songs: songs) {
                    ZStack {
                        ArtworkImage(key: album.representative.artworkKey, size: 264, cornerRadius: 0, seed: album.title)
                        MotionArtwork(song: album.representative)
                    }
                } subtitle: {
                    if let artist {
                        NavigationLink(value: artist) {
                            Text(album.artist).font(.title3).foregroundStyle(.primary).multilineTextAlignment(.center)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(album.artist).font(.title3).foregroundStyle(.primary).multilineTextAlignment(.center)
                    }
                } trailingButton: {
                    RoundButton(symbol: allFavorite ? "star.fill" : "star", isOn: allFavorite) {
                        for song in songs where song.isFavorite == allFavorite { library.toggleFavorite(song.id) }
                    }
                }

                if let notes = catalog?.notesShort ?? catalog?.notesStandard {
                    Button { showNotes = true } label: {
                        HStack(alignment: .lastTextBaseline) {
                            Text(notes).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            if catalog?.notesStandard != nil { Text("MORE").font(.caption.bold()).foregroundStyle(.tint) }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }

                if let quality = album.representative.qualityLabel {
                    QualityBadge(label: quality).frame(maxWidth: .infinity).padding(.top, 14)
                }

                Divider().padding(.top, 22).padding(.leading, 20)
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        if multiDisc && (index == 0 || songs[index - 1].info.discNumber != song.info.discNumber) {
                            Text("Disc \(song.info.discNumber)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, index == 0 ? 10 : 22)
                                .padding(.bottom, 4)
                        }
                        DetailTrackRow(song: song, number: song.info.trackNumber > 0 ? song.info.trackNumber : index + 1, showArtist: song.artist != album.artist) {
                            player.play(songs, startAt: song)
                        }
                        Divider().padding(.leading, 40)
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 3) {
                    if let date = releaseDate { Text(date) }
                    Text("\(Format.songs(songs.count)), \(Format.minutes(songs.reduce(0) { $0 + $1.duration }))")
                    if let copyright = songs.compactMap(\.info.copyright).first { Text(copyright) }
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if !others.isEmpty {
                    Divider().padding(.top, 24).padding(.leading, 20)
                    Text("More by \(album.artist)")
                        .font(.title3.bold())
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(others) { other in
                                NavigationLink(value: other) { AlbumTile(album: other, width: 150) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(ArtworkTintBackground(artworkKey: album.representative.artworkKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: "\(album.title) — \(album.artist)") { Image(systemName: "square.and.arrow.up") }
                    .tint(.primary)
                Menu { SongMenu(songs: songs) } label: { Image(systemName: "ellipsis") }
                    .tint(.primary)
            }
        }
        .sheet(isPresented: $showNotes) {
            NotesSheet(title: album.title, text: catalog?.notesStandard ?? catalog?.notesShort ?? "")
        }
        .task(id: album.key) {
            catalog = AppleMusicCatalog.shared.cachedAlbum(named: album.title, artist: album.artist)
            let fetched = await AppleMusicCatalog.shared.album(named: album.title, artist: album.artist)
            if fetched != catalog { withAnimation { catalog = fetched } }
        }
    }

    /// "August 2, 2024" from Apple Music when known, else the year.
    private var releaseDate: String? {
        if let raw = catalog?.releaseDate, let date = ISO8601DateFormatter.dateOnly.date(from: raw) {
            return date.formatted(date: .long, time: .omitted)
        }
        return album.year.map(String.init)
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

struct NotesSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(text).font(.body)
                    Text("Editor's notes from Apple Music").font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Playlist

struct PlaylistView: View {
    let playlistId: UUID
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var showAddSongs = false
    @State private var showReorder = false
    @State private var renaming = false
    @State private var confirmDelete = false
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let playlist = library.playlists.first(where: { $0.id == playlistId }) {
            let songs = library.songs(of: playlist)
            let editable = !playlist.isSmart && !playlist.isFavorites
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailHeader(title: playlist.name, caption: nil, songs: songs) {
                        if let key = playlist.artworkKey {
                            ArtworkImage(key: key, size: 264, cornerRadius: 0, seed: playlist.name)
                        } else {
                            PlaylistCoverView(songs: songs, isFavorites: playlist.isFavorites)
                        }
                    } subtitle: {
                        Text(updatedLine(playlist, count: songs.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } trailingButton: {
                        if editable {
                            RoundButton(symbol: "plus") { showAddSongs = true }
                        } else {
                            RoundButton(symbol: "text.line.last.and.arrowtriangle.forward") { player.playLater(songs) }
                        }
                    }

                    if !playlist.description.isEmpty && playlist.description != "Imported from Apple Music" {
                        Text(playlist.description)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    Divider().padding(.top, 16).padding(.leading, 20)
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            DetailTrackRow(song: song, extraMenu: editable || playlist.isFavorites ? {
                                AnyView(Button(role: .destructive) { remove(song, from: playlist) } label: {
                                    Label(playlist.isFavorites ? "Remove from Favorites" : "Remove from Playlist", systemImage: "minus.circle")
                                })
                            } : nil) {
                                player.play(songs, startAt: song)
                            }
                            Divider().padding(.leading, 68)
                        }
                    }
                    .padding(.horizontal, 20)

                    if !songs.isEmpty {
                        Text("\(Format.songs(songs.count)), \(Format.minutes(songs.reduce(0) { $0 + $1.duration }))")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(ArtworkTintBackground(artworkKey: playlist.artworkKey ?? songs.first?.artworkKey))
            .overlay {
                if songs.isEmpty {
                    ContentUnavailableView(playlist.isFavorites ? "No Favorites Yet" : "Empty Playlist", systemImage: playlist.isFavorites ? "star" : "music.note.list",
                                           description: Text(playlist.isFavorites ? "Tap the star on a song to add it here." : "Tap + to add songs."))
                        .padding(.top, 380)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { player.playNext(songs) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { player.playLater(songs) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
                        if editable {
                            Divider()
                            Button { showAddSongs = true } label: { Label("Add Songs", systemImage: "plus") }
                            Button { showReorder = true } label: { Label("Edit Order", systemImage: "arrow.up.arrow.down") }
                            Button { newName = playlist.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        }
                        if !playlist.isFavorites {
                            Divider()
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Playlist", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .tint(.primary)
                }
            }
            .sheet(isPresented: $showAddSongs) { AddSongsSheet(playlistId: playlist.id) }
            .sheet(isPresented: $showReorder) { ReorderPlaylistSheet(playlistId: playlist.id) }
            .alert("Rename Playlist", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { if !newName.isEmpty { library.updatePlaylist(playlist.id) { $0.name = newName } } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete “\(playlist.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Playlist", role: .destructive) {
                    library.deletePlaylist(playlist.id)
                    dismiss()
                }
            } message: {
                Text(playlist.createdHere == true
                     ? "It's also deleted on your Mac the next time you sync."
                     : "This playlist comes from your Mac, so it comes back the next time you sync. Delete it on the Mac to remove it for good.")
            }
        } else {
            ContentUnavailableView("Playlist Removed", systemImage: "music.note.list")
        }
    }

    private func updatedLine(_ playlist: MobilePlaylist, count: Int) -> String {
        if let modified = playlist.dateModified {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return "Updated \(f.localizedString(for: modified, relativeTo: Date()))"
        }
        return Format.songs(count)
    }

    private func remove(_ song: Song, from playlist: MobilePlaylist) {
        if playlist.isFavorites {
            library.toggleFavorite(song.id)
        } else {
            library.updatePlaylist(playlist.id) { p in p.songIds.removeAll { $0 == song.id } }
        }
    }
}

struct ReorderPlaylistSheet: View {
    let playlistId: UUID
    @EnvironmentObject var library: MobileLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let playlist = library.playlists.first(where: { $0.id == playlistId }) {
                    let songs = library.songs(of: playlist)
                    ForEach(songs) { song in SongRow(song: song) }
                        .onMove { from, to in library.updatePlaylist(playlistId) { $0.songIds.move(fromOffsets: from, toOffset: to) } }
                        .onDelete { offsets in
                            let ids = offsets.map { songs[$0].id }
                            library.updatePlaylist(playlistId) { p in p.songIds.removeAll { ids.contains($0) } }
                        }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Artist

struct ArtistView: View {
    let artist: MobileArtist
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var catalog: CatalogArtistInfo?

    var body: some View {
        let name = artist.name
        let live = library.artists.first { $0.name == name } ?? artist
        let songs = live.songs
        let albums = library.albums.filter { library.displayArtist($0.artist) == name }.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        let isSingle: (MobileAlbum) -> Bool = { $0.title.hasSuffix(" - Single") || $0.title.hasSuffix(" - EP") || $0.songs.count <= 2 }
        let fullAlbums = albums.filter { !isSingle($0) }, singles = albums.filter(isSingle)
        let top = songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }
        let lower = name.lowercased()
        let appearsOn = library.albums.filter { album in
            library.displayArtist(album.artist) != name && album.songs.contains { $0.artist.lowercased().contains(lower) }
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack(alignment: .bottom) {
                    banner
                        .frame(height: 360)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 14) {
                        Text(name)
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        HStack(spacing: 16) {
                            RoundButton(symbol: "shuffle") { player.play(songs, shuffled: true) }
                            Button { player.play(songs) } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.title3.weight(.semibold)).foregroundStyle(.black)
                                    .frame(width: 160, height: 54).background(.white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            if library.isFavoriteArtist(name) {
                                RoundButton(symbol: "heart.fill", isOn: true) {}
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                    .padding(.horizontal)
                }
                .frame(height: 360)

                if !top.isEmpty {
                    section("Top Songs") {
                        VStack(spacing: 0) {
                            ForEach(Array(top.prefix(5))) { song in
                                DetailTrackRow(song: song) { player.play(top, startAt: song) }
                                Divider().padding(.leading, 68)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                albumShelf("Albums", fullAlbums)
                albumShelf("Singles & EPs", singles)
                albumShelf("Appears On", appearsOn)

                if let essentials = catalog?.essentialAlbums, !essentials.isEmpty {
                    section("Essential Albums") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(essentials) { item in
                                    EssentialTile(item: item, local: localAlbum(item))
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if let bio = catalog?.bio, !bio.isEmpty {
                    section("About") {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: name) {
            catalog = AppleMusicCatalog.shared.cachedArtist(named: name)
            let fetched = await AppleMusicCatalog.shared.artist(named: name)
            if fetched != catalog { withAnimation { catalog = fetched } }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let url = catalog?.bannerURL(width: 1200) ?? catalog?.artworkURL(1000) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                fallbackBanner
            }
        } else {
            fallbackBanner
        }
    }

    private var fallbackBanner: some View {
        ArtworkImage(key: artist.songs.first?.artworkKey, size: 400, cornerRadius: 0, seed: artist.name)
            .blur(radius: 30)
            .scaleEffect(1.3)
    }

    private func localAlbum(_ item: CatalogAlbumInfo) -> MobileAlbum? {
        let wanted = AnimatedArtworkService.normalize(item.name)
        return library.albums.first { AnimatedArtworkService.normalize($0.title).caseInsensitiveCompare(wanted) == .orderedSame }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold()).padding(.horizontal)
            content()
        }
    }

    @ViewBuilder
    private func albumShelf(_ title: String, _ albums: [MobileAlbum]) -> some View {
        if !albums.isEmpty {
            section(title) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkImage(key: album.representative.artworkKey, size: 160, cornerRadius: 10, seed: album.title)
                                        .frame(width: 160, height: 160)
                                    Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(album.year.map(String.init) ?? album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 160, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct EssentialTile: View {
    let item: CatalogAlbumInfo
    let local: MobileAlbum?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: item.artworkURL(500)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkImage.Placeholder(seed: item.name)
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(item.notesShort ?? item.year ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if local == nil {
                Label("Not in your library", systemImage: "arrow.down.circle").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 220, alignment: .leading)

        if let local {
            NavigationLink(value: local) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}
