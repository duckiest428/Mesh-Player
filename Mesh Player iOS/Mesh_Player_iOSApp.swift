import SwiftUI

@main
struct MeshPlayer_iOSApp: App {
    @StateObject private var engine = iOSAudioEngine()
    @StateObject private var syncManager = MultipeerSyncManager()
    
    var body: some Scene {
        WindowGroup {
            iOSMainView()
                .environmentObject(engine)
                .environmentObject(syncManager)
        }
    }
}
