//
//  LastFM.swift
//  Mesh Player
//
//  Last.fm scrobbling using the official web API (https://www.last.fm/api):
//   • desktop authentication (auth.getToken → approve in the browser → auth.getSession)
//   • track.updateNowPlaying when a song starts
//   • track.scrobble once a song has played for half its length or 4 minutes (songs over 30 s),
//     queued on disk and sent in batches so plays made offline are never lost
//   • optional track.love / track.unlove when favorites change
//

import AppKit
import Combine
import CryptoKit
import Foundation
import Security

nonisolated struct PendingScrobble: Codable, Hashable, Sendable {
    var artist: String
    var track: String
    var album: String
    var albumArtist: String?
    var duration: Int
    var trackNumber: Int?
    var timestamp: Int
}

final class LastFMService: ObservableObject {
    static let shared = LastFMService()

    enum Status: Equatable {
        case disconnected
        case waitingForApproval
        case connected
        case failed(String)
    }

    @Published var apiKey: String { didSet { UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespaces), forKey: "lastfm.apiKey") } }
    @Published var apiSecret: String { didSet { Keychain.set(apiSecret.trimmingCharacters(in: .whitespaces), for: "lastfm.apiSecret") } }
    @Published var isEnabled: Bool { didSet { UserDefaults.standard.set(isEnabled, forKey: "lastfm.enabled") } }
    @Published var syncLoves: Bool { didSet { UserDefaults.standard.set(syncLoves, forKey: "lastfm.syncLoves") } }
    @Published private(set) var username: String?
    @Published private(set) var status: Status = .disconnected
    @Published private(set) var pending: [PendingScrobble] = []
    @Published private(set) var lastScrobbled: String?
    @Published private(set) var scrobbledThisSession = 0

    private var sessionKey: String?
    private var authPoll: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    private static var queueURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lastfm-queue.json")
    }

    private init() {
        let defaults = UserDefaults.standard
        apiKey = defaults.string(forKey: "lastfm.apiKey") ?? ""
        apiSecret = Keychain.get("lastfm.apiSecret") ?? ""
        isEnabled = defaults.object(forKey: "lastfm.enabled") as? Bool ?? true
        syncLoves = defaults.object(forKey: "lastfm.syncLoves") as? Bool ?? true
        sessionKey = Keychain.get("lastfm.session")
        username = defaults.string(forKey: "lastfm.username")
        if sessionKey != nil, username != nil { status = .connected }
        if let data = try? Data(contentsOf: Self.queueURL), let queue = try? JSONDecoder().decode([PendingScrobble].self, from: data) {
            pending = queue
        }
        scheduleFlush(after: 5)
    }

    var hasCredentials: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !apiSecret.trimmingCharacters(in: .whitespaces).isEmpty }
    var isConnected: Bool { status == .connected && sessionKey != nil }
    var isActive: Bool { isEnabled && isConnected }

    // MARK: Authentication

    func connect() {
        guard hasCredentials else {
            status = .failed("Enter your API key and shared secret first.")
            return
        }
        authPoll?.cancel()
        status = .waitingForApproval
        authPoll = Task { [weak self] in
            guard let self else { return }
            do {
                let tokenResponse = try await self.call("auth.getToken", [:], signed: true, post: false)
                guard let token = tokenResponse["token"] as? String else { throw LastFMError.api(0, "Last.fm didn't return a token.") }
                let key = self.apiKey.trimmingCharacters(in: .whitespaces)
                if let url = URL(string: "https://www.last.fm/api/auth/?api_key=\(key)&token=\(token)") {
                    NSWorkspace.shared.open(url)
                }
                // Wait for the user to press "Yes, allow access" in the browser (tokens last 60 minutes).
                for _ in 0..<200 {
                    try await Task.sleep(for: .seconds(3))
                    do {
                        let session = try await self.call("auth.getSession", ["token": token], signed: true, post: false)
                        if let info = session["session"] as? [String: Any], let sk = info["key"] as? String, let name = info["name"] as? String {
                            self.finishLogin(sessionKey: sk, username: name)
                            return
                        }
                    } catch LastFMError.api(let code, _) where code == 14 {
                        continue // not authorised yet
                    }
                }
                self.status = .failed("Timed out waiting for approval on last.fm.")
            } catch is CancellationError {
                if self.status == .waitingForApproval { self.status = .disconnected }
            } catch {
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    func cancelConnect() {
        authPoll?.cancel()
        authPoll = nil
        if status == .waitingForApproval { status = .disconnected }
    }

    private func finishLogin(sessionKey: String, username: String) {
        self.sessionKey = sessionKey
        self.username = username
        Keychain.set(sessionKey, for: "lastfm.session")
        UserDefaults.standard.set(username, forKey: "lastfm.username")
        status = .connected
        scheduleFlush(after: 1)
    }

    /// The login the iPhone uses to scrobble to the same account (sent when syncing).
    func syncCredentials() -> SyncLastFM? {
        guard let sessionKey, let username, hasCredentials else { return nil }
        return SyncLastFM(apiKey: apiKey.trimmingCharacters(in: .whitespaces), apiSecret: apiSecret.trimmingCharacters(in: .whitespaces),
                          sessionKey: sessionKey, username: username, scrobbleEnabled: isEnabled, syncLoves: syncLoves)
    }

    func disconnect() {
        authPoll?.cancel()
        sessionKey = nil
        username = nil
        Keychain.delete("lastfm.session")
        UserDefaults.standard.removeObject(forKey: "lastfm.username")
        status = .disconnected
    }

    // MARK: Playback hooks

    func nowPlaying(_ track: LocalTrack) {
        guard isActive, track.duration >= 30 else { return }
        var params = ["artist": track.artist, "track": track.title, "duration": String(Int(track.duration))]
        if !track.album.isEmpty, track.album != "Unknown Album" { params["album"] = track.album }
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty { params["albumArtist"] = albumArtist }
        if track.trackNumber > 0 { params["trackNumber"] = String(track.trackNumber) }
        Task { [weak self] in
            guard let self, let sk = self.sessionKey else { return }
            params["sk"] = sk
            _ = try? await self.call("track.updateNowPlaying", params, signed: true, post: true)
        }
    }

    /// Called once per play when the scrobble point (half the song or 4 minutes) is reached.
    func scrobble(_ track: LocalTrack, startedAt: Date) {
        guard isEnabled, track.duration >= 30 else { return }
        let entry = PendingScrobble(
            artist: track.artist,
            track: track.title,
            album: track.album == "Unknown Album" ? "" : track.album,
            albumArtist: track.albumArtist,
            duration: Int(track.duration),
            trackNumber: track.trackNumber > 0 ? track.trackNumber : nil,
            timestamp: Int(startedAt.timeIntervalSince1970)
        )
        pending.append(entry)
        saveQueue()
        scheduleFlush(after: 2)
    }

    func setLoved(_ track: LocalTrack, loved: Bool) {
        guard isActive, syncLoves else { return }
        Task { [weak self] in
            guard let self, let sk = self.sessionKey else { return }
            _ = try? await self.call(loved ? "track.love" : "track.unlove", ["artist": track.artist, "track": track.title, "sk": sk], signed: true, post: true)
        }
    }

    // MARK: Queue

    private func saveQueue() {
        let snapshot = pending
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.queueURL, options: .atomic) }
        }
    }

    func flushNow() { scheduleFlush(after: 0) }

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
        // Last.fm rejects scrobbles older than two weeks; drop those rather than retrying forever.
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
                if let n = s.trackNumber { params["trackNumber[\(i)]"] = String(n) }
            }
            do {
                _ = try await call("track.scrobble", params, signed: true, post: true)
                pending.removeFirst(batch.count)
                scrobbledThisSession += batch.count
                if let last = batch.last { lastScrobbled = "\(last.artist) — \(last.track)" }
                saveQueue()
            } catch LastFMError.api(let code, _) where code == 9 {
                disconnect() // session revoked
                status = .failed("Last.fm signed you out. Connect again to keep scrobbling.")
                return
            } catch {
                scheduleFlush(after: 120) // offline or rate limited: keep the queue and retry later
                return
            }
        }
    }

    // MARK: API

    enum LastFMError: LocalizedError {
        case api(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .api(_, let message): return message
            case .badResponse: return "Last.fm sent an unexpected response."
            }
        }
    }

    private func call(_ method: String, _ extra: [String: String], signed: Bool, post: Bool) async throws -> [String: Any] {
        var params = extra
        params["method"] = method
        params["api_key"] = apiKey.trimmingCharacters(in: .whitespaces)
        if signed {
            let raw = params.keys.sorted().map { $0 + (params[$0] ?? "") }.joined() + apiSecret.trimmingCharacters(in: .whitespaces)
            params["api_sig"] = Insecure.MD5.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        params["format"] = "json"

        let query = params.map { "\(Self.encode($0.key))=\(Self.encode($0.value))" }.joined(separator: "&")
        var request: URLRequest
        if post {
            request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(query.utf8)
        } else {
            request = URLRequest(url: URL(string: endpoint.absoluteString + "?" + query)!)
        }
        request.setValue("MeshPlayer/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LastFMError.badResponse }
        if let code = json["error"] as? Int {
            throw LastFMError.api(code, json["message"] as? String ?? "Last.fm error \(code)")
        }
        return json
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
