//
//  AnimatedArtwork.swift
//  Mesh Player
//
//  Plays an album's square motion artwork (see Shared/MotionArtwork.swift).
//

import AppKit
import AVFoundation
import SwiftUI

extension AnimatedArtworkService {
    /// Square motion artwork for the track's album, or nil when the album has none.
    func squareVideo(for track: LocalTrack) async -> URL? {
        await videos(key: track.artworkKey, album: track.album, artist: track.albumArtist ?? track.artist,
                     localFolder: track.fileURL?.deletingLastPathComponent()).square
    }
}

// MARK: - View

/// Plays an album's square motion artwork, muted and looping. Transparent until the first
/// frame is ready, so it can sit on top of the static cover and simply fade in.
struct AnimatedArtworkView: NSViewRepresentable {
    let track: LocalTrack
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.cornerRadius = cornerRadius
        context.coordinator.host = view
        context.coordinator.load(track)
        return view
    }

    func updateNSView(_ view: PlayerHostView, context: Context) {
        view.playerLayer.cornerRadius = cornerRadius
        context.coordinator.load(track)
    }

    static func dismantleNSView(_ view: PlayerHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class PlayerHostView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.masksToBounds = true
            playerLayer.opacity = 0
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator {
        weak var host: PlayerHostView?
        private var key: String?
        private var player: AVPlayer?
        private var loopObserver: NSObjectProtocol?
        private var readyObservation: NSKeyValueObservation?
        private var loadTask: Task<Void, Never>?

        func load(_ track: LocalTrack) {
            let newKey = track.artworkKey
            guard newKey != key else { return }
            stop()
            key = newKey
            loadTask = Task { [weak self] in
                guard let url = await AnimatedArtworkService.shared.squareVideo(for: track),
                      !Task.isCancelled, let self, self.key == newKey else { return }
                self.start(url)
            }
        }

        private func start(_ url: URL) {
            guard let host else { return }
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            self.player = player
            host.playerLayer.player = player
            readyObservation = host.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.6)
                    layer.opacity = 1
                    CATransaction.commit()
                }
            }
            loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            player.play()
        }

        func stop() {
            loadTask?.cancel()
            loadTask = nil
            readyObservation = nil
            if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
            loopObserver = nil
            player?.pause()
            player = nil
            host?.playerLayer.player = nil
            host?.playerLayer.opacity = 0
            key = nil
        }
    }
}

/// Plays any motion artwork URL, muted and looping (used by the artwork viewer).
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var cornerRadius: CGFloat = 0
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> AnimatedArtworkView.PlayerHostView {
        let view = AnimatedArtworkView.PlayerHostView()
        configure(view)
        context.coordinator.play(url, in: view)
        return view
    }

    func updateNSView(_ view: AnimatedArtworkView.PlayerHostView, context: Context) {
        configure(view)
        context.coordinator.play(url, in: view)
    }

    static func dismantleNSView(_ view: AnimatedArtworkView.PlayerHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(_ view: AnimatedArtworkView.PlayerHostView) {
        view.playerLayer.cornerRadius = cornerRadius
        view.playerLayer.videoGravity = gravity
    }

    final class Coordinator {
        private var url: URL?
        private var player: AVPlayer?
        private var loopObserver: NSObjectProtocol?
        private var readyObservation: NSKeyValueObservation?

        func play(_ url: URL, in host: AnimatedArtworkView.PlayerHostView) {
            guard url != self.url else { return }
            stop()
            self.url = url
            host.playerLayer.opacity = 0
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            self.player = player
            host.playerLayer.player = player
            readyObservation = host.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.4)
                    layer.opacity = 1
                    CATransaction.commit()
                }
            }
            loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            player.play()
        }

        func stop() {
            readyObservation = nil
            if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
            loopObserver = nil
            player?.pause()
            player = nil
            url = nil
        }
    }
}

// MARK: - Artwork viewer

/// Opened by clicking an album's cover: the full-size artwork, plus the square and tall motion
/// artwork when Apple Music has them.
struct ArtworkViewerSheet: View {
    let track: LocalTrack
    let title: String
    let theme: ThemeColor
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case still = "Artwork"
        case square = "Animated"
        case tall = "Animated (Tall)"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .still
    @State private var square: URL?
    @State private var tall: URL?
    @State private var lookedUp = false
    @State private var showControls = true

    private var modes: [Mode] {
        [.still] + (square != nil ? [.square] : []) + (tall != nil ? [.tall] : [])
    }

    /// The sheet is exactly the artwork's size: square for stills and square motion art, 3:4 for tall.
    private var artSize: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let height = min(760, screen.height - 120)
        return mode == .tall ? CGSize(width: height * 3 / 4, height: height) : CGSize(width: height, height: height)
    }

    var body: some View {
        ZStack {
            switch mode {
            case .still:
                ArtworkView(track: track, pixelSize: 1600, cornerRadius: 0)
            case .square:
                if let square {
                    // The still sits underneath until the first video frame is ready.
                    ZStack {
                        ArtworkView(track: track, pixelSize: 1600, cornerRadius: 0)
                        LoopingVideoView(url: square)
                    }
                }
            case .tall:
                if let tall {
                    ZStack {
                        ArtworkView(track: track, pixelSize: 1600, cornerRadius: 0)
                            .blur(radius: 30)
                        LoopingVideoView(url: tall)
                    }
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height)
        .clipped()
        .overlay(alignment: .top) {
            // Controls float over the artwork and fade in on hover.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(lookedUp ? (modes.count > 1 ? "Motion artwork available" : "No motion artwork") : "Looking for motion artwork…")
                        .font(.system(size: 11))
                        .opacity(0.75)
                }
                Spacer(minLength: 8)
                if modes.count > 1 {
                    Picker("", selection: $mode.animation(.easeInOut(duration: 0.3))) {
                        ForEach(modes) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .background(LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
            .opacity(showControls ? 1 : 0)
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.2)) { showControls = hovering } }
        .background(Color.black)
        .task {
            let videos = await AnimatedArtworkService.shared.videos(key: track.artworkKey, album: track.album, artist: track.albumArtist ?? track.artist,
                                                                    localFolder: track.fileURL?.deletingLastPathComponent())
            square = videos.square
            tall = videos.tall
            lookedUp = true
        }
    }
}
