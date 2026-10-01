//
//  MobileLastFM.swift
//  Mesh Player iOS
//
//  Last.fm scrobbling on the iPhone. Connecting happens on the Mac; its login arrives with the
//  next sync (kept in the Keychain) and the iPhone scrobbles to the same account: "now playing"
//  when a song starts, a scrobble after half the song or 4 minutes, queued while offline.
//

import Combine
import CryptoKit
import Foundation

final class MobileLastFM: ObservableObject {
    static let shared = MobileLastFM()

    nonisolated struct Pending: Codable, Hashable, Sendable {
        var artist: String
        var track: String
        var album: String
        var albumArtist: String?
        var duration: Int
        var timestamp: Int
    }

    @Published private(set) var username: String?
    @Published private(set) var macEnabled = false
    @Published private(set) var pending: [Pending] = []
    @Published private(set) var lastScrobbled: String?
    @Published private(set) var lastError: String?
    /// Lets the iPhone stop scrobbling even when the Mac has it on.
    @Published var enabledHere: Bool = UserDefaults.standard.object(forKey: "lastfm.enabledHere") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabledHere, forKey: "lastfm.enabledHere"); if enabledHere { scheduleFlush(after: 1) } }
    }

    private var apiKey: String?
    private var apiSecret: String?
    private var sessionKey: String?
    private var syncLoves = false
    private var flushTask: Task<Void, Never>?
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    private static var queueURL: URL {
        MobileLibrary.root.appendingPathComponent("lastfm-queue.json")
    }

    var isConnected: Bool { sessionKey != nil && apiKey != nil && apiSecret != nil }
    var isActive: Bool { isConnected && macEnabled && enabledHere }

    private init() {
        apiKey = Keychain.get("lastfm.ios.apiKey")
        apiSecret = Keychain.get("lastfm.ios.apiSecret")
        sessionKey = Keychain.get("lastfm.ios.session")
        username = UserDefaults.standard.string(forKey: "lastfm.ios.username")
        macEnabled = UserDefaults.standard.bool(forKey: "lastfm.ios.macEnabled")
        syncLoves = UserDefaults.standard.bool(forKey: "lastfm.ios.syncLoves")
        if let data = try? Data(contentsOf: Self.queueURL), let queue = try? JSONDecoder().decode([Pending].self, from: data) { pending = queue }
        if !pending.isEmpty { scheduleFlush(after: 5) }
    }

    /// Takes the login from the Mac's sync settings (nil: the Mac is disconnected).
    func update(from login: SyncLastFM?) {
        guard let login else {
            for key in ["lastfm.ios.apiKey", "lastfm.ios.apiSecret", "lastfm.ios.session"] { Keychain.delete(key) }
            apiKey = nil; apiSecret = nil; sessionKey = nil
            username = nil
            macEnabled = false
            UserDefaults.standard.removeObject(forKey: "lastfm.ios.username")
            UserDefaults.standard.set(false, forKey: "lastfm.ios.macEnabled")
            return
        }
        Keychain.set(login.apiKey, for: "lastfm.ios.apiKey")
        Keychain.set(login.apiSecret, for: "lastfm.ios.apiSecret")
        Keychain.set(login.sessionKey, for: "lastfm.ios.session")
        apiKey = login.apiKey; apiSecret = login.apiSecret; sessionKey = login.sessionKey
        username = login.username
        macEnabled = login.scrobbleEnabled
        syncLoves = login.syncLoves
        UserDefaults.standard.set(login.username, forKey: "lastfm.ios.username")
        UserDefaults.standard.set(login.scrobbleEnabled, forKey: "lastfm.ios.macEnabled")
        UserDefaults.standard.set(login.syncLoves, forKey: "lastfm.ios.syncLoves")
        scheduleFlush(after: 2)
    }

    // MARK: Playback hooks

    func nowPlaying(_ song: Song) {
        guard isActive, let sk = sessionKey else { return }
        var params = ["artist": song.artist, "track": song.title, "duration": String(Int(song.duration)), "sk": sk]
        if !song.album.isEmpty { params["album"] = song.album }
        Task { _ = try? await self.call("track.updateNowPlaying", params) }
    }

    func scrobble(_ song: Song, startedAt: Date) {
        guard isActive, song.duration >= 30 else { return }
        pending.append(Pending(artist: song.artist, track: song.title, album: song.album, albumArtist: song.info.albumArtist,
                               duration: Int(song.duration), timestamp: Int(startedAt.timeIntervalSince1970)))
        saveQueue()
        scheduleFlush(after: 1)
    }

    func setLoved(_ song: Song, loved: Bool) {
        guard isActive, syncLoves, let sk = sessionKey else { return }
        Task { _ = try? await self.call(loved ? "track.love" : "track.unlove", ["artist": song.artist, "track": song.title, "sk": sk]) }
    }

    func flushNow() { scheduleFlush(after: 0) }

    // MARK: Queue

    private func saveQueue() {
        let snapshot = pending
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.queueURL, options: .atomic) }
        }
    }

    private func scheduleFlush(after seconds: Double) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        guard isActive, let sk = sessionKey, !pending.isEmpty else { return }
        let cutoff = Int(Date().timeIntervalSince1970) - 13 * 86_400
        pending.removeAll { $0.timestamp < cutoff }
        while !pending.isEmpty {
            let batch = Array(pending.prefix(50))
            var params: [String: String] = ["sk": sk]
            for (i, s) in batch.enumerated() {
                params["artist[\(i)]"] = s.artist
                params["track[\(i)]"] = s.track
                params["timestamp[\(i)]"] = String(s.timestamp)
                params["duration[\(i)]"] = String(s.duration)
                if !s.album.isEmpty { params["album[\(i)]"] = s.album }
                if let aa = s.albumArtist, !aa.isEmpty { params["albumArtist[\(i)]"] = aa }
            }
            do {
                _ = try await call("track.scrobble", params)
                pending.removeFirst(batch.count)
                if let last = batch.last { lastScrobbled = "\(last.artist) — \(last.track)" }
                lastError = nil
                saveQueue()
            } catch APIError.api(let code, let message) where code == 9 {
                lastError = "Last.fm signed you out (\(message)). Connect again on your Mac and sync."
                return
            } catch {
                scheduleFlush(after: 120)
                return
            }
        }
    }

    // MARK: API

    enum APIError: Error {
        case api(Int, String)
        case badResponse
    }

    private func call(_ method: String, _ extra: [String: String]) async throws -> [String: Any] {
        guard let apiKey, let apiSecret else { throw APIError.badResponse }
        var params = extra
        params["method"] = method
        params["api_key"] = apiKey
        let raw = params.keys.sorted().map { $0 + (params[$0] ?? "") }.joined() + apiSecret
        params["api_sig"] = Insecure.MD5.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        params["format"] = "json"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = params.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }.joined(separator: "&")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("MeshPlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.badResponse }
        if let code = json["error"] as? Int { throw APIError.api(code, json["message"] as? String ?? "Error \(code)") }
        return json
    }
}
