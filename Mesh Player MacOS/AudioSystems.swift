import AVFoundation
import AppKit
import Combine
import Foundation
import MediaPlayer
import SwiftUI

// MARK: - AudioEngineManager.swift
//
//  AudioEngineManager.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//


class AudioTimeTracker: ObservableObject {
    @Published var currentTime: TimeInterval = 0.0
}



class AudioEngineManager: ObservableObject {
    @Published var isPlaying: Bool = false
    var currentTime: TimeInterval { return timeTracker.currentTime }
    let timeTracker = AudioTimeTracker()
    @Published var duration: TimeInterval = 0.0
    @Published var volume: Float = 0.8 {
        didSet {
            // AVPlayer uses a scale of 0.0 to 1.0
            player?.volume = volume
        }
    }
    @Published var isAtmosTrack: Bool = false
    var hasCountedPlay: Bool = false
    private var hasScrobbled = false
    private var playStartedAt = Date()
    var onPlayCountUpdate: ((UUID) -> Void)?
    /// A new song started playing (used for Last.fm "now playing").
    var onTrackStarted: ((LocalTrack) -> Void)?
    /// The song reached Last.fm's scrobble point: half its length or 4 minutes.
    var onScrobblePoint: ((LocalTrack, Date) -> Void)?
    /// The user jumped to a new position in the song.
    var onSeek: ((TimeInterval) -> Void)?
    var onTrackMetadataUpdated: ((LocalTrack) -> Void)?
    @Published var currentTrack: LocalTrack?
    @Published var parsedLyrics: [SyncedLyricLine] = []
    
    // Hardware Routing
    @Published var availableOutputs: [SwiftOutputDevice] = []
    @Published var activeOutputId: String = ""
    /// The device macOS's sound output is set to.
    @Published var systemOutput: SwiftOutputDevice?
    
    
#if os(macOS)
    func triggerHaptic(pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
#else
    func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
#endif
    
    // Core Change: Replaced AVAudioPlayer with AVPlayer for system spatial routing
    private var player: AVPlayer?
    /// For the AirPlay picker, which routes this player.
    var avPlayer: AVPlayer? { player }

    /// The exact playback position, read straight from the player (the published time only
    /// updates a few times a second). For per-frame animations such as the lyrics' break dots.
    var preciseCurrentTime: TimeInterval {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return timeTracker.currentTime }
        return seconds
    }
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    
    // Handlers for remote commands
    var onPlayNext: (() -> Void)?
    var onPlayPrevious: (() -> Void)?
    var onTrackFinished: ((LocalTrack) -> Void)?
    
    init() {
        setupDeviceRouting()
        setupRemoteCommandCenter()
    }
    
    private var deviceObserver: AnyObject?

    private func setupDeviceRouting() {
        activeOutputId = UserDefaults.standard.string(forKey: "audioOutputDevice") ?? AudioDevices.systemID
        deviceObserver = AudioDevices.observe { [weak self] in
            MainActor.assumeIsolated { self?.refreshAvailableDevices() }
        }
        refreshAvailableDevices()
    }

    /// The Mac's output devices, and what "System Output" currently means.
    func refreshAvailableDevices() {
        availableOutputs = AudioDevices.outputs()
        systemOutput = AudioDevices.defaultOutput()
        // A chosen device that went away (AirPods put back in their case): follow macOS again
        // until it comes back.
        if activeOutputId != AudioDevices.systemID && !availableOutputs.contains(where: { $0.id == activeOutputId }) {
            player?.audioOutputDeviceUniqueID = nil
        } else {
            applyOutputDevice()
        }
    }

    /// Plays through `id`, or wherever macOS's sound output is set for `AudioDevices.systemID`.
    func setOutputDevice(id: String) {
        activeOutputId = id
        UserDefaults.standard.set(id, forKey: "audioOutputDevice")
        applyOutputDevice()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// The device sound is actually going to right now.
    var currentOutput: SwiftOutputDevice? {
        if activeOutputId != AudioDevices.systemID, let chosen = availableOutputs.first(where: { $0.id == activeOutputId }) { return chosen }
        return systemOutput
    }

    private func applyOutputDevice() {
        let uid = activeOutputId == AudioDevices.systemID ? nil : activeOutputId
        if player?.audioOutputDeviceUniqueID != uid { player?.audioOutputDeviceUniqueID = uid }
    }

    /// The media keys (F7, F8, F9), AirPods and headphone controls, Control Center and the
    /// Touch Bar all arrive here. macOS sends them to whichever app last said it's playing, so
    /// `updateNowPlayingInfo` keeps telling it.
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            MainActor.assumeIsolated { self.play() }
            return .success
        }

        // Taking an AirPod out sends "pause", never "toggle", so it must not start playback.
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            MainActor.assumeIsolated { self.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            MainActor.assumeIsolated { self.togglePlayPause() }
            return .success
        }

        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            MainActor.assumeIsolated { self.pause() }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            MainActor.assumeIsolated { self.onPlayNext?() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.currentTrack != nil else { return .noActionableNowPlayingItem }
            MainActor.assumeIsolated { self.onPlayPrevious?() }
            return .success
        }

        // Dragging the time in Control Center or the menu bar's Now Playing.
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self.seek(to: event.positionTime) }
            return .success
        }

        // Not supported: hide them so the keys map to next/previous rather than seeking.
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
    }

    /// Claims the media keys again, e.g. after the Music app was told to play (mirroring).
    func reassertNowPlaying() {
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo(refreshArtwork: Bool = false) {
        SystemMediaManager.shared.updateNowPlayingInfo(track: currentTrack, isPlaying: isPlaying, currentTime: currentTime, refreshArtwork: refreshArtwork)
    }
    
    /// Parses the current song's lyrics, then swaps in word-synced ones when that experimental
    /// setting is on and they can be found. Also called when the setting changes.
    func reloadLyrics() {
        guard let track = currentTrack else { parsedLyrics = []; return }
        parsedLyrics = LyricsEngine.parse(lyricsText: track.lyrics, duration: track.duration)
        guard UserDefaults.standard.bool(forKey: ExperimentalSettings.wordLyricsKey) else { return }
        let id = track.id
        Task { @MainActor [weak self] in
            guard let lines = await WordLyricsService.shared.lines(title: track.title, artist: track.artist, duration: track.duration, fileLyrics: track.lyrics),
                  let self, self.currentTrack?.id == id else { return }
            self.parsedLyrics = lines
        }
    }

    /// Albums we've already asked the iTunes Search API about this session.
    private var remoteLookupsAttempted = Set<String>()

    func playTrack(_ track: LocalTrack) {
        // Clean up any active observers from the previous track
        removeTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        self.currentTrack = track
        self.duration = track.duration
        self.timeTracker.currentTime = 0.0
        self.hasCountedPlay = false
        self.hasScrobbled = false
        self.playStartedAt = Date()
        self.isAtmosTrack = track.isAtmos
        reloadLyrics()

        guard let url = track.fileURL else {
            self.player = nil
            self.isPlaying = false
            updateNowPlayingInfo()
            return
        }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        // Settings › Playback: Dolby Atmos / multichannel rendering and spatializing stereo.
        let defaults = UserDefaults.standard
        let renderAtmos = defaults.object(forKey: "settings.enableAtmos") as? Bool ?? true
        let spatializeStereo = defaults.object(forKey: "settings.spatialAudioActive") as? Bool ?? false
        playerItem.allowedAudioSpatializationFormats = !renderAtmos ? [] : (spatializeStereo ? .monoStereoAndMultichannel : .multichannel)

        let player = AVPlayer(playerItem: playerItem)
        if activeOutputId != AudioDevices.systemID && availableOutputs.contains(where: { $0.id == activeOutputId }) {
            player.audioOutputDeviceUniqueID = activeOutputId
        }
        player.volume = volume
        self.player = player

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.player = nil
                if let track = self.currentTrack { self.onTrackFinished?(track) }
                self.onPlayNext?()
            }
        }

        player.play()
        isPlaying = true

        // Scrobbling Broadcast
        let userInfo: [String: Any] = [
            "Player State": "Playing",
            "Title": track.title,
            "Artist": track.artist,
            "Album": track.album,
            "Total Time": Int(track.duration * 1000)
        ]
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.apple.iTunes.playerInfo"), object: "com.apple.iTunes.player", userInfo: userInfo, deliverImmediately: true)

        updateNowPlayingInfo()
        startTimeObservers()
        onTrackStarted?(track)
        probeFormat(of: track, asset: asset)
        fetchMissingMetadataIfNeeded(for: track)
    }

    /// Codec inspection runs off the main thread so starting playback never hitches.
    private func probeFormat(of track: LocalTrack, asset: AVURLAsset) {
        let trackId = track.id
        Task { [weak self] in
            let info = await Task.detached(priority: .userInitiated) { await TrackMetadataReader.probeCodec(asset) }.value
            guard let self, let info, self.currentTrack?.id == trackId else { return }
            let isAtmos = info.isAtmos || (info.channels ?? 2) > 2
            self.isAtmosTrack = isAtmos
            guard var updated = self.currentTrack else { return }
            let label = TrackMetadataReader.formatLabel(info, fileExtension: track.fileURL?.pathExtension.lowercased() ?? "")
            let changed = updated.isAtmos != info.isAtmos || updated.format != label || updated.channels != info.channels
            guard changed else { return }
            updated.isAtmos = info.isAtmos
            updated.format = label
            updated.channels = info.channels
            updated.bitDepth = info.bitDepth ?? updated.bitDepth
            updated.sampleRate = info.sampleRate ?? updated.sampleRate
            updated.bitRate = info.bitRate ?? updated.bitRate
            self.currentTrack = updated
            self.onTrackMetadataUpdated?(updated)
        }
    }

    /// Fills in missing artwork / copyright from the iTunes Search API, once per album.
    private func fetchMissingMetadataIfNeeded(for track: LocalTrack) {
        let lookupKey = track.artworkKey
        guard !remoteLookupsAttempted.contains(lookupKey) else { return }
        let needsCopyright = track.copyright?.isEmpty ?? true
        Task { [weak self] in
            let hasArtwork = await ArtworkStore.shared.hasArtwork(for: track)
            guard let self, !hasArtwork || needsCopyright else { return }
            self.remoteLookupsAttempted.insert(lookupKey)

            let term = "\(track.album) \(track.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let url = URL(string: "https://itunes.apple.com/search?term=\(term)&media=music&entity=album&limit=1"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first else { return }

            if !hasArtwork, let art100 = first["artworkUrl100"] as? String,
               let artURL = URL(string: art100.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
               let (artData, _) = try? await URLSession.shared.data(from: artURL), !artData.isEmpty {
                ArtworkStore.shared.store(artData, forKey: lookupKey, notify: true)
                if self.currentTrack?.artworkKey == lookupKey { self.updateNowPlayingInfo(refreshArtwork: true) }
            }
            if needsCopyright, let copyright = first["copyright"] as? String, var updated = self.currentTrack, updated.id == track.id {
                updated.copyright = copyright
                self.currentTrack = updated
                self.onTrackMetadataUpdated?(updated)
            }
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func pause() {
        guard isPlaying else { return }
        
        if let player = player {
            player.pause()
        }
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func play() {
        guard !isPlaying else { return }

        guard let player = player else {
            // Playback finished (or never started): restart the current track.
            if let track = currentTrack { playTrack(track) }
            return
        }
        player.play()
        isPlaying = true
        startTimeObservers()
        updateNowPlayingInfo()
    }
    
    func seek(to time: TimeInterval) {
        timeTracker.currentTime = max(0, min(time, duration))
        let targetCMTime = CMTime(seconds: timeTracker.currentTime, preferredTimescale: 60000)
        player?.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
        onSeek?(timeTracker.currentTime)
        
        updateNowPlayingInfo()
    }
    
    private func startTimeObservers() {
        removeTimeObserver()
        
        guard let player = player else { return }
        
        // Progress Time Observer: Uses AVPlayer native high-precision periodic callback
        let interval = CMTime(seconds: 0.1, preferredTimescale: 60000)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.timeTracker.currentTime = time.seconds
            
            if !self.hasCountedPlay && self.duration > 0 {
                let threshold = self.duration / 2.0
                if time.seconds >= threshold {
                    self.hasCountedPlay = true
                    if let track = self.currentTrack {
                        self.onPlayCountUpdate?(track.id)
                    }
                }
            }
            if !self.hasScrobbled && self.duration >= 30 && time.seconds >= min(self.duration / 2.0, 240) {
                self.hasScrobbled = true
                if let track = self.currentTrack { self.onScrobblePoint?(track, self.playStartedAt) }
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    deinit {
        removeTimeObserver()
    }
}

// MARK: - SystemMediaManager.swift
//
//  SystemMediaManager.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-26.
//  SPDX-License-Identifier: Apache-2.0
//


class SystemMediaManager {
    static let shared = SystemMediaManager()
    
    private init() {}
    
    private var artworkTrackKey: String?

    /// Built outside the main actor: MediaPlayer calls the handler on a background thread.
    nonisolated private static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
    private var artwork: MPMediaItemArtwork?

    func updateNowPlayingInfo(track: LocalTrack?, isPlaying: Bool, currentTime: TimeInterval, refreshArtwork: Bool = false) {
        var nowPlayingInfo = [String: Any]()
        
        if let track = track {
            // Title / artist / album / duration are what Last.fm-style scrobblers read to identify a play.
            nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
            nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration

            // Artwork is decoded once per album, off the main thread, then reused.
            let key = track.artworkKey
            if key == artworkTrackKey && !refreshArtwork {
                if let artwork { nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork }
            } else {
                artworkTrackKey = key
                artwork = nil
                Task { [weak self] in
                    guard let image = await ArtworkStore.shared.image(for: track, pixelSize: 600),
                          let self, self.artworkTrackKey == key else { return }
                    let art = Self.makeArtwork(image)
                    self.artwork = art
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = art
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
        
        // MPNowPlayingInfoPropertyElapsedPlaybackTime: Tells the OS exactly where we are in the track, helping scrobblers sync their internal timer.
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // MPNowPlayingInfoPropertyPlaybackRate: A value of 1.0 indicates active playback (started/resumed), while 0.0 indicates a paused or stopped state. Scrobblers listen to this to pause their duration tracking.
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        // macOS routes the media keys and AirPods to the app whose playback state says it's
        // playing (or paused most recently); without this they often went to the Music app.
        MPNowPlayingInfoCenter.default().playbackState = track == nil ? .stopped : (isPlaying ? .playing : .paused)
        
        // Broadcast system-wide Darwin notification for robust scrobbler integration (e.g., standard Apple Music/iTunes media state signatures)
        var userInfo = [String: Any]()
        if let track = track {
            userInfo["Name"] = track.title
            userInfo["Artist"] = track.artist
            userInfo["Album"] = track.album
            userInfo["Total Time"] = Int(track.duration * 1000)
            userInfo["Player State"] = isPlaying ? "Playing" : "Paused"
        } else {
            userInfo["Player State"] = "Stopped"
        }
        
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}

