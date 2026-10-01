//
//  DeviceSync.swift
//  Mesh Player
//
//  Syncs the library to the Mesh Player iPhone app, over the network (Bonjour) or a USB cable
//  (usbmuxd, the macOS service Finder and Xcode use to reach connected iPhones). See
//  Shared/MeshSync.swift for the protocol.
//

import AppKit
import Combine
import Network
import SwiftUI

// MARK: - USB (usbmuxd)

/// Talks to usbmuxd over its Unix socket: lists USB-connected iPhones and opens a tunnel to a
/// TCP port on one of them.
nonisolated enum UsbMux {
    struct Device: Hashable, Sendable {
        let deviceID: Int
        let serial: String
    }

    private static let socketPath = "/var/run/usbmuxd"

    private static func openSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, 103) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { Darwin.close(fd); return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private static func request(_ fd: Int32, _ body: [String: Any]) -> [String: Any]? {
        var message = body
        message["ClientVersionString"] = "mesh-player-1"
        message["ProgName"] = "Mesh Player"
        message["kLibUSBMuxVersion"] = 3
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0) else { return nil }
        var header = [UInt32(16 + plist.count), 1, 8, 1].map { $0.littleEndian }
        var packet = Data(bytes: &header, count: 16)
        packet.append(plist)
        guard writeAll(fd, packet) else { return nil }
        guard let replyHeader = readExactly(fd, 16) else { return nil }
        let length = replyHeader.withUnsafeBytes { Int(UInt32(littleEndian: $0.load(as: UInt32.self))) }
        guard length >= 16, let payload = readExactly(fd, length - 16) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: payload, format: nil)) as? [String: Any]
    }

    /// iPhones connected by cable right now (empty when usbmuxd can't be reached).
    static func listDevices() -> [Device] {
        guard let fd = openSocket() else { return [] }
        defer { Darwin.close(fd) }
        guard let reply = request(fd, ["MessageType": "ListDevices"]),
              let list = reply["DeviceList"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let props = entry["Properties"] as? [String: Any],
                  (props["ConnectionType"] as? String) == "USB",
                  let id = (entry["DeviceID"] as? Int) ?? (props["DeviceID"] as? Int) else { return nil }
            return Device(deviceID: id, serial: props["SerialNumber"] as? String ?? "")
        }
    }

    /// Opens a raw byte tunnel to `port` on the device.
    static func connect(to device: Device, port: UInt16) -> Int32? {
        guard let fd = openSocket() else { return nil }
        guard let reply = request(fd, ["MessageType": "Connect", "DeviceID": device.deviceID, "PortNumber": Int(port.bigEndian)]),
              (reply["Number"] as? Int) == 0 else {
            Darwin.close(fd)
            return nil
        }
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written <= 0 {
                    if written < 0 && errno == EINTR { continue }
                    return false
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return count == 0 }
            while offset < count {
                let n = Darwin.read(fd, base.advanced(by: offset), count - offset)
                if n <= 0 {
                    if n < 0 && errno == EINTR { continue }
                    return false
                }
                offset += n
            }
            return true
        }
        return ok ? data : nil
    }
}

/// Sync transport over a usbmuxd tunnel (a plain socket).
nonisolated final class SocketSyncTransport: SyncTransport, @unchecked Sendable {
    private let fd: Int32
    private let readQueue = DispatchQueue(label: "mesh.sync.usb.read")
    private let writeQueue = DispatchQueue(label: "mesh.sync.usb.write")

    init(fd: Int32) { self.fd = fd }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                if UsbMux.writeAll(self.fd, data) { continuation.resume() } else { continuation.resume(throwing: SyncError.closed) }
            }
        }
    }

    func receive(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            readQueue.async {
                if let data = UsbMux.readExactly(self.fd, count) { continuation.resume(returning: data) } else { continuation.resume(throwing: SyncError.closed) }
            }
        }
    }

    func close() {
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

// MARK: - Controller

final class DeviceSyncController: ObservableObject {
    static let shared = DeviceSyncController()

    struct Device: Identifiable, Hashable {
        enum Route: Hashable {
            case network(NWEndpoint)
            case usb(UsbMux.Device)
        }
        let id: String
        var name: String
        let route: Route
        var isUSB: Bool { if case .usb = route { return true }; return false }
    }

    enum Phase: Equatable {
        case idle
        case connecting
        case waitingForApproval
        case preparing
        case sending
        case finishing
        case done(String)
        case failed(String)
    }

    enum Scope: String, CaseIterable, Identifiable {
        case everything = "Entire library"
        case playlists = "Selected playlists"
        var id: String { rawValue }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var deviceName = ""
    @Published private(set) var filesDone = 0
    @Published private(set) var filesTotal = 0
    @Published private(set) var bytesDone: Int64 = 0
    @Published private(set) var bytesTotal: Int64 = 0
    @Published private(set) var currentItem = ""
    @Published var scope: Scope {
        didSet { UserDefaults.standard.set(scope.rawValue, forKey: "sync.scope") }
    }
    @Published var selectedPlaylists: Set<UUID> {
        didSet { UserDefaults.standard.set(selectedPlaylists.map(\.uuidString), forKey: "sync.playlists") }
    }

    private var browser: NWBrowser?
    private var usbPoll: Task<Void, Never>?
    private var networkDevices: [Device] = []
    private var usbDevices: [Device] = []
    private var session: Task<Void, Never>?
    private var channel: SyncChannel?

    private init() {
        scope = Scope(rawValue: UserDefaults.standard.string(forKey: "sync.scope") ?? "") ?? .everything
        selectedPlaylists = Set((UserDefaults.standard.stringArray(forKey: "sync.playlists") ?? []).compactMap(UUID.init(uuidString:)))
    }

    var isBusy: Bool {
        switch phase {
        case .connecting, .waitingForApproval, .preparing, .sending, .finishing: return true
        default: return false
        }
    }

    // MARK: Discovery

    func startDiscovery() {
        if browser == nil {
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: MeshSync.serviceType, domain: nil), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found: [Device] = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return Device(id: "net-\(name)", name: name, route: .network(result.endpoint))
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.networkDevices = found
                    self.publishDevices()
                }
            }
            browser.start(queue: .main)
            self.browser = browser
        }
        if usbPoll == nil {
            usbPoll = Task { [weak self] in
                while !Task.isCancelled {
                    let found = await Task.detached { UsbMux.listDevices() }.value
                    guard let self else { return }
                    self.usbDevices = found.map { device in
                        let known = self.usbDevices.first { $0.id == "usb-\(device.serial)" }?.name
                        return Device(id: "usb-\(device.serial)", name: known ?? "iPhone (USB)", route: .usb(device))
                    }
                    self.publishDevices()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        usbPoll?.cancel()
        usbPoll = nil
    }

    private func publishDevices() {
        devices = usbDevices + networkDevices
    }

    // MARK: Sync

    func cancel() {
        session?.cancel()
        channel?.close()
        channel = nil
        if isBusy { phase = .failed("Sync cancelled.") }
    }

    func sync(_ device: Device, state: AppStateManager) {
        guard !isBusy else { return }
        phase = .connecting
        deviceName = device.name
        filesDone = 0
        filesTotal = 0
        bytesDone = 0
        bytesTotal = 0
        currentItem = ""
        session = Task { [weak self] in
            guard let self else { return }
            do {
                let transport: SyncTransport
                switch device.route {
                case .network(let endpoint):
                    let parameters = NWParameters.tcp
                    parameters.includePeerToPeer = true
                    let nw = NWSyncTransport(connection: NWConnection(to: endpoint, using: parameters))
                    do {
                        try await nw.start()
                    } catch {
                        throw Self.networkConnectError(error, deviceName: device.name)
                    }
                    transport = nw
                case .usb(let usb):
                    guard let fd = await Task.detached(operation: { UsbMux.connect(to: usb, port: MeshSync.port) }).value else {
                        throw SyncError.protocolError("Couldn't reach Mesh Player on the iPhone over USB. Open the app on the iPhone, unlock it, and make sure you tapped Trust.")
                    }
                    transport = SocketSyncTransport(fd: fd)
                }
                let channel = SyncChannel(transport)
                self.channel = channel
                defer { channel.close() }
                let summary = try await self.run(channel, state: state, usbDevice: device)
                self.phase = .done(summary)
            } catch is CancellationError {
                self.phase = .failed("Sync cancelled.")
            } catch {
                if case .failed = self.phase {} else { self.phase = .failed(error.localizedDescription) }
            }
            self.channel = nil
        }
    }

    /// Turns a failed Wi-Fi connection into something the user can act on.
    private static func networkConnectError(_ error: Error, deviceName: String) -> Error {
        switch error as? NWError {
        case .dns(let code) where code == -65570: // kDNSServiceErr_PolicyDenied
            return SyncError.protocolError("Mesh Player isn't allowed on your local network. Turn it on in System Settings › Privacy & Security › Local Network, then try again.")
        case .posix(.ECONNREFUSED):
            return SyncError.protocolError("\(deviceName) isn't accepting connections. Open Mesh Player on the iPhone, keep it on screen, and try again.")
        default:
            // iOS silently drops connections to apps that aren't allowed Local Network access.
            return SyncError.protocolError("Couldn't connect to \(deviceName). On the iPhone, turn on Local Network for Mesh Player (Settings › Apps › Mesh Player), keep the app open, and try again. A USB cable works too.")
        }
    }

    private func run(_ channel: SyncChannel, state: AppStateManager, usbDevice: Device) async throws -> String {
        try await channel.send(.hello(SyncHello(deviceId: SyncIdentity.deviceId, name: Host.current().localizedName ?? "Mac", platform: "mac", version: MeshSync.protocolVersion)))

        var inventory: SyncInventory?
        while inventory == nil {
            switch try await channel.nextMessage() {
            case .hello(let hello):
                deviceName = hello.name
                guard hello.version >= MeshSync.protocolVersion else {
                    throw SyncError.protocolError("Mesh Player on \(hello.name) is out of date. Install the latest version on the iPhone, then sync again.")
                }
                if usbDevice.isUSB, let idx = usbDevices.firstIndex(where: { $0.id == usbDevice.id }) {
                    usbDevices[idx].name = hello.name
                    publishDevices()
                }
            case .awaitingApproval:
                phase = .waitingForApproval
            case .denied(let reason):
                phase = .failed(reason)
                throw SyncError.protocolError(reason)
            case .inventory(let received):
                inventory = received
            default:
                throw SyncError.protocolError("Unexpected reply from the iPhone.")
            }
        }
        guard let inventory else { throw SyncError.closed }
        phase = .preparing

        // 1. Songs added on the iPhone come to the Mac first: the Mac keeps everything.
        let uploads = (inventory.localSongs ?? []).filter { state.track(withId: $0.id) == nil }
        try await channel.send(.requestUploads(uploads.map(\.id.uuidString)))
        try await receiveUploads(channel, songs: uploads, state: state)

        // 2. Bring the iPhone's plays, favorites and playlists into the Mac library.
        state.mergeSyncChanges(inventory)
        // Playlists made on the iPhone stay on it even when only selected playlists are synced.
        if scope == .playlists {
            for playlist in inventory.playlists where !playlist.isSmart { selectedPlaylists.insert(playlist.id) }
        }

        // 3. Decide what the iPhone should hold.
        let manifest = makeManifest(state: state)
        try await channel.send(.manifest(manifest))

        // 4. Send what's missing, or what's on the iPhone at the wrong size (cut-off or damaged).
        let byId = Dictionary(uniqueKeysWithValues: state.tracks.map { ($0.id, $0) })
        let audio = manifest.tracks.filter { inventory.files[$0.id.uuidString] != $0.fileSize }
        // Covers count as present only when the file isn't empty.
        let haveArt: Set<String> = inventory.artworkSizes.map { sizes in Set(sizes.filter { $0.value > 0 }.keys) } ?? Set(inventory.artworkKeys)
        var artworkTracks: [String: LocalTrack] = [:]
        for synced in manifest.tracks where !haveArt.contains(synced.artworkKey) && artworkTracks[synced.artworkKey] == nil {
            artworkTracks[synced.artworkKey] = byId[synced.id]
        }
        // Albums with no cover at all would otherwise be "missing" on every sync.
        for (key, track) in artworkTracks where !(await ArtworkStore.shared.hasArtwork(for: track)) { artworkTracks[key] = nil }
        // Custom playlist covers.
        var playlistCovers: [String: URL] = [:]
        for playlist in manifest.playlists {
            guard let key = playlist.artworkKey, !haveArt.contains(key),
                  let local = state.playlists.first(where: { $0.id == playlist.id }), let url = state.playlistArtworkURL(local) else { continue }
            playlistCovers[key] = url
        }
        filesTotal = audio.count + artworkTracks.count + playlistCovers.count
        bytesTotal = audio.reduce(0) { $0 + $1.fileSize }
        let free = inventory.freeSpace ?? .max
        if bytesTotal > free {
            throw SyncError.protocolError("Not enough space on \(deviceName): \(ByteCountFormatter.string(fromByteCount: bytesTotal, countStyle: .file)) needed, \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free. Sync fewer playlists.")
        }
        phase = .sending
        try await channel.send(.progress(SyncProgressInfo(filesDone: 0, filesTotal: filesTotal, bytesDone: 0, bytesTotal: bytesTotal)))

        // Artwork first: it's small, and a sync that gets cut off still leaves every song with its cover.
        currentItem = "Artwork"
        for (key, track) in artworkTracks {
            try Task.checkCancellation()
            guard let data = await ArtworkStore.shared.jpegData(for: track, maxPixel: 800) else { filesDone += 1; continue }
            try await channel.send(.fileBegin(SyncFileHeader(kind: .artwork, id: key, fileExtension: "jpg", size: Int64(data.count))))
            try await channel.sendChunk(data)
            try await channel.send(.fileEnd)
            filesDone += 1
        }
        for (key, url) in playlistCovers {
            try Task.checkCancellation()
            guard let data = try? Data(contentsOf: url) else { filesDone += 1; continue }
            try await channel.send(.fileBegin(SyncFileHeader(kind: .artwork, id: key, fileExtension: "jpg", size: Int64(data.count))))
            try await channel.sendChunk(data)
            try await channel.send(.fileEnd)
            filesDone += 1
        }
        for synced in audio {
            try Task.checkCancellation()
            guard let url = byId[synced.id]?.fileURL else { continue }
            currentItem = "\(synced.title) — \(synced.artist)"
            try await channel.sendFile(url, header: SyncFileHeader(kind: .audio, id: synced.id.uuidString, fileExtension: synced.fileExtension, size: synced.fileSize)) { bytes in
                self.bytesDone += Int64(bytes)
            }
            filesDone += 1
        }

        phase = .finishing
        try await channel.send(.finished)
        while true {
            if case .complete(let summary) = try await channel.nextMessage() { return summary }
        }
    }

    /// Receives the songs the iPhone added itself and adds them to the Mac library (same ids, so
    /// the iPhone keeps its plays and playlists for them).
    private func receiveUploads(_ channel: SyncChannel, songs: [SyncTrack], state: AppStateManager) async throws {
        let folder = LibraryManager.shared.mediaDirectory.appendingPathComponent("From iPhone", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var pending = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, Self.localTrack(from: $0)) })
        var received: [LocalTrack] = []
        var current: (header: SyncFileHeader, url: URL?, handle: FileHandle?, data: Data)?
        if !songs.isEmpty { currentItem = "Receiving \(songs.count) song\(songs.count == 1 ? "" : "s") from \(deviceName)" }
        while true {
            switch try await channel.next() {
            case .message(.fileBegin(let header)):
                if header.kind == .audio, let id = UUID(uuidString: header.id) {
                    let url = folder.appendingPathComponent(id.uuidString + "." + header.fileExtension)
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    current = (header, url, try FileHandle(forWritingTo: url), Data())
                } else {
                    current = (header, nil, nil, Data())
                }
            case .chunk(let data):
                if let handle = current?.handle { try handle.write(contentsOf: data) } else { current?.data.append(data) }
            case .message(.fileEnd):
                guard let file = current, let id = UUID(uuidString: file.header.id), var track = pending[id] else { current = nil; break }
                try? file.handle?.close()
                if file.header.kind == .audio, let url = file.url {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
                    if Int64(size) == file.header.size {
                        track.fileURL = url
                        pending[id] = track
                        received.append(track)
                    } else {
                        try? FileManager.default.removeItem(at: url)
                    }
                } else if !file.data.isEmpty {
                    ArtworkStore.shared.store(file.data, forKey: track.artworkKey, overwrite: false)
                }
                current = nil
            case .message(.uploadsDone):
                if !received.isEmpty { state.tracks.append(contentsOf: received) }
                return
            default:
                break
            }
        }
    }

    private static func localTrack(from s: SyncTrack) -> LocalTrack {
        var t = LocalTrack(title: s.title, artist: s.artist, album: s.album, genre: s.genre, duration: s.duration, fileURL: nil,
                           coverImageName: "music.note", dateAdded: s.dateAdded, isAtmos: s.isAtmos,
                           fileSize: ByteCountFormatter.string(fromByteCount: s.fileSize, countStyle: .file), lyrics: s.lyrics)
        t.id = s.id
        t.isFavorite = s.isFavorite
        t.playCount = s.playCount
        t.lastPlayedDate = s.lastPlayedDate
        t.format = s.format
        t.discNumber = s.discNumber
        t.trackNumber = s.trackNumber
        t.copyright = s.copyright
        t.year = s.year
        t.bitDepth = s.bitDepth
        t.sampleRate = s.sampleRate
        t.albumArtist = s.albumArtist
        return t
    }

    private func makeManifest(state: AppStateManager) -> SyncManifest {
        let chosenPlaylists: [Playlist]
        var trackSet: [LocalTrack]
        switch scope {
        case .everything:
            chosenPlaylists = state.playlists
            trackSet = state.tracks
        case .playlists:
            chosenPlaylists = state.playlists.filter { selectedPlaylists.contains($0.id) }
            var seen = Set<UUID>()
            trackSet = chosenPlaylists.flatMap { state.resolvedTracks(of: $0) }.filter { seen.insert($0.id).inserted }
        }
        trackSet = trackSet.filter { $0.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
        let included = Set(trackSet.map(\.id))
        let tracks: [SyncTrack] = trackSet.map { t in
            let size = (try? t.fileURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init) ?? 0
            return SyncTrack(id: t.id, title: t.title, artist: t.artist, album: t.album, albumArtist: t.albumArtist, genre: t.genre,
                             duration: t.duration, year: t.year, trackNumber: t.trackNumber, discNumber: t.discNumber, isAtmos: t.isAtmos,
                             format: t.format, lyrics: t.lyrics, copyright: t.copyright, isFavorite: t.isFavorite, playCount: t.playCount,
                             lastPlayedDate: t.lastPlayedDate, dateAdded: t.dateAdded, artworkKey: t.artworkKey,
                             fileExtension: t.fileURL?.pathExtension ?? "m4a", fileSize: size, bitDepth: t.bitDepth, sampleRate: t.sampleRate)
        }
        let playlists: [SyncPlaylist] = chosenPlaylists.map { p in
            SyncPlaylist(id: p.id, name: p.name, description: p.description,
                         trackIds: state.resolvedTracks(of: p).map(\.id).filter { included.contains($0) },
                         isSmart: p.isSmart, isFavorites: p.isAppleMusicFavorites, dateModified: p.dateModified,
                         artworkKey: p.artworkFileName == nil ? nil : "playlist-" + p.id.uuidString)
        }
        // The Mac decides these for both devices.
        let settings = SyncSettings(
            themeName: state.currentThemeName,
            mergeCollaborations: state.mergeCollaborationArtists,
            hiddenTrackIds: trackSet.filter { state.isHiddenFromLibrary($0.id) }.map(\.id),
            favoriteArtists: Array(state.favoriteArtists).sorted(),
            animatedArtwork: state.animatedArtworkEnabled,
            lastFM: LastFMService.shared.syncCredentials()
        )
        let history = state.playHistoryLog.suffix(50_000).map {
            SyncPlayEvent(id: $0.id, trackId: $0.trackId, title: $0.title, artist: $0.artist, album: $0.album, genre: $0.genre, duration: $0.duration, timestamp: $0.timestamp)
        }
        return SyncManifest(tracks: tracks, playlists: playlists, sourceName: Host.current().localizedName ?? "Mac", settings: settings, playHistory: Array(history))
    }
}

extension AppStateManager {
    /// Applies plays, favorites and playlists changed on the iPhone.
    func mergeSyncChanges(_ inventory: SyncInventory) {
        // Plays made on the iPhone, with their real times (older iPhone versions only sent counts).
        var knownEvents = Set(playHistoryLog.map(\.id))
        var events: [PlayLogEntry] = []
        for e in inventory.playEvents ?? [] where knownEvents.insert(e.id).inserted {
            events.append(PlayLogEntry(id: e.id, trackId: e.trackId, title: e.title, artist: e.artist, album: e.album, genre: e.genre, duration: e.duration, timestamp: e.timestamp))
        }
        if !events.isEmpty { playHistoryLog = (playHistoryLog + events).sorted { $0.timestamp < $1.timestamp } }
        let synthesizeEntries = inventory.playEvents == nil

        // Playlists made on the iPhone and then deleted there.
        if let deleted = inventory.deletedPlaylists, !deleted.isEmpty {
            let ids = Set(deleted)
            playlists.removeAll { ids.contains($0.id) && $0.createdOnDevice != nil }
        }

        if !inventory.changes.isEmpty {
            var updated = tracks
            var entries: [PlayLogEntry] = []
            for i in updated.indices {
                guard let change = inventory.changes[updated[i].id.uuidString] else { continue }
                if change.playsSinceSync > 0 {
                    updated[i].playCount += change.playsSinceSync
                    let t = updated[i]
                    for _ in 0..<(synthesizeEntries ? min(change.playsSinceSync, 50) : 0) {
                        entries.append(PlayLogEntry(trackId: t.id, title: t.title, artist: t.artist, album: t.album, genre: t.genre, duration: t.duration, timestamp: change.lastPlayed ?? Date()))
                    }
                }
                if let last = change.lastPlayed, last > (updated[i].lastPlayedDate ?? .distantPast) { updated[i].lastPlayedDate = last }
                if let favorite = change.isFavorite { updated[i].isFavorite = favorite }
            }
            tracks = updated
            if !entries.isEmpty { playHistoryLog.append(contentsOf: entries.sorted { $0.timestamp < $1.timestamp }) }
        }
        for remote in inventory.playlists where !remote.isSmart && !remote.isFavorites {
            let songs = remote.trackIds.compactMap { track(withId: $0) }
            if playlists.contains(where: { $0.id == remote.id }) {
                updatePlaylist(remote.id) { p in
                    p.name = remote.name
                    p.description = remote.description
                    p.playlistTracks = songs.map { PlaylistTrack(track: $0) }
                }
            } else {
                var playlist = Playlist(id: remote.id, name: remote.name, description: remote.description, isImported: false, playlistTracks: songs.map { PlaylistTrack(track: $0) })
                playlist.dateCreated = Date()
                playlist.dateModified = remote.dateModified
                playlist.createdOnDevice = "iPhone"
                playlists.append(playlist)
            }
        }
    }
}

// MARK: - Sheet

struct DeviceSyncView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject private var sync = DeviceSyncController.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = state.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accentGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync iPhone").font(.system(size: 18, weight: .bold))
                    Text("Open Mesh Player on your iPhone. Connect with a cable or use the same Wi-Fi.")
                        .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                }
            }
            .padding(20)
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                statusView(theme)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Devices").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textSecondary)
                    if sync.devices.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for iPhones running Mesh Player…").font(.system(size: 12.5)).foregroundStyle(theme.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(theme, radius: 10)
                    } else {
                        ForEach(sync.devices) { device in
                            HStack(spacing: 12) {
                                Image(systemName: device.isUSB ? "cable.connector" : "wifi")
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name).font(.system(size: 13, weight: .semibold))
                                    Text(device.isUSB ? "Connected by USB" : "On this network").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                                }
                                Spacer()
                                Button("Sync") { sync.sync(device, state: state) }
                                    .buttonStyle(PillButtonStyle(kind: .primary, theme: theme, compact: true))
                                    .disabled(sync.isBusy)
                            }
                            .padding(12)
                            .card(theme, radius: 10)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What to sync").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textSecondary)
                    Picker("", selection: $sync.scope) {
                        ForEach(DeviceSyncController.Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    if sync.scope == .playlists {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(state.playlists) { playlist in
                                    Toggle(isOn: Binding(
                                        get: { sync.selectedPlaylists.contains(playlist.id) },
                                        set: { if $0 { sync.selectedPlaylists.insert(playlist.id) } else { sync.selectedPlaylists.remove(playlist.id) } }
                                    )) {
                                        HStack {
                                            Text(playlist.name)
                                            Spacer()
                                            Text(Fmt.songs(state.resolvedTracks(of: playlist).count)).foregroundStyle(theme.textTertiary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .padding(10)
                        }
                        .frame(height: 130)
                        .card(theme, radius: 10)
                    }
                    Text("Songs not selected are removed from the iPhone. Plays and favorites from the iPhone are added to your Mac library first.")
                        .font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                }
            }
            .padding(20)

            Divider()
            HStack {
                if sync.isBusy {
                    Button("Stop Sync") { sync.cancel() }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear { sync.startDiscovery() }
        .onDisappear { if !sync.isBusy { sync.stopDiscovery() } }
    }

    @ViewBuilder
    private func statusView(_ theme: ThemeColor) -> some View {
        switch sync.phase {
        case .idle:
            EmptyView()
        case .connecting:
            statusRow(theme, icon: nil, text: "Connecting to \(sync.deviceName)…")
        case .waitingForApproval:
            statusRow(theme, icon: "hand.tap", text: "Tap Allow on \(sync.deviceName) to trust this Mac.")
        case .preparing:
            statusRow(theme, icon: nil, text: "Comparing libraries…")
        case .sending, .finishing:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(sync.phase == .finishing ? "Finishing up…" : "Syncing \(sync.filesDone) of \(sync.filesTotal)")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: sync.bytesDone, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: sync.bytesTotal, countStyle: .file))")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(theme.textSecondary)
                }
                ProgressView(value: sync.bytesTotal > 0 ? Double(sync.bytesDone) / Double(sync.bytesTotal) : (sync.filesTotal > 0 ? Double(sync.filesDone) / Double(sync.filesTotal) : 0))
                    .tint(theme.accent)
                Text(sync.currentItem).font(.system(size: 11)).foregroundStyle(theme.textTertiary).lineLimit(1)
            }
            .padding(12)
            .card(theme, radius: 10)
        case .done(let summary):
            statusRow(theme, icon: "checkmark.circle.fill", text: summary, color: .green)
        case .failed(let message):
            statusRow(theme, icon: "exclamationmark.triangle.fill", text: message, color: .orange)
        }
    }

    private func statusRow(_ theme: ThemeColor, icon: String?, text: String, color: Color? = nil) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).foregroundStyle(color ?? theme.accent)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme, radius: 10)
    }
}
