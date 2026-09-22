import Foundation
import MultipeerConnectivity
import Combine

class MultipeerSyncManager: NSObject, ObservableObject, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    static let serviceType = "mesh-player"
    
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private let advertiser: MCNearbyServiceAdvertiser
    private(set) var session: MCSession
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isReceiving: Bool = false
    @Published var receiveProgress: Double = 0.0
    
    // We will keep track of total incoming resources to calculate progress approximately
    private var totalIncomingResources: Int = 0
    private var completedResources: Int = 0
    
    override init() {
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        super.init()
        self.session.delegate = self
        self.advertiser.delegate = self
    }
    
    func startAdvertising() {
        advertiser.startAdvertisingPeer()
    }
    
    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
    }
    
    // MARK: - MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Automatically accept invitations for now
        invitationHandler(true, self.session)
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
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async {
            self.isReceiving = true
            self.totalIncomingResources += 1 // Increment for every new resource
        }
        
        progress.publisher(for: \.fractionCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fraction in
                guard let self = self else { return }
                // Approximation of total progress
                let currentTotal = max(1, self.totalIncomingResources)
                let base = Double(self.completedResources) / Double(currentTotal)
                let currentResourceProgress = fraction / Double(currentTotal)
                self.receiveProgress = base + currentResourceProgress
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        DispatchQueue.main.async {
            self.completedResources += 1
            if self.completedResources == self.totalIncomingResources {
                // Done receiving the batch
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isReceiving = false
                    self.totalIncomingResources = 0
                    self.completedResources = 0
                    self.receiveProgress = 0.0
                }
            }
            
            // Move file to documents directory
            if let localURL = localURL, error == nil {
                let fileManager = FileManager.default
                let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dest = docs.appendingPathComponent(resourceName)
                do {
                    if fileManager.fileExists(atPath: dest.path) {
                        try fileManager.removeItem(at: dest)
                    }
                    try fileManager.moveItem(at: localURL, to: dest)
                    // Broadcast notification to update library
                    NotificationCenter.default.post(name: NSNotification.Name("LibraryUpdated"), object: nil)
                } catch {
                    print("Error moving file: \(error)")
                }
            }
        }
    }
}
