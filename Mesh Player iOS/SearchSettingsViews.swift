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
    @State private var scope = 0

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
        .searchable(text: $query, prompt: "Songs, Artists, Albums, Playlists")
        .searchScopes($scope) {
            Text("All").tag(0)
            Text("Songs").tag(1)
            Text("Albums").tag(2)
            Text("Artists").tag(3)
        }
        .libraryDestinations()
    }

    private var results: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let songs = library.availableSongs.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) || $0.album.localizedCaseInsensitiveContains(q) }
        let albums = library.albums.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
        let artists = library.artists.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let playlists = library.playlists.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return List {
            if scope == 0 || scope == 3, !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists.prefix(scope == 0 ? 3 : 100)) { artist in
                        NavigationLink(value: artist) {
                            HStack(spacing: 12) {
                                ArtworkImage(key: artist.songs.first?.artworkKey, size: 44, cornerRadius: 22, seed: artist.name).frame(width: 44, height: 44)
                                Text(artist.name)
                            }
                        }
                    }
                }
            }
            if scope == 0 || scope == 2, !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums.prefix(scope == 0 ? 4 : 200)) { album in
                        NavigationLink(value: album) {
                            HStack(spacing: 12) {
                                ArtworkImage(key: album.representative.artworkKey, size: 48, cornerRadius: 6, seed: album.title).frame(width: 48, height: 48)
                                VStack(alignment: .leading) {
                                    Text(album.title).lineLimit(1)
                                    Text(album.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if scope == 0, !playlists.isEmpty {
                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) { Label(playlist.name, systemImage: "music.note.list") }
                    }
                }
            }
            if scope == 0 || scope == 1, !songs.isEmpty {
                Section("Songs") {
                    ForEach(songs.prefix(scope == 0 ? 25 : 500)) { song in
                        Button { player.play(songs, startAt: song) } label: { SongRow(song: song) }
                            .buttonStyle(.plain)
                            .contextMenu { SongMenu(songs: [song]) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty {
                ContentUnavailableView.search(text: q)
            }
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
