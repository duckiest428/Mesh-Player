import SwiftUI
import Combine
import AVFoundation
import AVKit
import MediaPlayer

class iOSAudioEngine: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var volume: Float = 0.5 {
        didSet {
            player?.volume = volume
        }
    }
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var currentSong: iOSSong?
    private var hasCountedPlay = false
    var onPlayCountUpdate: ((UUID) -> Void)?
    
    init() {
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category.")
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] event in
            if self?.player?.currentItem != nil {
                self?.player?.play()
                self?.isPlaying = true
                self?.updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            if self?.player?.currentItem != nil {
                self?.player?.pause()
                self?.isPlaying = false
                self?.updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = song.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    func playSong(_ song: iOSSong) {
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: player?.currentItem)
        
        self.currentSong = song
        self.duration = song.duration
        self.currentTime = 0.0
        
        if let url = song.fileURL {
            let playerItem = AVPlayerItem(url: url)
            if player == nil {
                player = AVPlayer(playerItem: playerItem)
            } else {
                player?.replaceCurrentItem(with: playerItem)
            }
            player?.volume = self.volume
            player?.play()
            self.isPlaying = true
            
            startTimeObservers()
            updateNowPlayingInfo()
            
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player?.currentItem, queue: .main) { [weak self] _ in
                self?.isPlaying = false
                self?.currentTime = 0
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        self.currentTime = time
        updateNowPlayingInfo()
    }
    
    private func startTimeObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken =
        player?.addPeriodicTimeObserver(forInterval: interval,
                                        queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.updateNowPlayingInfo()
            
            if !self.hasCountedPlay && self.duration > 0 {
                let threshold = min(30.0, self.duration / 2.0)
                if time.seconds >= threshold {
                    self.hasCountedPlay = true
                    if let song = self.currentSong {
                        self.onPlayCountUpdate?(song.id)
                    }
                }
            }
        }
    }
}
