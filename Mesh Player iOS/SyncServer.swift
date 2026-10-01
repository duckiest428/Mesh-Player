//
//  SyncServer.swift
//  Mesh Player iOS
//
//  Waits for the Mac. The listener uses a fixed port and Bonjour, so the Mac can reach it over
//  Wi-Fi, peer-to-peer Wi-Fi, or a USB cable (usbmuxd tunnels to the same port). A Mac has to be
//  approved on the iPhone the first time it connects. See Shared/MeshSync.swift for the protocol.
//

import Combine
import Network
import SwiftUI
import UIKit

final class SyncServer: ObservableObject {
    static let shared = SyncServer()

    enum Status: Equatable {
        case stopped
        case ready
        case unavailable(String)
        case syncing(String)
        case finished(String)
        case failed(String)
    }

    struct ApprovalRequest: Identifiable {
        let id: String
        let name: String
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var filesDone = 0
    @Published private(set) var filesTotal = 0
    @Published private(set) var bytesDone: Int64 = 0
    @Published private(set) var bytesTotal: Int64 = 0
    @Published var approval: ApprovalRequest?

    private var listener: NWListener?
    private var active: SyncChannel?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var isSyncing: Bool { if case .syncing = status { return true }; return false }

    func start() {
        startProbe()
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: MeshSync.port)!)
            listener.service = NWListener.Service(name: UIDevice.current.name, type: MeshSync.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if !self.isSyncing { self.status = .ready }
                    case .waiting(let error):
                        if !self.isSyncing { self.status = .unavailable(error.localizedDescription) }
                    case .failed(let error):
                        self.status = .unavailable(error.localizedDescription)
                        self.listener?.cancel()
                        self.listener = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.start() }
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func stop() {
        guard !isSyncing else { return }
        listener?.cancel()
        listener = nil
        probe?.cancel()
        probe = nil
        status = .stopped
    }

    /// Called when the app comes to the front. A listener that sat in a suspended app can be left
    /// with a dead socket that still advertises, so start a fresh one.
    func restart() {
        guard !isSyncing, active == nil else { return }
        listener?.cancel()
        listener = nil
        probe?.cancel()
        probe = nil
        start()
    }

    /// Listening for the Mac doesn't make iOS ask for Local Network access, and without it iOS
    /// silently drops the Mac's connection. Browsing for our own service asks the first time and
    /// reports PolicyDenied when access is off; seeing any result means access is on.
    private func startProbe() {
        guard probe == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: MeshSync.serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            let denied: Bool? = {
                switch state {
                case .waiting(let error), .failed(let error):
                    if case .dns(let code) = error, code == Self.policyDenied { return true }
                    return nil
                default:
                    return nil
                }
            }()
            guard let denied else { return }
            DispatchQueue.main.async { self?.localNetworkDenied = denied }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard !results.isEmpty else { return }
            DispatchQueue.main.async { self?.localNetworkDenied = false }
        }
        browser.start(queue: .main)
        probe = browser
    }

    /// kDNSServiceErr_PolicyDenied
    private static let policyDenied: DNSServiceErrorType = -65570

    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    func respondToApproval(_ allow: Bool) {
        approval = nil
        approvalContinuation?.resume(returning: allow)
        approvalContinuation = nil
    }

    private func accept(_ connection: NWConnection) {
        guard active == nil else {
            connection.cancel()
            return
        }
        let transport = NWSyncTransport(connection: connection)
        let channel = SyncChannel(transport)
        active = channel
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Mesh Sync") { [weak self] in
            self?.active?.close()
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await transport.start()
                let summary = try await self.run(channel)
                self.status = .finished(summary)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.status = .failed(error.localizedDescription)
            }
            channel.close()
            self.active = nil
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
            try? await Task.sleep(for: .seconds(6))
            if !self.isSyncing, self.listener != nil { self.status = .ready }
        }
    }

    private func run(_ channel: SyncChannel) async throws -> String {
        let library = MobileLibrary.shared
        guard case .hello(let mac) = try await channel.nextMessage() else { throw SyncError.protocolError("Unexpected first message") }
        status = .syncing("Connected to \(mac.name)")

        if !library.isTrusted(mac.deviceId) {
            try await channel.send(.awaitingApproval)
            let allowed = await withCheckedContinuation { continuation in
                approvalContinuation = continuation
                approval = ApprovalRequest(id: mac.deviceId, name: mac.name)
            }
            guard allowed else {
                try await channel.send(.denied("\(UIDevice.current.name) declined to sync with this Mac."))
                throw SyncError.protocolError("Declined")
            }
            library.trust(mac.deviceId, name: mac.name)
        }

        try await channel.send(.hello(SyncHello(deviceId: SyncIdentity.deviceId, name: UIDevice.current.name, platform: "ios", version: MeshSync.protocolVersion)))
        try await channel.send(.inventory(library.makeInventory()))

        guard case .manifest(let manifest) = try await channel.nextMessage() else { throw SyncError.protocolError("Expected the library list") }
        status = .syncing("Syncing with \(mac.name)")
        library.applyManifest(manifest)

        var current: (header: SyncFileHeader, url: URL, handle: FileHandle)?
        while true {
            switch try await channel.next() {
            case .message(.progress(let info)):
                filesTotal = info.filesTotal
                bytesTotal = info.bytesTotal
                filesDone = info.filesDone
                bytesDone = info.bytesDone
            case .message(.fileBegin(let header)):
                let url = MobileLibrary.incomingFolder.appendingPathComponent(UUID().uuidString + "." + header.fileExtension)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                current = (header, url, try FileHandle(forWritingTo: url))
            case .chunk(let data):
                try current?.handle.write(contentsOf: data)
                if current?.header.kind == .audio { bytesDone += Int64(data.count) }
            case .message(.fileEnd):
                guard let file = current else { break }
                try? file.handle.close()
                switch file.header.kind {
                case .audio:
                    if let id = UUID(uuidString: file.header.id) { library.registerFile(for: id, at: file.url) }
                case .artwork:
                    library.registerArtwork(key: file.header.id, at: file.url)
                }
                current = nil
                filesDone += 1
            case .message(.finished):
                let summary = library.finishSync(manifest: manifest)
                try await channel.send(.complete(summary))
                return summary
            default:
                break
            }
        }
    }
}
