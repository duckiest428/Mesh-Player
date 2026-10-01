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
    @State private var colors: [Color] = [Color(white: 0.22), Color(white: 0.1)]
    @State private var dragOffset: CGFloat = 0
    /// Full-screen (tall) motion artwork for the current album, when Apple Music has one.
    @State private var tallVideo: URL?
    @AppStorage("animatedArtwork") private var animatedArtwork = true

    private var showsTallArtwork: Bool { animatedArtwork && tallVideo != nil && panel == .artwork }

    enum Panel { case artwork, lyrics, queue }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    Capsule().fill(.white.opacity(0.45)).frame(width: 38, height: 5).padding(.top, 8)

                    Group {
                        switch panel {
                        case .artwork:
                            if showsTallArtwork {
                                Spacer(minLength: 0)
                            } else {
                                artwork(width: geo.size.width - 56)
                                    .frame(maxHeight: .infinity)
                            }
                        case .lyrics:
                            compactHeader.padding(.top, 22)
                            LyricsPanel()
                        case .queue:
                            compactHeader.padding(.top, 22)
                            QueuePanel()
                        }
                    }
                    .transition(.opacity)

                    controls
                        .padding(.horizontal, 28)
                        .padding(.bottom, 10)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
        // The cover's own background, so it reaches behind the status bar and home indicator.
        .presentationBackground { background.offset(y: dragOffset) }
        .task(id: player.current?.artworkKey) {
            if let found = await ArtworkPalette.colors(for: player.current?.artworkKey, darken: 0.62) {
                withAnimation(.easeInOut(duration: 0.8)) { colors = found }
            }
        }
        .task(id: player.current?.artworkKey) {
            guard animatedArtwork, let song = player.current else { tallVideo = nil; return }
            let videos = await AnimatedArtworkService.shared.videos(key: song.artworkKey, album: song.album, artist: song.albumArtist, localFolder: nil)
            withAnimation(.easeInOut(duration: 0.5)) { tallVideo = videos.tall }
        }
    }

    // MARK: Background

    /// The cover's colors, with a heavily blurred copy of the cover on top so the background
    /// carries its texture the way Apple Music's does.
    private var background: some View {
        // Every layer is sized by the screen (Color.clear), never by its own content: an image
        // set to fill would otherwise make the whole player wider than the display.
        ZStack {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            Color.clear
                .overlay {
                    ArtworkImage(key: player.current?.artworkKey, size: 120, cornerRadius: 0, seed: player.current?.album ?? "")
                        .aspectRatio(1, contentMode: .fill)
                        .scaleEffect(1.6)
                        .blur(radius: 70)
                        .opacity(0.55)
                }
                .clipped()
            LinearGradient(colors: [.clear, colors.last ?? .black], startPoint: .center, endPoint: .bottom).opacity(0.85)
            if animatedArtwork, let tallVideo {
                // Like Apple Music: the tall video fills the screen behind the controls; it
                // folds away for lyrics and the queue.
                Color.clear.overlay { MotionArtworkView(url: tallVideo) }.clipped()
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.3), location: 0),
                            .init(color: .clear, location: 0.18),
                            .init(color: .clear, location: 0.45),
                            .init(color: .black.opacity(0.85), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .opacity(panel == .artwork ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: panel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: colors)
        .ignoresSafeArea()
        .clipped()
    }

    // MARK: Artwork

    private func artwork(width: CGFloat) -> some View {
        let song = player.current
        return ZStack {
            ArtworkImage(key: song?.artworkKey, size: width, cornerRadius: 12, seed: song?.album ?? "")
            MotionArtwork(song: song)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(width: width, height: width)
        .scaleEffect(player.isPlaying ? 1 : 0.8)
        .shadow(color: .black.opacity(player.isPlaying ? 0.45 : 0.25), radius: player.isPlaying ? 30 : 12, y: player.isPlaying ? 16 : 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: player.isPlaying)
    }

    private var compactHeader: some View {
        HStack(spacing: 14) {
            ArtworkImage(key: player.current?.artworkKey, size: 82, cornerRadius: 8, seed: player.current?.album ?? "")
                .frame(width: 82, height: 82)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "").font(.title3.bold()).lineLimit(1)
                Text(player.current?.artist ?? "").font(.title3).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 4)
            favoriteAndMenu
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private var favoriteAndMenu: some View {
        if let song = player.current {
            let isFavorite = library.song(song.id)?.isFavorite ?? false
            Button { library.toggleFavorite(song.id) } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            Menu {
                SongMenu(songs: [song])
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            if panel == .artwork {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.title ?? "Not Playing")
                            .font(.title2.bold())
                            .lineLimit(1)
                        Text(player.current?.artist ?? "")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    favoriteAndMenu
                }
                .padding(.bottom, 26)
            }

            Scrubber()
                .padding(.bottom, 34)

            HStack {
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 36)) }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 52))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 80, height: 80)
                }
                Spacer()
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 36)) }
                Spacer()
            }
            .padding(.bottom, 30)

            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").font(.subheadline)
                SystemVolumeSlider().frame(height: 30)
                Image(systemName: "speaker.wave.3.fill").font(.subheadline)
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.bottom, 20)

            HStack {
                panelButton(.lyrics, icon: "quote.bubble")
                    .disabled(player.lyrics.isEmpty)
                    .opacity(player.lyrics.isEmpty ? 0.4 : 1)
                Spacer()
                RoutePicker().frame(width: 52, height: 52)
                Spacer()
                panelButton(.queue, icon: "list.bullet")
            }
            .padding(.horizontal, 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func panelButton(_ target: Panel, icon: String) -> some View {
        let active = panel == target
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { panel = active ? .artwork : target }
        } label: {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(active ? colors.first ?? .black : .white)
                .frame(width: 52, height: 52)
                .background(active ? .white.opacity(0.85) : .clear, in: Circle())
        }
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
                    Capsule().fill(.white.opacity(dragFraction == nil ? 0.75 : 1)).frame(width: geo.size.width * fraction)
                }
                .frame(height: dragFraction == nil ? 8 : 13)
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
        let upNext = player.upNext
        let autoplayOffset = player.autoplayStart.map { max(0, $0 - player.index - 1) }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                toggle("shuffle", isOn: player.isShuffled) { player.toggleShuffle() }
                toggle(player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off) { player.cycleRepeat() }
                toggle("infinity", isOn: player.autoplay) { player.autoplay.toggle() }
                toggle("arrow.triangle.merge", isOn: player.crossfade) { player.crossfade.toggle() }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            List {
                Section {
                    ForEach(Array(upNext.enumerated()), id: \.offset) { offset, song in
                        if autoplayOffset == nil || offset < autoplayOffset! {
                            row(song, offset: offset)
                        }
                    }
                    .onMove { player.moveInQueue(from: $0, to: $1) }
                    .deleteDisabled(true)
                } header: {
                    header(player.isShuffled ? "Continue Playing (Shuffled)" : "Continue Playing")
                }
                if let autoplayOffset, autoplayOffset < upNext.count {
                    Section {
                        ForEach(Array(upNext.enumerated()).filter { $0.offset >= autoplayOffset }, id: \.offset) { offset, song in
                            row(song, offset: offset)
                        }
                    } header: {
                        header("Autoplay")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if upNext.isEmpty {
                    Text(player.autoplay ? "Autoplay continues with similar songs" : "Nothing up next")
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .textCase(nil)
            .padding(.top, 6)
    }

    private func row(_ song: Song, offset: Int) -> some View {
        Button { player.jump(to: player.index + 1 + offset) } label: {
            HStack(spacing: 14) {
                ArtworkImage(key: song.artworkKey, size: 54, cornerRadius: 6, seed: song.album)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.title3).lineLimit(1)
                    Text(song.artist).font(.body).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button(role: .destructive) { player.removeFromQueue(at: IndexSet(integer: offset)) } label: { Label("Remove from Queue", systemImage: "minus.circle") }
        }
    }

    private func toggle(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isOn ? Color.black.opacity(0.75) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isOn ? .white.opacity(0.75) : .white.opacity(0.14), in: Capsule())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
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
