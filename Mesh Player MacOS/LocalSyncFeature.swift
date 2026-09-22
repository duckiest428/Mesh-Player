import Combine
import Foundation
import MultipeerConnectivity
import SwiftUI

// MARK: - LocalSyncView.swift
struct LocalSyncView: View {
    @EnvironmentObject var state: AppStateManager
    @StateObject private var syncManager = MultipeerSyncManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 48))
                .foregroundColor(state.theme.accent)
                
            Text("Local Device Sync")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Find and sync music with iOS devices over the local network via MultipeerConnectivity. Make sure the Mesh Player app is open on your iOS device.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            if syncManager.isSyncing {
                VStack(spacing: 12) {
                    ProgressView(value: syncManager.syncProgress, total: 1.0)
                        .frame(width: 200)
                    Text("Syncing library metadata & files...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(syncManager.discoveredPeers, id: \.self) { peer in
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundColor(state.theme.accent)
                            Text(peer.displayName)
                            Spacer()
                            if syncManager.connectedPeers.contains(peer) {
                                Button("Sync") {
                                    startSync()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(state.theme.accent)
                            } else {
                                Button("Connect") {
                                    syncManager.invitePeer(peer)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(height: 120)
                .border(Color.secondary.opacity(0.2), width: 1)
                .overlay {
                    if syncManager.discoveredPeers.isEmpty {
                        Text("Searching for devices...")
                            .foregroundColor(.secondary)
                    }
                }
                    
                Button("Done") {
                    state.showSyncWindow = false
                }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
            }
        }
        .padding(30)
        .frame(width: 450, height: 420)
        .onAppear {
            syncManager.startBrowsing()
            syncManager.onSyncCompleted = {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    state.showSyncWindow = false
                }
            }
        }
        .onDisappear {
            syncManager.stopBrowsing()
        }
    }
    
    private func startSync() {
        let urls = state.tracks.compactMap { $0.fileURL }
        syncManager.sendTracks(urls)
    }
}

// MARK: - MultipeerSyncManager.swift
class MultipeerSyncManager: NSObject, ObservableObject, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    static let serviceType = "mesh-player"
    
    private let myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "MacBook")
    private let browser: MCNearbyServiceBrowser
    private(set) var session: MCSession
    
    @Published var discoveredPeers: [MCPeerID] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
    
    var onSyncCompleted: (() -> Void)?
    
    override init() {
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        self.browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: Self.serviceType)
        super.init()
        self.session.delegate = self
        self.browser.delegate = self
    }
    
    func startBrowsing() {
        discoveredPeers.removeAll()
        browser.startBrowsingForPeers()
    }
    
    func stopBrowsing() {
        browser.stopBrowsingForPeers()
    }
    
    func invitePeer(_ peer: MCPeerID) {
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }
    
    func sendTracks(_ tracks: [URL]) {
        guard let peer = connectedPeers.first else { return }
        
        DispatchQueue.main.async {
            self.isSyncing = true
            self.syncProgress = 0.0
        }
        
        let total = tracks.count
        var completed = 0
        
        for trackURL in tracks {
            session.sendResource(at: trackURL, withName: trackURL.lastPathComponent, toPeer: peer) { [weak self] error in
                DispatchQueue.main.async {
                    completed += 1
                    self?.syncProgress = Double(completed) / Double(total)
                    if completed == total {
                        self?.isSyncing = false
                        self?.onSyncCompleted?()
                    }
                }
            }
        }
    }
    
    // MARK: - MCNearbyServiceBrowserDelegate
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
    
    // MARK: - MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
            case .connecting:
                break
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

