//
//  MeshSync.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  The Mac → iPhone sync protocol. The iPhone listens on a fixed TCP port and advertises itself
//  over Bonjour; the Mac connects either over the network (Wi-Fi / peer-to-peer Wi-Fi) or through
//  a USB cable (usbmuxd tunnels a connection to the same port). Both ends then speak the same
//  framed protocol:
//
//    frame = [UInt32 payload length, big endian][UInt8 kind][payload]
//    kind 1 = JSON-encoded SyncMessage, kind 2 = raw bytes of the file currently being sent
//
//  Session (the Mac is the source of truth; the iPhone reports what it has and what changed):
//    Mac → hello              iPhone → hello (+ awaitingApproval the first time) → inventory
//    Mac → requestUploads     iPhone → fileBegin, chunk…, fileEnd per song added on the iPhone → uploadsDone
//    Mac → manifest (library, settings and play history the iPhone should have)
//    Mac → fileBegin, chunk…, fileEnd   for every song / artwork the iPhone is missing or has damaged
//    Mac → finished           iPhone → complete (after checking files and removing what's no longer synced)
//

import Foundation
import Network

nonisolated enum MeshSync {
    static let serviceType = "_meshsync._tcp"
    static let port: UInt16 = 47_811
    static let protocolVersion = 2
    static let chunkSize = 256 * 1024
}

// MARK: - Models

nonisolated struct SyncTrack: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var albumArtist: String?
    var genre: String
    var duration: Double
    var year: Int?
    var trackNumber: Int
    var discNumber: Int
    var isAtmos: Bool
    var format: String
    var lyrics: String
    var copyright: String?
    var isFavorite: Bool
    var playCount: Int
    var lastPlayedDate: Date?
    var dateAdded: Date
    var artworkKey: String
    var fileExtension: String
    var fileSize: Int64
    var bitDepth: Int?
    var sampleRate: Double?
}

nonisolated struct SyncPlaylist: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var description: String
    var trackIds: [UUID]
    var isSmart: Bool
    var isFavorites: Bool
    var dateModified: Date?
    /// Custom cover sent as an artwork file under this key.
    var artworkKey: String? = nil
}

/// One counted play, with a stable id so both devices can merge histories without duplicates.
nonisolated struct SyncPlayEvent: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var trackId: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: Double
    var timestamp: Date
}

/// Last.fm login made on the Mac, so the iPhone can scrobble to the same account.
nonisolated struct SyncLastFM: Codable, Hashable, Sendable {
    var apiKey: String
    var apiSecret: String
    var sessionKey: String
    var username: String
    var scrobbleEnabled: Bool
    var syncLoves: Bool
}

/// Settings the Mac decides for both devices.
nonisolated struct SyncSettings: Codable, Hashable, Sendable {
    var themeName: String
    var mergeCollaborations: Bool
    /// Songs hidden from the library (they still play inside their playlists).
    var hiddenTrackIds: [UUID]
    var favoriteArtists: [String]
    var animatedArtwork: Bool
    var lastFM: SyncLastFM?
}

nonisolated struct SyncHello: Codable, Sendable {
    var deviceId: String
    var name: String
    var platform: String
    var version: Int
}

/// What changed on the iPhone since the last sync, sent back so the Mac can merge it.
nonisolated struct SyncTrackChange: Codable, Sendable {
    var playsSinceSync: Int
    var lastPlayed: Date?
    var isFavorite: Bool?
}

nonisolated struct SyncInventory: Codable, Sendable {
    /// Track id (uuidString) → size of the audio file already on the iPhone.
    var files: [String: Int64]
    var artworkKeys: [String]
    /// Track id (uuidString) → plays / favorite changes made on the iPhone.
    var changes: [String: SyncTrackChange]
    /// Playlists created or edited on the iPhone.
    var playlists: [SyncPlaylist]
    var freeSpace: Int64?
    /// Artwork key → file size, so damaged (empty) covers are sent again.
    var artworkSizes: [String: Int64]? = nil
    /// Plays counted on the iPhone since the last sync.
    var playEvents: [SyncPlayEvent]? = nil
    /// Playlists deleted on the iPhone since the last sync.
    var deletedPlaylists: [UUID]? = nil
    /// Songs added on the iPhone (Files / Finder) that the Mac doesn't have yet.
    var localSongs: [SyncTrack]? = nil
}

nonisolated struct SyncManifest: Codable, Sendable {
    var tracks: [SyncTrack]
    var playlists: [SyncPlaylist]
    var sourceName: String
    var settings: SyncSettings? = nil
    /// The Mac's full play history (the iPhone keeps it for Statistics and Replay).
    var playHistory: [SyncPlayEvent]? = nil
}

nonisolated struct SyncFileHeader: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case audio, artwork }
    var kind: Kind
    var id: String
    var fileExtension: String
    var size: Int64
}

nonisolated struct SyncProgressInfo: Codable, Sendable {
    var filesDone: Int
    var filesTotal: Int
    var bytesDone: Int64
    var bytesTotal: Int64
}

nonisolated enum SyncMessage: Codable, Sendable {
    case hello(SyncHello)
    case awaitingApproval
    case denied(String)
    case inventory(SyncInventory)
    case manifest(SyncManifest)
    case progress(SyncProgressInfo)
    case fileBegin(SyncFileHeader)
    case fileEnd
    case finished
    case complete(String)
    /// Mac → iPhone: send these songs that were added on the iPhone (track ids).
    case requestUploads([String])
    case uploadsDone
}

nonisolated enum SyncError: LocalizedError {
    case closed
    case protocolError(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .closed: return "The connection was closed."
        case .protocolError(let text): return text
        case .timedOut: return "The device stopped responding."
        }
    }
}

// MARK: - Transport

nonisolated protocol SyncTransport: AnyObject, Sendable {
    func send(_ data: Data) async throws
    func receive(exactly count: Int) async throws -> Data
    func close()
}

/// Network.framework connection (Wi-Fi, peer-to-peer Wi-Fi, loopback for USB on the iPhone side).
nonisolated final class NWSyncTransport: SyncTransport, @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "mesh.sync.connection")

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Starts the connection and waits until it is ready (or fails).
    func start(timeout: TimeInterval = 15) async throws {
        let once = OnceFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: SyncError.closed) }
                case .waiting(let error):
                    // Unreachable for now; give it a moment, then fail.
                    self.queue.asyncAfter(deadline: .now() + 6) {
                        if once.claim() { continuation.resume(throwing: error) }
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(throwing: SyncError.timedOut) }
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            let part: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: count - buffer.count) { data, _, isComplete, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let data, !data.isEmpty { continuation.resume(returning: data); return }
                    continuation.resume(throwing: isComplete ? SyncError.closed : SyncError.protocolError("Empty read"))
                }
            }
            buffer.append(part)
        }
        return buffer
    }

    func close() {
        connection.cancel()
    }
}

nonisolated final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Framing

nonisolated final class SyncChannel: @unchecked Sendable {
    enum Frame {
        case message(SyncMessage)
        case chunk(Data)
    }

    let transport: SyncTransport
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    init(_ transport: SyncTransport) {
        self.transport = transport
    }

    func send(_ message: SyncMessage) async throws {
        try await sendFrame(kind: 1, payload: try encoder.encode(message))
    }

    func sendChunk(_ data: Data) async throws {
        try await sendFrame(kind: 2, payload: data)
    }

    private func sendFrame(kind: UInt8, payload: Data) async throws {
        var header = Data(count: 5)
        let length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: length) { header.replaceSubrange(0..<4, with: $0) }
        header[4] = kind
        try await transport.send(header + payload)
    }

    func next() async throws -> Frame {
        let header = try await transport.receive(exactly: 5)
        let length = header.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length <= 256 * 1024 * 1024 else { throw SyncError.protocolError("Frame too large") }
        let payload = try await transport.receive(exactly: length)
        switch header[header.startIndex + 4] {
        case 1: return .message(try decoder.decode(SyncMessage.self, from: payload))
        case 2: return .chunk(payload)
        default: throw SyncError.protocolError("Unknown frame")
        }
    }

    /// Next frame that must be a message.
    func nextMessage() async throws -> SyncMessage {
        guard case .message(let message) = try await next() else { throw SyncError.protocolError("Expected a message") }
        return message
    }

    /// Streams a file as fileBegin + chunks + fileEnd. `onBytes` reports progress.
    func sendFile(_ url: URL, header: SyncFileHeader, onBytes: (Int) -> Void) async throws {
        try await send(.fileBegin(header))
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let data = try handle.read(upToCount: MeshSync.chunkSize) ?? Data()
            if data.isEmpty { break }
            try await sendChunk(data)
            onBytes(data.count)
        }
        try await send(.fileEnd)
    }

    func close() { transport.close() }
}

/// A stable id for this installation, used so the iPhone can remember which Macs it trusts.
nonisolated enum SyncIdentity {
    static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: "sync.deviceId") { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "sync.deviceId")
        return id
    }
}
