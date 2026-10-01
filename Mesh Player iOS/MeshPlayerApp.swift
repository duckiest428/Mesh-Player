//
//  MeshPlayerApp.swift
//  Mesh Player iOS
//

import SwiftUI

@main
struct MeshPlayerApp: App {
    @StateObject private var library = MobileLibrary.shared
    @StateObject private var player = MobilePlayer.shared
    @StateObject private var sync = SyncServer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(sync)
                .onAppear {
                    sync.start()
                    library.importDocumentsFolder()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        sync.restart()
                        library.importDocumentsFolder()
                    case .background:
                        library.saveNow()
                        // A suspended app's listener stops accepting connections but can keep
                        // advertising, so the Mac would see a phone it can't reach. Stay
                        // listening only while a sync is running (stop() checks that).
                        sync.stop()
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    library.importFiles([url], move: false)
                }
        }
    }
}

enum AppTab: Hashable { case home, library, search }

struct RootView: View {
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @EnvironmentObject var sync: SyncServer
    @State private var tab: AppTab = .home
    @State private var showNowPlaying = false
    @State private var dismissedNetworkAlert = false
    @AppStorage("themeOverride") private var themeOverride = MeshTheme.followMac
    @State private var libraryPath = NavigationPath()

    var body: some View {
        let theme = MeshTheme.current(override: themeOverride, library: library)
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack(path: $libraryPath) { LibraryHomeView() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.current != nil) {
            MiniPlayer { showNowPlaying = true }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .alert("Sync with “\(sync.approval?.name ?? "Mac")”?", isPresented: Binding(get: { sync.approval != nil }, set: { if !$0 && sync.approval != nil { sync.respondToApproval(false) } })) {
            Button("Don't Allow", role: .cancel) { sync.respondToApproval(false) }
            Button("Allow") { sync.respondToApproval(true) }
        } message: {
            Text("This Mac wants to sync its Mesh Player library to this iPhone. Only allow Macs you own.")
        }
        .alert(library.importMessage ?? "", isPresented: Binding(get: { library.importMessage != nil }, set: { if !$0 { library.importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            SyncBanner()
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .environment(\.meshTheme, theme)
        .alert("Turn On Local Network", isPresented: Binding(get: { sync.localNetworkDenied && !dismissedNetworkAlert }, set: { if !$0 { dismissedNetworkAlert = true } })) {
            Button("Open Settings") { sync.openAppSettings() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Your Mac can't sync with Mesh Player until it's allowed on your local network. In Settings, turn on Local Network for Mesh Player.")
        }
    }
}

/// Floating status pill while a sync runs or just finished.
struct SyncBanner: View {
    @EnvironmentObject var sync: SyncServer
    @ObservedObject private var progress = SyncProgress.shared

    var body: some View {
        Group {
            switch sync.status {
            case .syncing(let text):
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text).font(.subheadline.weight(.semibold))
                        if progress.filesTotal > 0 {
                            Text("\(progress.filesDone) of \(progress.filesTotal) · \(ByteCountFormatter.string(fromByteCount: progress.bytesDone, countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
            case .finished(let summary):
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
            default:
                EmptyView()
            }
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sync.status)
    }
}

/// Shown where sync status appears when iOS is blocking the Mac's connections.
struct LocalNetworkNotice: View {
    @EnvironmentObject var sync: SyncServer

    var body: some View {
        if sync.localNetworkDenied {
            VStack(alignment: .leading, spacing: 8) {
                Label("Local Network is off", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Your Mac can see this iPhone but can't connect to it. Turn on Local Network for Mesh Player in Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Open Settings") { sync.openAppSettings() }
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}
