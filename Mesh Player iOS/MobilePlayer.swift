//
//  MobilePlayer.swift
//  Mesh Player iOS
//
//  Playback: a queue with shuffle / repeat, background audio, lock screen and Control Center
//  controls, spatial audio for Dolby Atmos files, play counting and synced lyrics.
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

/// Playback position lives in its own object so only the views showing time redraw 4× a second.
final class PlaybackClock: ObservableObject {
    @Published var time: TimeInterval = 0
}

final class MobilePlayer: ObservableObject {
    static let shared = MobilePlayer()

    enum RepeatMode: Int { case off, all, one }

    @Published private(set) var current: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var queue: [UUID] = []
    @Published private(set) var index = 0
    @Published private(set) var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var lyrics: [SyncedLyricLine] = []
    let clock = PlaybackClock()

    private var originalQueue: [UUID] = []
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var countedPlay = false
    private var scrobbled = false
    private var startedAt = Date()
    private static let fadeLength: TimeInterval = 6
    private var library: MobileLibrary { .shared }
    private var nowPlayingArtwork: MPMediaItemArtwork?

    var duration: TimeInterval { current?.duration ?? 0 }
    var upNext: [Song] {
        guard index + 1 < queue.count else { return [] }
        return queue[(index + 1)...].compactMap(library.song)
    }

    private init() {
        configureSession()
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began {
                    self.isPlaying = false
                    self.updateNowPlaying()
                } else if type == .ended, options?.contains(.shouldResume) == true {
                    self.resume()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            // Pause when headphones are unplugged, like every music app.
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setSupportsMultichannelContent(true)
    }

    // MARK: Queue

    func play(_ songs: [Song], startAt song: Song? = nil, shuffled: Bool = false) {
        let playable = songs.filter(\.isAvailable)
        guard !playable.isEmpty else { return }
        originalQueue = playable.map(\.id)
        isShuffled = shuffled
        if shuffled {
            var rest = originalQueue.shuffled()
            if let song, let i = rest.firstIndex(of: song.id) { rest.swapAt(0, i) }
            queue = rest
            index = 0
        } else {
            queue = originalQueue
            index = song.flatMap { s in queue.firstIndex(of: s.id) } ?? 0
        }
        load(queue[index], autoplay: true)
    }

    func playNext(_ songs: [Song]) {
        let ids = songs.filter(\.isAvailable).map(\.id)
        guard !ids.isEmpty else { return }
        if current == nil { play(songs); return }
        queue.insert(contentsOf: ids, at: min(index + 1, queue.count))
        originalQueue.append(contentsOf: ids)
    }

    func playLater(_ songs: [Song]) {
        let ids = songs.filter(\.isAvailable).map(\.id)
        guard !ids.isEmpty else { return }
        if current == nil { play(songs); return }
        queue.append(contentsOf: ids)
        originalQueue.append(contentsOf: ids)
    }

    func jump(to position: Int) {
        guard queue.indices.contains(position) else { return }
        index = position
        load(queue[position], autoplay: true)
    }

    func removeFromQueue(at offsets: IndexSet) {
        // Offsets are relative to Up Next.
        let absolute = IndexSet(offsets.map { $0 + index + 1 })
        queue.remove(atOffsets: absolute)
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        var upcoming = Array(queue[(index + 1)...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[...index]) + upcoming
    }

    func toggleShuffle() {
        guard let currentId = current?.id else { isShuffled.toggle(); return }
        isShuffled.toggle()
        if isShuffled {
            var rest = queue.filter { $0 != currentId }.shuffled()
            rest.insert(currentId, at: 0)
            queue = rest
            index = 0
        } else {
            queue = originalQueue
            index = queue.firstIndex(of: currentId) ?? 0
        }
    }

    func cycleRepeat() {
        repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off
    }

    // MARK: Transport

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentItem == nil, let current { load(current.id, autoplay: true); return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all {
            index = 0
        } else {
            pause()
            seek(to: 0)
            return
        }
        load(queue[index], autoplay: true)
    }

    func previous() {
        if clock.time > 3 || index == 0 {
            seek(to: 0)
            return
        }
        index -= 1
        load(queue[index], autoplay: true)
    }

    func seek(to time: TimeInterval) {
        clock.time = max(0, time)
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    private func load(_ id: UUID, autoplay: Bool) {
        guard let song = library.song(id), let url = library.fileURL(for: song) else {
            // Missing file: skip it.
            if index + 1 < queue.count { index += 1; load(queue[index], autoplay: autoplay) }
            return
        }
        current = song
        countedPlay = false
        scrobbled = false
        startedAt = Date()
        player.volume = crossfade ? 0 : 1
        MobileLastFM.shared.nowPlaying(song)
        clock.time = 0
        lyrics = LyricsEngine.parse(lyricsText: song.info.lyrics, duration: song.duration)
        let item = AVPlayerItem(url: url)
        let spatialStereo = UserDefaults.standard.bool(forKey: "spatializeStereo")
        item.allowedAudioSpatializationFormats = spatialStereo ? .monoStereoAndMultichannel : .multichannel
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemFinished() }
        }
        player.replaceCurrentItem(with: item)
        if autoplay {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
        loadNowPlayingArtwork(for: song)
        updateNowPlaying()
    }

    private func itemFinished() {
        if repeatMode == .one, let current {
            load(current.id, autoplay: true)
        } else {
            next()
        }
    }

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        clock.time = seconds
        guard let current, current.duration > 0 else { return }
        if !countedPlay, seconds >= current.duration / 2 {
            countedPlay = true
            library.recordPlay(current.id)
        }
        // Last.fm's rule: half the song or 4 minutes, whichever comes first.
        if !scrobbled, seconds >= min(current.duration / 2, 240) {
            scrobbled = true
            MobileLastFM.shared.scrobble(current, startedAt: startedAt)
        }
        if crossfade {
            let fadeIn = min(seconds / 2, 1)
            let fadeOut = min(max((current.duration - seconds) / Self.fadeLength, 0), 1)
            player.volume = Float(min(fadeIn, fadeOut))
        }
    }

    // MARK: Lock screen / Control Center

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.togglePlayPause() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
            return .success
        }
        center.likeCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                if let id = self?.current?.id { MobileLibrary.shared.toggleFavorite(id) }
            }
            return .success
        }
    }

    private func loadNowPlayingArtwork(for song: Song) {
        nowPlayingArtwork = nil
        let key = song.artworkKey
        Task { [weak self] in
            guard let image = await ArtworkCache.shared.image(key, size: 400), let self, self.current?.artworkKey == key else { return }
            self.nowPlayingArtwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func updateNowPlaying() {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album,
            MPMediaItemPropertyPlaybackDuration: current.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
