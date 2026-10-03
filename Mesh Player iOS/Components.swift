//
//  Components.swift
//  Mesh Player iOS
//
//  Shared building blocks: artwork, song rows, context menus, motion artwork and the mini player.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Artwork

struct ArtworkImage: View {
    let key: String?
    var size: CGFloat = 60
    var cornerRadius: CGFloat = 6
    var seed: String = ""

    @State private var image: UIImage?
    @State private var reload = 0
    private var cache: ArtworkCache { .shared }

    var body: some View {
        ZStack {
            if let shown = image ?? key.flatMap({ cache.cached($0, size: size) }) {
                Image(uiImage: shown).resizable().scaledToFill()
            } else {
                Placeholder(seed: seed.isEmpty ? (key ?? "") : seed)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .task(id: "\(key ?? "")#\(reload)") {
            guard let key else { image = nil; return }
            image = await cache.image(key, size: size)
        }
        .onReceive(cache.changes) { keys in
            // Reload only when this cover's file changed (nil = everything changed).
            guard let key, keys?.contains(key) ?? true else { return }
            image = nil
            reload &+= 1
        }
    }

    struct Placeholder: View {
        let seed: String
        private static let palettes: [[Color]] = [
            [Color(red: 0.95, green: 0.33, blue: 0.45), Color(red: 0.55, green: 0.18, blue: 0.62)],
            [Color(red: 0.28, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.18, blue: 0.55)],
            [Color(red: 0.99, green: 0.60, blue: 0.25), Color(red: 0.85, green: 0.22, blue: 0.32)],
            [Color(red: 0.22, green: 0.78, blue: 0.68), Color(red: 0.13, green: 0.35, blue: 0.55)],
            [Color(red: 0.62, green: 0.45, blue: 1.00), Color(red: 0.30, green: 0.18, blue: 0.60)]
        ]
        var body: some View {
            let colors = Self.palettes[Int(UInt(bitPattern: seed.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }) % UInt(Self.palettes.count))]
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: max(10, geo.size.width * 0.34), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}

// MARK: - Motion artwork

/// Streams Apple Music motion artwork, muted and looping; transparent until the first frame.
struct MotionArtworkView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.currentURL != url { view.play(url) }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var player: AVPlayer?
        private var loop: NSObjectProtocol?
        private var ready: NSKeyValueObservation?
        private(set) var currentURL: URL?

        func play(_ url: URL) {
            stop()
            currentURL = url
            isUserInteractionEnabled = false
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.opacity = 0
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            // Don't interrupt the music that's playing.
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            player.preventsDisplaySleepDuringVideoPlayback = false
            self.player = player
            playerLayer.player = player
            ready = playerLayer.observe(\.isReadyForDisplay) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.6) { layer.opacity = 1 }
                }
            }
            loop = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            player.play()
        }

        func stop() {
            player?.pause()
            player = nil
            playerLayer.player = nil
            ready = nil
            if let loop { NotificationCenter.default.removeObserver(loop) }
            loop = nil
            currentURL = nil
        }
    }
}

/// Looks up the album's motion artwork once and shows it when the setting is on.
struct MotionArtwork: View {
    let song: Song?
    var tall = false
    @AppStorage("animatedArtwork") private var enabled = true
    @State private var url: URL?

    var body: some View {
        ZStack {
            if enabled, let url { MotionArtworkView(url: url) }
        }
        .task(id: song?.artworkKey) {
            url = nil
            guard enabled, let song else { return }
            let videos = await AnimatedArtworkService.shared.videos(key: song.artworkKey, album: song.album, artist: song.albumArtist, localFolder: nil)
            url = tall ? videos.tall : videos.square
        }
    }
}

// MARK: - Songs

struct SongRow: View {
    let song: Song
    var showArtwork = true
    var number: Int? = nil
    var subtitle: String? = nil
    /// Adds the ••• menu at the end of the row, like Apple Music's song lists.
    var showsMenu = false
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
                .font(.subheadline.monospacedDigit())
                .frame(width: 24)
            } else if showArtwork {
                ArtworkImage(key: song.artworkKey, size: 54, cornerRadius: 6, seed: song.album)
                    .frame(width: 54, height: 54)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45))
                            Image(systemName: "waveform")
                                .font(.title3.weight(.semibold))
                                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                .foregroundStyle(.white)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(song.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if song.info.isAtmos {
                        QualityLogoImage(logo: .dolbyIcon, height: 10).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle ?? song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if song.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.tint)
            }
            if showsMenu {
                Menu { SongMenu(songs: [song]) } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .tint(.primary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Apple Music's long-press menu for songs.
struct SongMenu: View {
    let songs: [Song]
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var showNewPlaylist = false

    var body: some View {
        if let first = songs.first {
            Button { player.playNext(songs) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { player.playLater(songs) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
            Divider()
            Menu {
                ForEach(library.playlists.filter { !$0.isSmart && !$0.isFavorites }) { playlist in
                    Button(playlist.name) { library.add(songs.map(\.id), to: playlist.id) }
                }
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            if songs.count == 1 {
                Button { library.toggleFavorite(first.id) } label: {
                    Label(first.isFavorite ? "Undo Favorite" : "Favorite", systemImage: first.isFavorite ? "star.slash" : "star")
                }
                ShareLink(item: "\(first.title) — \(first.artist)") { Label("Share Song", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

// MARK: - Mini player

struct MiniPlayer: View {
    @EnvironmentObject var player: MobilePlayer
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(key: player.current?.artworkKey, size: 34, cornerRadius: 6, seed: player.current?.album ?? "")
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.current?.title ?? "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if placement != .inline {
                    Text(player.current?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
            }
            if placement != .inline {
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 36, height: 36)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - Misc

struct PlayShuffleButtons: View {
    let songs: [Song]
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        HStack(spacing: 16) {
            button("Play", symbol: "play.fill") { player.play(songs) }
            button("Shuffle", symbol: "shuffle") { player.play(songs, shuffled: true) }
        }
        .disabled(songs.isEmpty)
    }

    /// Apple Music's gray capsule buttons with a white label.
    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.fill.tertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct QualityBadge: View {
    let label: String

    var body: some View {
        Group {
            if label == "Dolby Atmos" {
                QualityLogoImage(logo: .dolbyAtmos, height: 9)
                    .padding(.vertical, 1.5)
            } else {
                HStack(spacing: 4) {
                    if label.localizedCaseInsensitiveContains("lossless") {
                        QualityLogoImage(logo: .lossless, height: 8)
                    }
                    Text(label)
                }
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

enum Format {
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func length(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(max(1, minutes)) min"
    }

    static func songs(_ n: Int) -> String { "\(n) song\(n == 1 ? "" : "s")" }

    /// "12 hr 30 min" / "45 min" for listening totals.
    static func listening(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }

    /// "1 hour, 4 minutes" / "3 minutes", as Apple Music writes album lengths.
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        if total >= 60 {
            let h = total / 60, m = total % 60
            return "\(h) hour\(h == 1 ? "" : "s")" + (m > 0 ? ", \(m) minute\(m == 1 ? "" : "s")" : "")
        }
        let shown = max(1, total)
        return "\(shown) minute\(shown == 1 ? "" : "s")"
    }

    static func relative(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "today" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
