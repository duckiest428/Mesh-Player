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
                        sync.start()
                        library.importDocumentsFolder()
                    case .background:
                        library.saveNow()
                        if !player.isPlaying { sync.stop() }
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

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack { LibraryHomeView() }
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
    }
}

/// Floating status pill while a sync runs or just finished.
struct SyncBanner: View {
    @EnvironmentObject var sync: SyncServer

    var body: some View {
        Group {
            switch sync.status {
            case .syncing(let text):
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text).font(.subheadline.weight(.semibold))
                        if sync.filesTotal > 0 {
                            Text("\(sync.filesDone) of \(sync.filesTotal) · \(ByteCountFormatter.string(fromByteCount: sync.bytesDone, countStyle: .file))")
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
