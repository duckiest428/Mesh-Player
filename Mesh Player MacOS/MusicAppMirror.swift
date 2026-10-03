//
//  MusicAppMirror.swift
//  Mesh Player
//
//  An alternative way to scrobble: while Mesh Player plays a song, the Music app plays the same
//  track from your Music library in step with it (same position, pausing and seeking along) with
//  Music's own volume at zero. Music then records the play itself, so its play counts, Apple
//  Music Replay and anything that scrobbles from the Music app (Last.fm's desktop scrobbler,
//  NepTunes, …) see it. Music's volume is put back when mirroring stops.
//

import AppKit
import Combine
import Foundation

@MainActor
final class MusicAppMirror: ObservableObject {
    static let shared = MusicAppMirror()

    enum Status: Equatable {
        case off
        case idle
        case mirroring(String)
        case notInMusic(String)
        case failed(String)
    }

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "musicMirror.enabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "musicMirror.enabled")
            if isEnabled {
                status = .idle
                if let track = engine?.currentTrack, engine?.isPlaying == true { trackStarted(track) }
            } else {
                stopMirroring()
                status = .off
            }
        }
    }

    @Published private(set) var status: Status = .off

    private weak var engine: AudioEngineManager?
    private var cancellables: Set<AnyCancellable> = []
    private var mirroredTrackID: UUID?
    /// The Music track name being mirrored, to spot when Music is skipped from outside.
    private var mirroredName: String?
    private var resyncTimer: Timer?
    /// When we last told Music to do something; its own notifications right after are ours.
    private var lastCommand = Date.distantPast
    /// Music's volume before mirroring muted it (kept in UserDefaults in case the app quits).
    private var savedVolume: Int? {
        get { UserDefaults.standard.object(forKey: "musicMirror.savedVolume") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "musicMirror.savedVolume") }
    }

    private init() {}

    /// Hooks into the playback engine. Called once at launch.
    func attach(to engine: AudioEngineManager) {
        self.engine = engine
        status = isEnabled ? .idle : .off
        // A previous session that quit while mirroring left Music muted.
        if !isEnabled || engine.currentTrack == nil { restoreVolume() }
        engine.$isPlaying
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] playing in
                Task { @MainActor in self?.playbackChanged(playing) }
            }
            .store(in: &cancellables)
        // Media keys or AirPods that reach Music while it's mirroring are passed on to us.
        DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.Music.playerInfo"))
            .sink { [weak self] note in
                let info = note.userInfo ?? [:]
                let state = info["Player State"] as? String
                let name = info["Name"] as? String
                MainActor.assumeIsolated { self?.musicChanged(state: state, name: name) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.stopMirroring() } }
            .store(in: &cancellables)
    }

    // MARK: Engine events

    func trackStarted(_ track: LocalTrack) {
        guard isEnabled else { return }
        let position = engine?.currentTime ?? 0
        let lookup = Self.lookupClause(for: track)
        let script = """
        tell application "Music"
            set previousVolume to sound volume
            set found to (\(lookup))
            if (count of found) is 0 then return "missing|" & previousVolume
            if sound volume is not 0 then set previousVolume to sound volume
            set sound volume to 0
            play item 1 of found with once
            try
                set player position to \(Self.number(position))
            end try
            return "ok|" & previousVolume
        end tell
        """
        guard let result = run(script)?.stringValue else {
            status = .failed("Couldn't control the Music app. Allow Mesh Player under System Settings › Privacy & Security › Automation.")
            mirroredTrackID = nil
            return
        }
        let parts = result.split(separator: "|")
        if savedVolume == nil, parts.count == 2, let volume = Int(parts[1]), volume > 0 { savedVolume = volume }
        if parts.first == "ok" {
            mirroredTrackID = track.id
            mirroredName = nil
            status = .mirroring(track.title)
            startResync()
            // Music playing would otherwise take over the media keys and AirPods.
            engine?.reassertNowPlaying()
        } else {
            // Not in the Music library: stop whatever Music was doing so it doesn't play on silently.
            if mirroredTrackID != nil { run("tell application \"Music\" to pause") }
            mirroredTrackID = nil
            status = .notInMusic(track.title)
        }
    }

    func seeked(to time: TimeInterval) {
        guard isEnabled, mirroredTrackID != nil else { return }
        run("tell application \"Music\" to set player position to \(Self.number(time))")
    }

    private func playbackChanged(_ playing: Bool) {
        guard isEnabled, let engine else { return }
        if playing {
            if let track = engine.currentTrack {
                if mirroredTrackID == track.id {
                    run("""
                    tell application "Music"
                        set sound volume to 0
                        play
                        set player position to \(Self.number(engine.currentTime))
                    end tell
                    """)
                    startResync()
                    engine.reassertNowPlaying()
                } else {
                    trackStarted(track)
                }
            }
        } else if mirroredTrackID != nil {
            run("tell application \"Music\" to pause")
            resyncTimer?.invalidate()
        }
    }

    /// Music changed state. Changes we caused are ignored; anything else came from the media
    /// keys, AirPods or Control Center while Music had them, so Mesh Player does the same.
    private func musicChanged(state: String?, name: String?) {
        guard isEnabled, mirroredTrackID != nil, let engine, let state else { return }
        if state == "Playing", mirroredName == nil { mirroredName = name }
        guard Date().timeIntervalSince(lastCommand) > 2 else { return }
        switch state {
        case "Paused", "Stopped":
            // Music reaching the end of its copy a moment early isn't a pause.
            if engine.isPlaying && engine.currentTime < engine.duration - 6 { engine.pause() }
        case "Playing":
            if let name, let mirroredName, name != mirroredName {
                // Skipped in Music: skip here too (which mirrors the new song).
                engine.onPlayNext?()
            } else if !engine.isPlaying {
                engine.play()
            }
        default:
            break
        }
        engine.reassertNowPlaying()
    }

    /// Keeps Music within a couple of seconds of Mesh Player (the two drift apart slowly).
    private func startResync() {
        resyncTimer?.invalidate()
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled, self.mirroredTrackID != nil, let engine = self.engine, engine.isPlaying else { return }
                self.run("""
                tell application "Music"
                    if player state is playing then
                        if (player position - \(Self.number(engine.currentTime))) > 2 or (\(Self.number(engine.currentTime)) - player position) > 2 then set player position to \(Self.number(engine.currentTime))
                    end if
                end tell
                """)
            }
        }
    }

    private func stopMirroring() {
        resyncTimer?.invalidate()
        resyncTimer = nil
        if mirroredTrackID != nil { run("tell application \"Music\" to pause") }
        mirroredTrackID = nil
        mirroredName = nil
        restoreVolume()
    }

    private func restoreVolume() {
        guard let volume = savedVolume else { return }
        // Only touch Music if it's running; launching it just to set the volume would be odd.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return }
        run("tell application \"Music\" to set sound volume to \(volume)")
        savedVolume = nil
    }

    // MARK: AppleScript

    /// Finds the track in Music: by its persistent ID when it was imported from Music, else by
    /// title, artist and album.
    private static func lookupClause(for track: LocalTrack) -> String {
        if let hex = hex(track.persistentID) {
            return "every track of library playlist 1 whose persistent ID is \"\(hex)\""
        }
        let title = escape(track.title), artist = escape(track.artist), album = escape(track.album)
        return "every track of library playlist 1 whose name is \"\(title)\" and artist is \"\(artist)\" and album is \"\(album)\""
    }

    private static func hex(_ decimal: String?) -> String? {
        guard let decimal, let value = UInt64(decimal) else { return nil }
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 16 - text.count)) + text
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// AppleScript wants "12.5", never a locale's "12,5".
    private static func number(_ value: TimeInterval) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(0, value))
    }

    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        lastCommand = Date()
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { print("Music mirror script error: \(error)") }
        return error == nil ? result : nil
    }
}
