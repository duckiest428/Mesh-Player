//
//  SearchSettingsViews.swift
//  Mesh Player iOS
//

import SwiftUI
internal import UniformTypeIdentifiers

extension View {
    /// Navigation targets shared by every tab.
    func libraryDestinations() -> some View {
        self
            .navigationDestination(for: MobileAlbum.self) { AlbumView(album: $0) }
            .navigationDestination(for: MobileArtist.self) { ArtistView(artist: $0) }
            .navigationDestination(for: MobilePlaylist.self) { PlaylistView(playlistId: $0.id) }
            .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var query = ""
    @State private var scope: Scope = .top

    enum Scope: String, CaseIterable, Identifiable {
        case top = "Top Results"
        case albums = "Albums"
        case songs = "Songs"
        case artists = "Artists"
        case playlists = "Playlists"
        var id: String { rawValue }
    }

    private static let tints: [Color] = [.pink, .orange, .purple, .blue, .teal, .indigo, .red, .green, .mint, .cyan]

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Browse Your Genres").font(.title2.bold()).padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(Array(library.genres.enumerated()), id: \.element.name) { index, genre in
                                NavigationLink {
                                    SongsView(title: genre.name, songs: genre.songs)
                                } label: {
                                    GenreTile(name: genre.name, songs: genre.songs, tint: Self.tints[index % Self.tints.count])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            } else {
                results
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search Your Library")
        .libraryDestinations()
    }

    // MARK: Results

    enum Item: Identifiable {
        case song(Song), album(MobileAlbum), artist(MobileArtist), playlist(MobilePlaylist)

        var id: String {
            switch self {
            case .song(let s): return "s" + s.id.uuidString
            case .album(let a): return "a" + a.key
            case .artist(let a): return "r" + a.name
            case .playlist(let p): return "p" + p.id.uuidString
            }
        }
    }

    private var results: some View {
        let ranked = rankedItems(query.trimmingCharacters(in: .whitespaces))
        let shown = ranked.filter { item in
            switch (scope, item) {
            case (.top, _): return true
            case (.albums, .album), (.songs, .song), (.artists, .artist), (.playlists, .playlist): return true
            default: return false
            }
        }
        let songs: [Song] = shown.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Scope.allCases) { option in
                        Button { withAnimation(.snappy) { scope = option } } label: {
                            Text(option.rawValue)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(scope == option ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(scope == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
            List {
                ForEach(Array((scope == .top ? Array(shown.prefix(60)) : shown).enumerated()), id: \.element.id) { _, item in
                    SearchResultRow(item: item, playQueue: songs)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 16))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 84 }
                }
            }
            .listStyle(.plain)
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
    }

    /// Library matches, best first: the name starts with the query, then a word in it does,
    /// then it appears anywhere; albums and artists before songs on ties.
    private func rankedItems(_ q: String) -> [Item] {
        let lower = q.lowercased()
        func rank(_ text: String) -> Int? {
            let t = text.lowercased()
            if t.hasPrefix(lower) { return 0 }
            if t.contains(" " + lower) || t.contains("(" + lower) { return 1 }
            return t.contains(lower) ? 2 : nil
        }
        var scored: [(Item, Int)] = []
        for artist in library.artists { if let r = rank(artist.name) { scored.append((.artist(artist), r * 10)) } }
        for album in library.albums {
            if let r = rank(album.title) { scored.append((.album(album), r * 10 + 1)) }
            else if let r = rank(album.artist) { scored.append((.album(album), 30 + r * 10 + 1)) }
        }
        for song in library.availableSongs {
            if let r = rank(song.title) { scored.append((.song(song), r * 10 + 2)) }
            else if let r = rank(song.artist) ?? rank(song.album) { scored.append((.song(song), 30 + r * 10 + 2)) }
        }
        for playlist in library.playlists { if let r = rank(playlist.name) { scored.append((.playlist(playlist), r * 10 + 3)) } }
        return scored.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

/// One search result, laid out like Apple Music's: cover, title, "Kind · Artist", and a chevron
/// (albums, artists, playlists) or ••• menu (songs).
private struct SearchResultRow: View {
    let item: SearchView.Item
    let playQueue: [Song]
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        switch item {
        case .song(let song):
            HStack(spacing: 14) {
                ArtworkImage(key: song.artworkKey, size: 64, cornerRadius: 6, seed: song.album).frame(width: 64, height: 64)
                text(song.title, "Song · \(song.artist)")
                Spacer(minLength: 4)
                Menu { SongMenu(songs: [song]) } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.primary).frame(width: 34, height: 34)
                }
                .tint(.primary)
            }
            .overlay(alignment: .leading) {
                if song.isFavorite {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).offset(x: -16)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { player.play(playQueue, startAt: song) }
            .contextMenu { SongMenu(songs: [song]) }
        case .album(let album):
            NavigationLink(value: album) {
                HStack(spacing: 14) {
                    ArtworkImage(key: album.representative.artworkKey, size: 64, cornerRadius: 6, seed: album.title).frame(width: 64, height: 64)
                    text(album.title, "Album · \(album.artist)")
                }
            }
            .contextMenu { SongMenu(songs: album.songs) }
        case .artist(let artist):
            NavigationLink(value: artist) {
                HStack(spacing: 14) {
                    ArtworkImage(key: artist.songs.first?.artworkKey, size: 64, cornerRadius: 32, seed: artist.name).frame(width: 64, height: 64)
                    text(artist.name, "Artist")
                }
            }
        case .playlist(let playlist):
            NavigationLink(value: playlist) {
                HStack(spacing: 14) {
                    Group {
                        if let key = playlist.artworkKey {
                            ArtworkImage(key: key, size: 64, cornerRadius: 6, seed: playlist.name)
                        } else {
                            PlaylistCoverView(songs: library.songs(of: playlist), isFavorites: playlist.isFavorites)
                        }
                    }
                    .frame(width: 64, height: 64)
                    text(playlist.name, "Playlist")
                }
            }
        }
    }

    private func text(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3).lineLimit(1)
            Text(subtitle).font(.body).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct GenreTile: View {
    let name: String
    let songs: [Song]
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(tint.gradient)
            ArtworkImage(key: songs.first?.artworkKey, size: 70, cornerRadius: 6)
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(18))
                .offset(x: 12, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundStyle(.white).lineLimit(2)
                Text(Format.songs(songs.count)).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            .padding(12)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var sync: SyncServer
    @Environment(\.dismiss) private var dismiss
    @AppStorage("animatedArtwork") private var animatedArtwork = true
    @AppStorage("spatializeStereo") private var spatializeStereo = false
    @State private var showImporter = false
    @State private var confirmRemoveAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "macbook.and.iphone").font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusTitle).font(.headline)
                            Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if sync.localNetworkDenied { LocalNetworkNotice() }
                    if let last = library.lastSync {
                        LabeledContent("Last sync", value: "\(Format.relative(last))\(library.lastSyncSource.map { " from \($0)" } ?? "")")
                    }
                } header: {
                    Text("Sync with Mac")
                } footer: {
                    Text("On your Mac, open Mesh Player and choose Add Music › Sync iPhone. Works over Wi-Fi or a USB cable. Plays, favorites and playlists you make here go back to the Mac.")
                }

                if !library.trustedMacs.isEmpty {
                    Section("Allowed Macs") {
                        ForEach(library.trustedMacs.sorted(by: { $0.value < $1.value }), id: \.key) { id, name in
                            Label(name, systemImage: "laptopcomputer")
                                .swipeActions {
                                    Button("Forget", role: .destructive) { library.forget(id) }
                                }
                        }
                    }
                }

                Section {
                    Button { showImporter = true } label: { Label("Add Songs from Files…", systemImage: "folder.badge.plus") }
                } header: {
                    Text("Add Music")
                } footer: {
                    Text("You can also drag songs onto Mesh Player in Finder › your iPhone › Files; they're added the next time the app opens.")
                }

                Section("Playback") {
                    Toggle("Animated Artwork", isOn: $animatedArtwork)
                    Toggle("Spatialize Stereo", isOn: $spatializeStereo)
                }

                Section("Storage") {
                    LabeledContent("Songs", value: "\(library.availableSongs.count)")
                    LabeledContent("Albums", value: "\(library.albums.count)")
                    LabeledContent("Space used", value: ByteCountFormatter.string(fromByteCount: library.totalBytes, countStyle: .file))
                    Button("Remove All Music…", role: .destructive) { confirmRemoveAll = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.importFiles(urls, move: false) }
            }
            .confirmationDialog("Remove all music from this iPhone?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                Button("Remove All Music", role: .destructive) {
                    MobilePlayer.shared.pause()
                    library.removeAllMusic()
                }
            } message: {
                Text("Songs and playlists are deleted from this iPhone. Your Mac library isn't affected; sync again to bring them back.")
            }
        }
    }

    private var statusTitle: String {
        switch sync.status {
        case _ where sync.localNetworkDenied: return "Local Network is off"
        case .ready: return "Ready to sync"
        case .syncing: return "Syncing…"
        case .finished: return "Sync complete"
        case .failed: return "Last sync failed"
        case .unavailable: return "Sync unavailable"
        case .stopped: return "Starting…"
        }
    }

    private var statusDetail: String {
        switch sync.status {
        case _ where sync.localNetworkDenied: return "Macs can see this iPhone but can't connect."
        case .ready: return "Visible to Macs on this network and over USB as “\(UIDevice.current.name)”."
        case .syncing(let text): return text
        case .finished(let summary): return summary
        case .failed(let message): return message
        case .unavailable(let reason): return "\(reason). Allow Local Network access for Mesh Player in Settings › Privacy & Security."
        case .stopped: return ""
        }
    }
}
