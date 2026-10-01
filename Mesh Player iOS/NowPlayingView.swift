//
//  NowPlayingView.swift
//  Mesh Player iOS
//
//  Full screen player: artwork (with motion artwork), scrubber, transport, volume, AirPlay,
//  synced lyrics and the Up Next queue — on a background tinted by the album art.
//

import AVKit
import MediaPlayer
import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject var player: MobilePlayer
    @EnvironmentObject var library: MobileLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var panel: Panel = .artwork
    @State private var colors: [Color] = [Color(white: 0.2), Color(white: 0.08)]
    @State private var dragOffset: CGFloat = 0
    /// Full-screen (tall) motion artwork for the current album, when Apple Music has one.
    @State private var tallVideo: URL?
    @AppStorage("animatedArtwork") private var animatedArtwork = true

    private var showsTallArtwork: Bool { animatedArtwork && tallVideo != nil && panel == .artwork }

    enum Panel { case artwork, lyrics, queue }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.8), value: colors)

                if animatedArtwork, let tallVideo {
                    // Like Apple Music: the tall video fills the screen behind the controls.
                    MotionArtworkView(url: tallVideo)
                        .ignoresSafeArea()
                        .overlay {
                            LinearGradient(stops: [
                                .init(color: .black.opacity(0.35), location: 0),
                                .init(color: .clear, location: 0.18),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black.opacity(0.8), location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                        }
                        .opacity(panel == .artwork ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.4), value: panel)
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Capsule().fill(.white.opacity(0.4)).frame(width: 38, height: 5).padding(.top, 8)

                    Group {
                        switch panel {
                        case .artwork:
                            if showsTallArtwork {
                                Spacer(minLength: 0)
                            } else {
                                artwork(width: min(geo.size.width - 48, 380))
                                    .frame(maxHeight: .infinity)
                            }
                        case .lyrics:
                            compactHeader.padding(.top, 20)
                            LyricsPanel()
                        case .queue:
                            compactHeader.padding(.top, 20)
                            QueuePanel()
                        }
                    }
                    .transition(.opacity)

                    controls
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)
                }
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in if value.translation.height > 0 && panel == .artwork { dragOffset = value.translation.height } }
                    .onEnded { value in
                        if value.translation.height > 140 { dismiss() }
                        withAnimation(.spring) { dragOffset = 0 }
                    }
            )
        }
        .environment(\.colorScheme, .dark)
        .task(id: player.current?.artworkKey) { await updateColors() }
        .task(id: player.current?.artworkKey) {
            guard animatedArtwork, let song = player.current else { tallVideo = nil; return }
            let videos = await AnimatedArtworkService.shared.videos(key: song.artworkKey, album: song.album, artist: song.albumArtist, localFolder: nil)
            withAnimation(.easeInOut(duration: 0.5)) { tallVideo = videos.tall }
        }
    }

    // MARK: Artwork

    private func artwork(width: CGFloat) -> some View {
        let song = player.current
        return ZStack {
            ArtworkImage(key: song?.artworkKey, size: width, cornerRadius: 14, seed: song?.album ?? "")
            MotionArtwork(song: song)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: width, height: width)
        .scaleEffect(player.isPlaying ? 1 : 0.82)
        .shadow(color: .black.opacity(player.isPlaying ? 0.45 : 0.25), radius: player.isPlaying ? 30 : 12, y: player.isPlaying ? 16 : 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: player.isPlaying)
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            ArtworkImage(key: player.current?.artworkKey, size: 64, cornerRadius: 8, seed: player.current?.album ?? "")
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "").font(.headline).lineLimit(1)
                Text(player.current?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 22) {
            if panel == .artwork {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.current?.title ?? "Not Playing")
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text(player.current?.artist ?? "")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                    if let song = player.current {
                        let isFavorite = library.song(song.id)?.isFavorite ?? false
                        Button { library.toggleFavorite(song.id) } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.14), in: Circle())
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Menu {
                            SongMenu(songs: [song])
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.14), in: Circle())
                        }
                    }
                }
            }

            Scrubber()

            HStack {
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 32)) }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 46))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 70, height: 70)
                }
                Spacer()
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 32)) }
                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.caption)
                SystemVolumeSlider().frame(height: 30)
                Image(systemName: "speaker.wave.3.fill").font(.caption)
            }
            .foregroundStyle(.white.opacity(0.6))

            HStack {
                panelButton(.lyrics, icon: "quote.bubble")
                    .disabled(player.lyrics.isEmpty)
                Spacer()
                RoutePicker().frame(width: 44, height: 44)
                Spacer()
                panelButton(.queue, icon: "list.bullet")
            }
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func panelButton(_ target: Panel, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { panel = panel == target ? .artwork : target }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(panel == target ? .white.opacity(0.22) : .clear, in: Circle())
        }
    }

    // MARK: Background colors

    private func updateColors() async {
        guard let key = player.current?.artworkKey, let image = await ArtworkCache.shared.image(key, size: 60) else { return }
        let extracted = await Task.detached(priority: .utility) { Self.dominantColors(image) }.value
        if let extracted { colors = extracted }
    }

    nonisolated private static func dominantColors(_ image: UIImage) -> [Color]? {
        guard let cg = image.cgImage else { return nil }
        let width = 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        func average(rows: Range<Int>) -> Color {
            var r = 0, g = 0, b = 0, n = 0
            for y in rows { for x in 0..<width { let i = (y * width + x) * 4; r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2]); n += 1 } }
            // Darken a little so white text always reads.
            return Color(red: Double(r) / Double(n) / 255 * 0.75, green: Double(g) / Double(n) / 255 * 0.75, blue: Double(b) / Double(n) / 255 * 0.75)
        }
        return [average(rows: 0..<4), average(rows: 4..<8)]
    }
}

// MARK: - Scrubber

private struct Scrubber: View {
    @EnvironmentObject var player: MobilePlayer
    var body: some View { ScrubberBody(clock: player.clock) }
}

private struct ScrubberBody: View {
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject var player: MobilePlayer
    @State private var dragFraction: Double?

    var body: some View {
        let duration = max(player.duration, 0.1)
        let fraction = dragFraction ?? min(max(clock.time / duration, 0), 1)
        let shown = dragFraction.map { $0 * duration } ?? clock.time
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: geo.size.width * fraction)
                }
                .frame(height: dragFraction == nil ? 6 : 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(max($0.location.x / geo.size.width, 0), 1) }
                    .onEnded { value in
                        player.seek(to: min(max(value.location.x / geo.size.width, 0), 1) * duration)
                        dragFraction = nil
                    })
                .animation(.spring(response: 0.25), value: dragFraction == nil)
            }
            .frame(height: 16)
            HStack {
                Text(Format.time(shown))
                Spacer()
                if let quality = player.current?.qualityLabel {
                    QualityBadge(label: quality).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("-" + Format.time(max(0, duration - shown)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Lyrics

private struct LyricsPanel: View {
    @EnvironmentObject var player: MobilePlayer
    var body: some View { LyricsBody(clock: player.clock) }
}

private struct LyricsBody: View {
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject var player: MobilePlayer
    @State private var active: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(player.lyrics) { line in
                        Group {
                            if line.isBreak {
                                HStack(spacing: 10) {
                                    ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 10, height: 10) }
                                }
                                .opacity(active == line.id ? 0.9 : 0.3)
                            } else {
                                Text(line.text)
                                    .font(.system(size: 28, weight: .bold))
                                    .opacity(active == line.id ? 1 : 0.32)
                                    .blur(radius: active == line.id ? 0 : 0.5)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                        .onTapGesture { player.seek(to: line.timestamp) }
                        .animation(.easeOut(duration: 0.3), value: active)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 200)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .onChange(of: clock.time) { _, time in
                guard let line = player.lyrics.last(where: { $0.timestamp <= time }), line.id != active else { return }
                active = line.id
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { proxy.scrollTo(line.id, anchor: .center) }
            }
        }
    }
}

// MARK: - Queue

private struct QueuePanel: View {
    @EnvironmentObject var player: MobilePlayer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next").font(.headline)
                Spacer()
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .frame(width: 40, height: 32)
                        .background(player.isShuffled ? .white.opacity(0.25) : .white.opacity(0.08), in: Capsule())
                }
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .frame(width: 40, height: 32)
                        .background(player.repeatMode != .off ? .white.opacity(0.25) : .white.opacity(0.08), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)

            List {
                ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, song in
                    Button { player.jump(to: player.index + 1 + offset) } label: { SongRow(song: song) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                }
                .onDelete { player.removeFromQueue(at: $0) }
                .onMove { player.moveInQueue(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .overlay {
                if player.upNext.isEmpty { Text("Nothing up next").foregroundStyle(.white.opacity(0.5)) }
            }
        }
    }
}

// MARK: - System controls

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// The real system volume (MPVolumeView), styled to match.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
