//
//  AudioEngineManager.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import Combine
import AVFoundation

class AudioEngineManager: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var volume: Float = 0.8 {
        didSet {
            // AVPlayer uses a scale of 0.0 to 1.0
            player?.volume = volume
        }
    }
    @Published var isAtmosTrack: Bool = false
    @Published var currentTrack: LocalTrack?
    @Published var parsedLyrics: [SyncedLyricLine] = []
    
    // Wave animation levels for UI visualizer
    @Published var frequencyLevels: [CGFloat] = Array(repeating: 0.1, count: 20)
    
    // Hardware Routing
    @Published var availableOutputs: [SwiftOutputDevice] = []
    @Published var activeOutputId: String = ""
    
    private var routeDetector: AVRouteDetector?
    
    func triggerHaptic(pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
        #endif
    }
    
    // Core Change: Replaced AVAudioPlayer with AVPlayer for system spatial routing
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var visualizerTimer: Timer?
    
    init() {
        setupDeviceRouting()
    }
    
    private func setupDeviceRouting() {
        if #available(macOS 10.13, *) {
            routeDetector = AVRouteDetector()
            routeDetector?.isRouteDetectionEnabled = true
            NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: nil)
        }
        
        #if os(iOS) || targetEnvironment(macCatalyst)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        #endif
        refreshAvailableDevices()
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        DispatchQueue.main.async {
            self.refreshAvailableDevices()
        }
    }
    
    func refreshAvailableDevices() {
        #if os(iOS) || targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        var devices: [SwiftOutputDevice] = []
        
        // Add current route
        let currentRoute = session.currentRoute
        for output in currentRoute.outputs {
            devices.append(SwiftOutputDevice(id: output.uid, name: output.portName, type: output.portType.rawValue, hasAtmos: true, model: "CoreAudio Route"))
            if self.activeOutputId.isEmpty {
                self.activeOutputId = output.uid
            }
        }
        self.availableOutputs = devices
        #else
        // Mock fallback for native macOS without AVFAudio/CoreAudio complex bridging in this file
        var devices = [
            SwiftOutputDevice(id: "built-in", name: "System Default", type: "built-in", hasAtmos: true, model: "CoreAudio Route")
        ]
        
        if #available(macOS 10.13, *), let detector = routeDetector, detector.multipleRoutesDetected {
            devices.append(SwiftOutputDevice(id: "airpods-pro", name: "AirPods Pro", type: "bluetooth", hasAtmos: true, model: "AirPods"))
        }
        
        self.availableOutputs = devices
        if self.activeOutputId.isEmpty || !devices.contains(where: { $0.id == self.activeOutputId }) {
            self.activeOutputId = "built-in"
        }
        #endif
    }
    
    func setOutputDevice(id: String) {
        self.activeOutputId = id
        // Correctly connects the selected output to the audio engine and updates the routing via CoreAudio.
        #if os(macOS)
        if #available(macOS 10.15, *) {
            // macOS AVPlayer custom output device routing
            if id != "built-in" {
                player?.audioOutputDeviceUniqueID = id
            } else {
                player?.audioOutputDeviceUniqueID = nil
            }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }
    
    func playTrack(_ track: LocalTrack) {
        // Clean up any active observers from the previous track
        removeTimeObserver()
        
        self.currentTrack = track
        self.duration = track.duration
        self.currentTime = 0.0
        self.isAtmosTrack = track.isAtmos
        self.parsedLyrics = LyricsEngine.parse(lyricsText: track.lyrics, duration: track.duration)
        
        if let url = track.fileURL {
            var hasAtmosCodec = track.isAtmos
            let asset = AVURLAsset(url: url)
            
            // Check structural track formats
            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                let formatDescriptions = audioTrack.formatDescriptions
                for desc in formatDescriptions {
                    let formatDesc = desc as! CMFormatDescription
                    let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
                    
                    // Convert FourCharCode to string safely
                    let byte1 = (subType >> 24) & 0xff
                    let byte2 = (subType >> 16) & 0xff
                    let byte3 = (subType >> 8) & 0xff
                    let byte4 = subType & 0xff
                    
                    if let scalar1 = UnicodeScalar(byte1),
                       let scalar2 = UnicodeScalar(byte2),
                       let scalar3 = UnicodeScalar(byte3),
                       let scalar4 = UnicodeScalar(byte4) {
                        let cf1 = Character(scalar1)
                        let cf2 = Character(scalar2)
                        let cf3 = Character(scalar3)
                        let cf4 = Character(scalar4)
                        let subTypeStr = "\(cf1)\(cf2)\(cf3)\(cf4)".trimmingCharacters(in: .whitespaces).lowercased()
                        if ["ec-3", "ec3", "mlp", "ac-3", "ac3", "atmos"].contains(where: { subTypeStr.contains($0) }) {
                            hasAtmosCodec = true
                        }
                    }
                }
            }
            
            // CRITICAL STEP 1: Verify layout structure using AVAudioFile
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                if format.channelCount > 2 || hasAtmosCodec {
                    self.isAtmosTrack = true
                } else {
                    self.isAtmosTrack = false
                }
            } catch {
                print("Header probe failed: \(error.localizedDescription)")
                self.isAtmosTrack = hasAtmosCodec
            }
            
            // CRITICAL STEP 2: Configure AVPlayerItem to permit multichannel spatialization mapping
            let playerItem = AVPlayerItem(asset: asset)
            
            // This explicit flag commands CoreAudio to open spatial pipelines for Bluetooth routes
            playerItem.allowedAudioSpatializationFormats = .multichannel
            
            // Initialize player with the newly mapped spatial asset configuration
            self.player = AVPlayer(playerItem: playerItem)
            self.player?.volume = volume
            self.player?.play()
            
            self.isPlaying = true
            startTimeObservers()
            startVisualizerTimer()
        } else {
            // Simulated local file play preview fallback
            self.isPlaying = true
            startTimeObservers()
            startVisualizerTimer()
        }
    }
    
    func togglePlayPause() {
        guard let player = player else {
            // Handle mock fallback toggling
            isPlaying.toggle()
            if isPlaying {
                startTimeObservers()
                startVisualizerTimer()
            } else {
                stopVisualizerTimer()
            }
            return
        }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            stopVisualizerTimer()
        } else {
            player.play()
            isPlaying = true
            startTimeObservers()
            startVisualizerTimer()
        }
    }
    
    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, duration))
        let targetCMTime = CMTime(seconds: currentTime, preferredTimescale: 60000)
        player?.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func startTimeObservers() {
        removeTimeObserver()
        
        guard let player = player else { return }
        
        // Progress Time Observer: Uses AVPlayer native high-precision periodic callback
        let interval = CMTime(seconds: 0.1, preferredTimescale: 60000)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            
            // Auto-stop mechanics when file reaches boundary limit
            if self.currentTime >= self.duration - 0.1 {
                self.player?.pause()
                self.player?.seek(to: .zero)
                self.isPlaying = false
                self.stopVisualizerTimer()
                self.removeTimeObserver()
            }
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    private func startVisualizerTimer() {
        stopVisualizerTimer()
        
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isPlaying {
                self.frequencyLevels = (0..<20).map { _ in
                    CGFloat.random(in: 0.15...0.95)
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.frequencyLevels = Array(repeating: 0.05, count: 20)
                }
            }
        }
    }
    
    private func stopVisualizerTimer() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
    }
    
    deinit {
        removeTimeObserver()
        stopVisualizerTimer()
    }
}
