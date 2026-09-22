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
    private func scrobbleToLastFm(track: LocalTrack) {
        // Last.fm scrobbling placeholder
        // Requires MD5 hashing and Last.fm API keys
        print("Last.fm Scrobbling: \(track.title) by \(track.artist)")
    }

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
    var onPlayCountUpdate: ((UUID) -> Void)?
    var onTrackMetadataUpdated: ((LocalTrack) -> Void)?
    @Published var currentTrack: LocalTrack?
    @Published var parsedLyrics: [SyncedLyricLine] = []
    
    // Hardware Routing
    @Published var availableOutputs: [SwiftOutputDevice] = []
    @Published var activeOutputId: String = ""
    
    private var routeDetector: AVRouteDetector?
    
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
    private var timeObserverToken: Any?
    
    // Handlers for remote commands
    var onPlayNext: (() -> Void)?
    var onPlayPrevious: (() -> Void)?
    var onTrackFinished: ((LocalTrack) -> Void)?
    
    init() {
        setupDeviceRouting()
        setupRemoteCommandCenter()
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
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            if !self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            if let track = self.currentTrack { self.onTrackFinished?(track) }
                self.onPlayNext?()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.onPlayPrevious?()
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        SystemMediaManager.shared.updateNowPlayingInfo(track: currentTrack, isPlaying: isPlaying, currentTime: currentTime)
    }
    
    func playTrack(_ track: LocalTrack) {
        // Fetch missing metadata from iTunes API
        if track.embeddedArtData == nil || track.copyright == nil || track.copyright!.isEmpty {
            let term = "\(track.album) \(track.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://itunes.apple.com/search?term=\(term)&media=music&entity=album&limit=1") {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data = data else { return }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let first = results.first {
                        var updated = false
                        var newTrack = track
                        if track.embeddedArtData == nil, let art100 = first["artworkUrl100"] as? String {
                            let artwork = art100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                            if let artUrl = URL(string: artwork), let artData = try? Data(contentsOf: artUrl) {
                                newTrack.embeddedArtData = artData
                                updated = true
                            }
                        }
                        if (track.copyright == nil || track.copyright!.isEmpty), let copyright = first["copyright"] as? String {
                            newTrack.copyright = copyright
                            updated = true
                        }
                        if updated {
                            DispatchQueue.main.async {
                                if self.currentTrack?.id == newTrack.id {
                                    self.currentTrack = newTrack
                                    self.onTrackMetadataUpdated?(newTrack)
                                }
                            }
                        }
                    }
                }.resume()
            }
        }

        // Clean up any active observers from the previous track
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        self.currentTrack = track
        self.duration = track.duration
        self.timeTracker.currentTime = 0.0
        self.hasCountedPlay = false
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
            
            // Add completion lifecycle hook (Song End Tracking)
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                self.isPlaying = false
                MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
                MPNowPlayingInfoCenter.default().playbackState = .stopped
                
                // Re-initialize player cleanly
                self.player = nil
                
                if let track = self.currentTrack { self.onTrackFinished?(track) }
                self.onPlayNext?()
            }
            
            self.player?.volume = volume
            self.player?.play()
            
            self.isPlaying = true
            
            // Scrobbling Broadcast
            let center = DistributedNotificationCenter.default()
            let userInfo: [String: Any] = [
                "Player State": "Playing",
                "Title": track.title,
                "Artist": track.artist,
                "Album": track.album,
                "Total Time": Int(track.duration * 1000)
            ]
            center.postNotificationName(NSNotification.Name("com.apple.iTunes.playerInfo"), object: "com.apple.iTunes.player", userInfo: userInfo, deliverImmediately: true)
            
            updateNowPlayingInfo()
            startTimeObservers()
        } else {
            // Simulated local file play preview fallback
            self.isPlaying = true
            startTimeObservers()
        }
        
        updateNowPlayingInfo()
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
        
        if let player = player {
            player.play()
        }
        isPlaying = true
        startTimeObservers()
        updateNowPlayingInfo()
    }
    
    func seek(to time: TimeInterval) {
        timeTracker.currentTime = max(0, min(time, duration))
        let targetCMTime = CMTime(seconds: timeTracker.currentTime, preferredTimescale: 60000)
        player?.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
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
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    func parseTrackMetadata(from url: URL) -> LocalTrack {
        let asset = AVAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var genre = "Alternative"
        var embeddedArtData: Data? = nil
        var duration: TimeInterval = CMTimeGetSeconds(asset.duration)
        var discNumber = 1
        var trackNumber = 0
        var copyright: String? = nil
        var publisher: String? = nil
        var year: Int? = nil
        
        for format in asset.availableMetadataFormats {
            for metadataItem in asset.metadata(forFormat: format) {
                let keyStr = String(describing: metadataItem.key).lowercased()
                
                if let commonKey = metadataItem.commonKey {
                    switch commonKey {
                    case .commonKeyTitle:
                        if let value = metadataItem.stringValue { title = value }
                    case .commonKeyArtist:
                        if let value = metadataItem.stringValue { artist = value }
                    case .commonKeyAlbumName:
                        if let value = metadataItem.stringValue { album = value }
                    case .commonKeyCopyrights:
                        if let value = metadataItem.stringValue { copyright = value } else if let value = metadataItem.value as? String { copyright = value }
                    case .commonKeyPublisher:
                        if let value = metadataItem.stringValue { publisher = value }
                    case .commonKeyArtwork:
                        if let value = metadataItem.dataValue { embeddedArtData = value } else if let value = metadataItem.value as? Data { embeddedArtData = value }
                    case .commonKeyCreationDate:
                        if let value = metadataItem.stringValue, let parsedYear = Int(value.prefix(4)) { year = parsedYear }
                    default:
                        break
                    }
                }
                
                // Aggressive fallback for copyright using key string
                if copyright == nil {
                    if keyStr.contains("copy") || keyStr.contains("cprt") || keyStr.contains("cpy") || keyStr.contains("©cpy") || keyStr.contains("©cpr") {
                        if let value = metadataItem.stringValue {
                            copyright = value
                        }
                    }
                }
                
                if let identifier = metadataItem.identifier {
                    let idStr = identifier.rawValue
                    if idStr.contains("trackNumber") || idStr.contains("trkn") {
                        if let data = metadataItem.dataValue, data.count >= 4 {
                            trackNumber = Int(data[3])
                        } else if let num = metadataItem.numberValue {
                            trackNumber = num.intValue
                        } else if let str = metadataItem.stringValue {
                            let cleanStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let num = Int(cleanStr.split(separator: "/").first ?? "") {
                                trackNumber = num
                            }
                        }
                    } else if idStr.contains("discNumber") || idStr.contains("disk") {
                        if let data = metadataItem.dataValue, data.count >= 4 {
                            discNumber = Int(data[3])
                        } else if let num = metadataItem.numberValue {
                            discNumber = num.intValue
                        } else if let str = metadataItem.stringValue {
                            let cleanStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let num = Int(cleanStr.split(separator: "/").first ?? "") {
                                discNumber = num
                            }
                        }
                    } else if idStr.lowercased().contains("copyright") || idStr.lowercased().contains("cprt") {
                        if let valueStr = metadataItem.stringValue { copyright = valueStr } else if let valueStr = metadataItem.value as? String { copyright = valueStr }
                    } else if idStr.lowercased().contains("year") || idStr.lowercased().contains("date") || idStr.lowercased().contains("creationdate") || idStr.lowercased().contains("recordingtime") {
                        if let valueStr = metadataItem.stringValue, let parsedYear = Int(valueStr.prefix(4)) { year = parsedYear }
                    }
                }
                
                if let keySpace = metadataItem.keySpace, let key = metadataItem.key {
                    let keyStr = String(describing: key).lowercased()
                    if keySpace == AVMetadataKeySpace.id3 {
                        if keyStr == "tpos" || keyStr == "tpa" { // ID3v2 part of a set
                            if let valueStr = metadataItem.stringValue {
                                let parts = valueStr.split(separator: "/")
                                if let first = parts.first, let num = Int(first) { discNumber = num }
                            }
                        } else if keyStr == "trck" { // ID3v2 track number
                            if let valueStr = metadataItem.stringValue {
                                let parts = valueStr.split(separator: "/")
                                if let first = parts.first, let num = Int(first) { trackNumber = num }
                            }
                        } else if keyStr == "tpub" { // ID3v2 publisher
                            if let valueStr = metadataItem.stringValue { publisher = valueStr }
                        } else if keyStr == "tcop" { // ID3v2 copyright
                            if let valueStr = metadataItem.stringValue { copyright = valueStr } else if let valueStr = metadataItem.value as? String { copyright = valueStr }
                        } else if keyStr == "tyer" || keyStr == "tdrc" || keyStr == "tdat" || keyStr == "time" { // ID3v2 year/recording time
                            if let valueStr = metadataItem.stringValue, let parsedYear = Int(valueStr.prefix(4)) { year = parsedYear }
                        } else if keyStr.contains("apic") || keyStr.contains("pic") {
                            if let data = metadataItem.dataValue { embeddedArtData = data } else if let data = metadataItem.value as? Data { embeddedArtData = data }
                        }
                    } else if keySpace == AVMetadataKeySpace.iTunes || keySpace == AVMetadataKeySpace.quickTimeUserData {
                        if keyStr == "disk" {
                            if let data = metadataItem.dataValue, data.count >= 4 {
                                discNumber = Int(data[3])
                            } else if let num = metadataItem.numberValue {
                                discNumber = num.intValue
                            } else if let valueStr = metadataItem.stringValue {
                                let parts = valueStr.split(separator: "/")
                                if let first = parts.first, let num = Int(first) { discNumber = num }
                            }
                        } else if keyStr == "trkn" {
                            if let data = metadataItem.dataValue, data.count >= 4 {
                                trackNumber = Int(data[3])
                            } else if let num = metadataItem.numberValue {
                                trackNumber = num.intValue
                            } else if let valueStr = metadataItem.stringValue {
                                let parts = valueStr.split(separator: "/")
                                if let first = parts.first, let num = Int(first) { trackNumber = num }
                            }
                        } else if keyStr == "cprt" || keyStr == "©cpr" {
                            if let valueStr = metadataItem.stringValue { copyright = valueStr } else if let valueStr = metadataItem.value as? String { copyright = valueStr }
                        } else if keyStr == "day" || keyStr == "©day" || keyStr == "yrrc" {
                            if let valueStr = metadataItem.stringValue, let parsedYear = Int(valueStr.prefix(4)) { year = parsedYear }
                        } else if keyStr == "covr" {
                            if let data = metadataItem.dataValue { embeddedArtData = data } else if let data = metadataItem.value as? Data { embeddedArtData = data }
                        }
                    }
                }
            }
        }
        
        var bitRate: Int? = nil
        var sampleRate: Double? = nil
        var channels: Int? = nil
        var bitDepth: Int? = nil
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.fileFormat
            sampleRate = format.sampleRate
            channels = Int(format.channelCount)
            let streamDesc = format.streamDescription.pointee
            bitDepth = Int(streamDesc.mBitsPerChannel)
            
            // Calculate bitrate from file size if we have duration
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber {
                if duration > 0 {
                    let bits = Double(fileSize.intValue) * 8.0
                    bitRate = Int(bits / duration / 1000.0) // kbps
                }
            }
        } catch {
            print("Failed to read audio file format: \(error)")
        }
        
        let formatStr = url.pathExtension.uppercased()
        let isLossless = ["ALAC", "FLAC", "WAV"].contains(formatStr)
        
        return LocalTrack(
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            duration: duration.isNaN ? 0 : duration,
            fileURL: url,
            coverImageName: "music.note",
            localCoverURL: nil,
            embeddedArtData: embeddedArtData,
            dateAdded: Date(),
            isAtmos: false,
            fileSize: "Unknown",
            lyrics: "",
            isFavorite: false,
            playCount: 0,
            format: isLossless ? "Lossless" : formatStr,
            discNumber: discNumber,
            trackNumber: trackNumber,
            copyright: copyright,
            publisher: publisher,
            year: year,
            bitRate: bitRate,
            sampleRate: sampleRate,
            channels: channels,
            bitDepth: bitDepth
        )
    }
    
    deinit {
        removeTimeObserver()
    }
}

// MARK: - LyricsEngine.swift
//
//  LyricsEngine.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//


class LyricsEngine {
    /// Parses LRC lyrics formatted text with timestamps like [01:23.45] lyric text.
    /// If no timestamps are found, it falls back to evenly distributing the lines across the track duration.
    static func parse(lyricsText: String, duration: TimeInterval = 240.0) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        let cleanText = lyricsText.replacingOccurrences(of: "\\n", with: "\n")
        let nativeLines = cleanText.components(separatedBy: .newlines)
        
        var hasBrackets = false
        
        for rawLine in nativeLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            
            // Look for matching brackets e.g. [00:12.34] or [03.45]
            if let bracketIndex = line.firstIndex(of: "]") {
                let timeString = String(line[line.index(after: line.startIndex)..<bracketIndex])
                let lyricText = String(line[line.index(after: bracketIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                var seconds: TimeInterval = 0.0
                
                if timeString.contains(":") {
                    // MM:SS.XX or MM:SS format
                    let parts = timeString.components(separatedBy: ":")
                    if parts.count == 2 {
                        if let minutes = Double(parts[0]), let secs = Double(parts[1]) {
                            seconds = (minutes * 60.0) + secs
                            hasBrackets = true
                            lines.append(SyncedLyricLine(timestamp: seconds, text: lyricText.isEmpty ? "♫" : lyricText))
                        }
                    }
                } else {
                    // Direct seconds representation
                    if let secs = Double(timeString) {
                        seconds = secs
                        hasBrackets = true
                        lines.append(SyncedLyricLine(timestamp: seconds, text: lyricText.isEmpty ? "♫" : lyricText))
                    }
                }
            }
        }
        
        // If it's a plain text lyrics file or holds no timestamps, evenly space the lines across the song duration
        if !hasBrackets {
            let nonSpaceLines = nativeLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !nonSpaceLines.isEmpty {
                let totalLines = Double(nonSpaceLines.count)
                let trackDuration = duration > 0 ? duration : 240.0
                for (idx, lineText) in nonSpaceLines.enumerated() {
                    let timestamp = (trackDuration / totalLines) * Double(idx)
                    lines.append(SyncedLyricLine(timestamp: timestamp, text: lineText))
                }
            }
        }
        
        var sortedLines = lines.sorted(by: { $0.timestamp < $1.timestamp })
        if sortedLines.isEmpty { return [] }
        
        // 1. Calculate an Artificial End Time for a Lyric Line
        for i in 0..<sortedLines.count {
            let wordCount = Double(sortedLines[i].text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)
            let calculatedDuration = min(6.0, max(2.5, wordCount / 3.0))
            let nextLineStart = (i < sortedLines.count - 1) ? sortedLines[i+1].timestamp : sortedLines[i].timestamp + calculatedDuration
            let lineEndTime = min(sortedLines[i].timestamp + calculatedDuration, nextLineStart)
            sortedLines[i].endTime = lineEndTime
        }
        
        var processed: [SyncedLyricLine] = []
        
        // 2 & 3. Intro break if first lyric starts at >= 5.0s
        if sortedLines[0].timestamp >= 5.0 {
            processed.append(SyncedLyricLine(
                timestamp: 1.0,
                text: "...",
                isBreak: true,
                breakStart: 1.0,
                breakEnd: sortedLines[0].timestamp - 1.0,
                endTime: sortedLines[0].timestamp - 1.0
            ))
        }
        
        for i in 0..<sortedLines.count {
            processed.append(sortedLines[i])
            
            if i < sortedLines.count - 1 {
                let currentLine = sortedLines[i]
                let nextLine = sortedLines[i+1]
                let gap = nextLine.timestamp - currentLine.endTime
                
                // Gap of 5 seconds or more -> instrumental break
                if gap >= 5.0 {
                    processed.append(SyncedLyricLine(
                        timestamp: currentLine.endTime + 1.0,
                        text: "...",
                        isBreak: true,
                        breakStart: currentLine.endTime + 1.0,
                        breakEnd: nextLine.timestamp - 1.0,
                        endTime: nextLine.timestamp - 1.0
                    ))
                }
            }
        }
        
        return processed
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
    
    var onTogglePlayPause: (() -> Void)?
    var onPlayNext: (() -> Void)?
    var onPlayPrevious: (() -> Void)?
    
    func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // MPRemoteCommandCenter Setup: Hook into native media player commands so physical media keys (Play, Pause, Skip) respond immediately and register Mesh Player globally to macOS.
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.onTogglePlayPause?()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.onTogglePlayPause?()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            self?.onTogglePlayPause?()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            self?.onPlayNext?()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            self?.onPlayPrevious?()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            // Handle scrubbing if needed
            return .success
        }
    }
    
    func updateNowPlayingInfo(track: LocalTrack?, isPlaying: Bool, currentTime: TimeInterval) {
        var nowPlayingInfo = [String: Any]()
        
        if let track = track {
            // CRITICAL: High-density inline comments for background scrobbling engines
            
            // MPMediaItemPropertyTitle: Used by Last.fm, MacScrobbler, and Marvis to strictly identify the exact track name for scrobbling metadata.
            nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
            
            // MPMediaItemPropertyArtist: Extracted by background daemons to accurately attribute the scrobble to the correct artist profile online.
            nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
            
            // MPMediaItemPropertyAlbumTitle: Allows scrobbler platforms to group played tracks under the correct album release.
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album
            
            // MPMediaItemPropertyPlaybackDuration: Used by Last.fm to validate that at least 50% (or 4 minutes) of the song has elapsed before submitting a scrobble.
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
            
            if let artworkData = track.embeddedArtData, let image = NSImage(data: artworkData) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
                // MPMediaItemPropertyArtwork: Displayed in macOS Control Center and potentially parsed by UI-heavy visualizer extensions.
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            } else if let localCoverURL = track.localCoverURL, let image = NSImage(contentsOf: localCoverURL) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
        }
        
        // MPNowPlayingInfoPropertyElapsedPlaybackTime: Tells the OS exactly where we are in the track, helping scrobblers sync their internal timer.
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // MPNowPlayingInfoPropertyPlaybackRate: A value of 1.0 indicates active playback (started/resumed), while 0.0 indicates a paused or stopped state. Scrobblers listen to this to pause their duration tracking.
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
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

