//
//  HomeView.swift
//  Mesh Player iOS
//
//  Apple Music-style Home built only from real listening data.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var showSettings = false
    @State private var showImporter = false

    var body: some View {
        let songs = library.availableSongs
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if songs.isEmpty {
                    EmptyLibraryCard(showImporter: $showImporter)
                        .padding(.horizontal)
                } else {
                    let recent = songs.filter { $0.info.lastPlayedDate != nil }
                        .sorted { $0.info.lastPlayedDate! > $1.info.lastPlayedDate! }
                    if !recent.isEmpty {
                        shelf("Recently Played") {
                            ForEach(Array(recent.prefix(15))) { song in
                                SongTile(song: song, caption: "Played \(Format.relative(song.info.lastPlayedDate!))") {
                                    player.play(Array(recent.prefix(15)), startAt: song)
                                }
                            }
                        }
                    }

                    let albums = Array(library.recentlyAddedAlbums.prefix(12))
                    if !albums.isEmpty {
                        shelf("Recently Added", destination: AnyView(RecentlyAddedView())) {
                            ForEach(albums) { album in
                                NavigationLink(value: album) { AlbumTile(album: album) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    let most = songs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }
                    if !most.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            header("Most Played")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHGrid(rows: Array(repeating: GridItem(.fixed(56), spacing: 8), count: 4), spacing: 18) {
                                    ForEach(Array(most.prefix(16))) { song in
                                        Button { player.play(Array(most.prefix(16)), startAt: song) } label: {
                                            SongRow(song: song, subtitle: "\(song.artist) · \(song.playCount) play\(song.playCount == 1 ? "" : "s")")
                                                .frame(width: 300)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu { SongMenu(songs: [song]) }
                                    }
                                }
                                .padding(.horizontal)
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                        }
                    }

                    let favorites = songs.filter(\.isFavorite).shuffled()
                    if !favorites.isEmpty {
                        shelf("From Your Favorites") {
                            ForEach(Array(favorites.prefix(12))) { song in
                                SongTile(song: song, caption: song.artist) { player.play(favorites, startAt: song) }
                            }
                        }
                    }

                    let now = Date()
                    let rediscover = songs.filter { s in
                        guard s.playCount >= 3, let last = s.info.lastPlayedDate else { return false }
                        return now.timeIntervalSince(last) > 60 * 86_400
                    }
                    if !rediscover.isEmpty {
                        shelf("Not Played in a While") {
                            ForEach(Array(rediscover.shuffled().prefix(12))) { song in
                                SongTile(song: song, caption: "Last played \(Format.relative(song.info.lastPlayedDate!))") { player.play(rediscover, startAt: song) }
                            }
                        }
                    }

                    let unplayed = songs.filter { $0.playCount == 0 }.sorted { $0.info.dateAdded > $1.info.dateAdded }
                    if !unplayed.isEmpty {
                        shelf("Not Played Yet") {
                            ForEach(Array(unplayed.prefix(12))) { song in
                                SongTile(song: song, caption: "Added \(Format.relative(song.info.dateAdded))") { player.play(Array(unplayed.prefix(30)), startAt: song) }
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Home")
        .libraryDestinations()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.importFiles(urls, move: false) }
        }
    }

    private func header(_ title: String, destination: AnyView? = nil) -> some View {
        HStack {
            if let destination {
                NavigationLink { destination } label: {
                    HStack(spacing: 4) {
                        Text(title).font(.title2.bold()).foregroundStyle(.primary)
                        Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(title).font(.title2.bold())
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func shelf<Content: View>(_ title: String, destination: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title, destination: destination)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) { content() }
                    .padding(.horizontal)
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

struct SongTile: View {
    let song: Song
    let caption: String
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(key: song.artworkKey, size: 160, cornerRadius: 10, seed: song.album)
                    .frame(width: 160, height: 160)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                Text(song.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu { SongMenu(songs: [song]) }
    }
}

struct AlbumTile: View {
    let album: MobileAlbum
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(key: album.representative.artworkKey, size: width, cornerRadius: 10, seed: album.title)
                .frame(width: width, height: width)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct EmptyLibraryCard: View {
    @Binding var showImporter: Bool
    @EnvironmentObject var sync: SyncServer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Get your music on iPhone").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open Mesh Player on your Mac.")
                step(2, "Choose Add Music › Sync iPhone…")
                step(3, "Pick this iPhone. Use the same Wi-Fi, or connect with a USB cable.")
            }
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.footnote).foregroundStyle(.secondary)
            }
            LocalNetworkNotice()
            Divider()
            Button {
                showImporter = true
            } label: {
                Label("Add Songs from Files", systemImage: "folder")
            }
            Text("You can also drag songs onto Mesh Player in Finder › your iPhone › Files.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.footnote.bold()).frame(width: 22, height: 22).background(.tint.opacity(0.18), in: Circle())
            Text(text).font(.subheadline)
        }
    }

    private var statusColor: Color {
        if case .ready = sync.status { return .green }
        if case .unavailable = sync.status { return .orange }
        return .gray
    }

    private var statusText: String {
        switch sync.status {
        case .ready: return "Ready — waiting for your Mac"
        case .unavailable(let reason): return "Sync unavailable: \(reason)"
        case .syncing(let text): return text
        default: return "Starting…"
        }
    }
}
