import SwiftUI

struct iOSMainView: View {
    @StateObject private var appState = iOSAppState()
    @EnvironmentObject var engine: iOSAudioEngine
    @EnvironmentObject var syncManager: MultipeerSyncManager
    @State private var selectedTab = 2 // Default to Library
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    iOSHomeView(appState: appState)
                        .tabItem {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                        .tag(0)
                        
                    iOSRadioView(appState: appState)
                        .tabItem {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("Radio")
                        }
                        .tag(1)
                        
                    LibraryView(appState: appState)
                        .tabItem {
                            Image(systemName: "square.stack.fill")
                            Text("Library")
                        }
                        .tag(2)
                        
                    iOSSearchView(appState: appState)
                        .tabItem {
                            Image(systemName: "magnifyingglass")
                            Text("Search")
                        }
                        .tag(3)
                }
                .accentColor(.pink) // Just a placeholder for mesh player theme
                
                // Mini Player overlay
                iOSMiniPlayerView(appState: appState)
                    .offset(y: -49 - geometry.safeAreaInsets.bottom)
                    
                if syncManager.isReceiving {
                    VStack {
                        Spacer()
                        HStack {
                            ProgressView()
                            Text("Syncing from macOS...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .environmentObject(appState)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LibraryUpdated"))) { _ in
            appState.scanDocumentsDirectory()
        }
        .onAppear {
            syncManager.startAdvertising()
            engine.onPlayCountUpdate = { songId in
                if let idx = appState.recentlyAddedSongs.firstIndex(where: { $0.id == songId }) {
                    appState.recentlyAddedSongs[idx].playCount += 1
                }
            }
        }
    }
}
