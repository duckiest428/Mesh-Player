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
