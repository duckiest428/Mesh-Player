import AppKit
import CoreImage
import SwiftUI

// MARK: - Now Playing bar
//
//  PlayerControlsView.swift
//  macOS Music Player
//
//  The bar deliberately does NOT observe the time tracker; only the small scrubber
//  subview does, so the 10 Hz time updates redraw a few pixels instead of the whole bar.
//

struct PlayerControlsView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    let timeTracker: AudioTimeTracker
    @Binding var showFullscreen: Bool
    @Binding var showSettings: Bool
    @Environment(\.openWindow) private var openWindow

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var hoveringArt = false

    var body: some View {
        let theme = state.theme
        HStack(spacing: 20) {
            nowPlaying(theme)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                transport(theme)
                PlaybackScrubber(engine: engine, timeTracker: timeTracker, theme: theme)
            }
            .frame(width: 440)

            utilities(theme)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 82)
        .background {
            ZStack {
                Rectangle().fill(.bar)
                theme.barBackground
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.isEmpty, let track = engine.currentTrack {
                    state.createNewPlaylist(name: newPlaylistName, initialTrack: track)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new playlist.")
        }
    }

    // MARK: Left — artwork & metadata

    private func nowPlaying(_ theme: ThemeColor) -> some View {
        HStack(spacing: 12) {
            Button {
                if engine.currentTrack != nil {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    showFullscreen = true
                }
            } label: {
                ZStack {
                    if let track = engine.currentTrack {
                        ArtworkView(track: track, pixelSize: 120, cornerRadius: 7)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.cardBackground)
                            .overlay(Image(systemName: "music.note").foregroundStyle(theme.textTertiary))
                    }
                    if hoveringArt && engine.currentTrack != nil {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.black.opacity(0.45))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 54, height: 54)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .onHover { hoveringArt = $0 }
            .help("Open Now Playing")

            VStack(alignment: .leading, spacing: 3) {
                if let track = engine.currentTrack {
                    LinkText(text: track.title, font: .system(size: 13, weight: .semibold), color: theme.textPrimary, hoverColor: theme.textPrimary) {
                        state.showAlbum(of: track)
                    }
                    LinkText(text: track.artist, font: .system(size: 12), color: theme.textSecondary, hoverColor: theme.accent) {
                        state.showArtist(track.artist)
                    }
                } else {
                    Text("Not Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text("Pick something to play")
                        .lineLimit(1)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(minWidth: 60, alignment: .leading)

            if let track = engine.currentTrack {
                let isFav = state.isFavorite(track.id)
                Button {
                    state.toggleFavorite(track: track)
                } label: {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle(theme: theme, isActive: isFav, size: 28))
                .help(isFav ? "Remove from Favorites" : "Add to Favorites")

                Menu {
                    Button("Go to Album") { state.showAlbum(of: track) }
                    Button("Go to Artist") { state.showArtist(track.artist) }
                    Divider()
                    Menu("Add to Playlist") {
                        Button("New Playlist…") {
                            newPlaylistName = ""
                            showNewPlaylistAlert = true
                        }
                        Divider()
                        ForEach(state.playlists) { playlist in
                            Button(playlist.name) { state.addTrackToPlaylist(track: track, playlistId: playlist.id) }
                        }
                    }
                    Divider()
                    Button("Show in Finder") {
                        if let url = track.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button("Open Mini Player") { openWindow(id: "miniPlayer") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    // MARK: Center — transport

    private func transport(_ theme: ThemeColor) -> some View {
        HStack(spacing: 18) {
            Button {
                state.toggleShuffle(currentTrack: engine.currentTrack)
            } label: {
                Image(systemName: "shuffle").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: theme, isActive: state.isQueueShuffled, size: 28))
            .help("Shuffle")

            Button {
                engine.triggerHaptic(pattern: .alignment)
                state.playPrevious(engine: engine)
            } label: {
                Image(systemName: "backward.fill").font(.system(size: 17))
            }
            .buttonStyle(IconButtonStyle(theme: theme, size: 32))
            .disabled(engine.currentTrack == nil)

            Button {
                engine.triggerHaptic(pattern: .generic)
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.background)
                    .offset(x: engine.isPlaying ? 0 : 1.5)
                    .frame(width: 36, height: 36)
                    .background(theme.textPrimary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(engine.currentTrack == nil)
            .help(engine.isPlaying ? "Pause" : "Play")

            Button {
                engine.triggerHaptic(pattern: .alignment)
                state.playNext(engine: engine)
            } label: {
                Image(systemName: "forward.fill").font(.system(size: 17))
            }
            .buttonStyle(IconButtonStyle(theme: theme, size: 32))
            .disabled(engine.currentTrack == nil)

            Button {
                state.repeatMode = (state.repeatMode + 1) % 3
            } label: {
                Image(systemName: state.repeatMode == 2 ? "repeat.1" : "repeat").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: theme, isActive: state.repeatMode > 0, size: 28))
            .help(state.repeatMode == 2 ? "Repeat One" : (state.repeatMode == 1 ? "Repeat All" : "Repeat Off"))
        }
    }

    // MARK: Right — panels & volume

    private func utilities(_ theme: ThemeColor) -> some View {
        HStack(spacing: 4) {
            let hasLyrics = !(engine.currentTrack?.lyrics.isEmpty ?? true)
            panelButton(.lyrics, icon: "quote.bubble", help: hasLyrics ? "Lyrics" : "No Lyrics Available", theme: theme)
                .disabled(!hasLyrics && state.activeRightSidebar != .lyrics)
            panelButton(.queue, icon: "list.bullet", help: "Playing Next", theme: theme)
            panelButton(.output, icon: "airplayaudio", help: "Audio Output", theme: theme)

            VolumeControl(engine: engine, theme: theme)
                .padding(.leading, 6)

            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                showFullscreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: theme, size: 28))
            .disabled(engine.currentTrack == nil)
            .help("Full Screen Player")
        }
    }

    private func panelButton(_ panel: AppStateManager.RightSidebarPanel, icon: String, help: String, theme: ThemeColor) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.activeRightSidebar = state.activeRightSidebar == panel ? .none : panel
            }
        } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(theme: theme, isActive: state.activeRightSidebar == panel, size: 28))
        .help(help)
    }
}

/// Plain press feedback for custom-drawn buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Single-line text that underlines on hover and acts as a link.
struct LinkText: View {
    let text: String
    let font: Font
    let color: Color
    let hoverColor: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font)
                .foregroundStyle(hovering ? hoverColor : color)
                .underline(hovering)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct VolumeControl: View {
    @ObservedObject var engine: AudioEngineManager
    let theme: ThemeColor
    @State private var lastNonZero: Float = 0.8

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if engine.volume > 0 {
                    lastNonZero = engine.volume
                    engine.volume = 0
                } else {
                    engine.volume = lastNonZero
                }
            } label: {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 16)
            }
            .buttonStyle(IconButtonStyle(theme: theme, size: 26))
            .help(engine.volume == 0 ? "Unmute" : "Mute")

            ThinSlider(value: Binding(get: { Double(engine.volume) }, set: { engine.volume = Float($0) }), theme: theme)
                .frame(width: 72, height: 16)
        }
    }

    private var icon: String {
        switch engine.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// Minimal capsule slider that thickens on hover (used for volume).
struct ThinSlider: View {
    @Binding var value: Double
    let theme: ThemeColor
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(theme.textPrimary.opacity(0.18))
                Capsule().fill(hovering ? theme.accent : theme.textPrimary.opacity(0.75))
                    .frame(width: max(0, geo.size.width * fraction))
            }
            .frame(height: hovering ? 5 : 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = Double(min(max(g.location.x / max(geo.size.width, 1), 0), 1))
            })
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Timeline with elapsed / remaining labels. Observes the time tracker on its own.
struct PlaybackScrubber: View {
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker
    let theme: ThemeColor
    var style: Style = .bar

    enum Style { case bar, fullscreen }

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        let duration = max(0.1, engine.duration)
        let fraction = dragFraction ?? min(max(timeTracker.currentTime / duration, 0), 1)
        let shownTime = dragFraction.map { $0 * duration } ?? timeTracker.currentTime
        let labelColor = style == .fullscreen ? Color.white.opacity(0.6) : theme.textTertiary
        let track = style == .fullscreen ? Color.white.opacity(0.22) : theme.textPrimary.opacity(0.16)
        let fill = style == .fullscreen ? Color.white : (hovering || dragFraction != nil ? theme.accent : theme.textPrimary.opacity(0.7))

        HStack(spacing: 10) {
            Text(Fmt.time(shownTime))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(labelColor)
                .frame(width: 38, alignment: .trailing)

            GeometryReader { geo in
                let active = hovering || dragFraction != nil
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(fill).frame(width: max(0, geo.size.width * fraction))
                }
                .frame(height: active ? 6 : 4)
                .overlay(alignment: .leading) {
                    if active {
                        Circle()
                            .fill(style == .fullscreen ? Color.white : theme.textPrimary)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: geo.size.width * fraction - 6)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in dragFraction = min(max(g.location.x / max(geo.size.width, 1), 0), 1) }
                        .onEnded { g in
                            let f = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                            engine.seek(to: f * engine.duration)
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .disabled(engine.currentTrack == nil)

            Text("-" + Fmt.time(max(0, duration - shownTime)))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(labelColor)
                .frame(width: 42, alignment: .leading)
        }
    }
}

// MARK: - FullLyricsView.swift
//
//  FullLyricsView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255.0))
        let g = Int(round(nsColor.greenComponent * 255.0))
        let b = Int(round(nsColor.blueComponent * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Slowly drifting blurred color blobs behind the full screen player.
struct FluidBackgroundView: View {
    let isIdle: Bool
    var colors: [Color]
    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if colors.count >= 4 {
                    colors[3]
                    Ellipse()
                        .fill(colors[0])
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(phase ? 1.2 : 0.8)
                        .offset(x: phase ? size.width * 0.1 : -size.width * 0.1, y: phase ? size.height * 0.1 : -size.height * 0.1)
                        .rotationEffect(.degrees(phase ? 90 : 0))
                    Ellipse()
                        .fill(colors[1])
                        .frame(width: size.width * 1.1, height: size.height * 0.9)
                        .scaleEffect(phase ? 1.3 : 0.9)
                        .offset(x: phase ? -size.width * 0.2 : size.width * 0.2, y: phase ? size.height * 0.2 : -size.height * 0.1)
                        .rotationEffect(.degrees(phase ? -60 : 60))
                    Ellipse()
                        .fill(colors[2])
                        .frame(width: size.width * 0.9, height: size.height * 1.1)
                        .scaleEffect(phase ? 0.9 : 1.4)
                        .offset(x: phase ? -size.width * 0.15 : size.width * 0.15, y: phase ? -size.height * 0.2 : size.height * 0.2)
                        .rotationEffect(.degrees(phase ? 120 : -30))
                }
            }
            .scaleEffect(1.15)
            .blur(radius: 90, opaque: true)
            .clipped()
            .animation(isIdle ? .easeOut(duration: 2) : .easeInOut(duration: 18).repeatForever(autoreverses: true), value: phase)
            .onAppear { phase = !isIdle }
            .onChange(of: isIdle) { _, idle in phase = !idle }
        }
        .ignoresSafeArea(.all)
    }
}

struct FullLyricsView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    let timeTracker: AudioTimeTracker
    @Binding var isPresented: Bool

    enum FullLyricsRightPanel {
        case lyrics, queue, output, none
    }
    @State private var rightPanel: FullLyricsRightPanel = .lyrics

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var cachedColors: [Color] = []
    @State private var hoveringArt = false
    @State private var appeared = false
    @State private var backCount = 0
    @State private var forwardCount = 0

    @AppStorage("enableDynamicBackground") private var enableDynamicBackground = true

    private var activeBackgroundColors: [Color] {
        if !enableDynamicBackground || cachedColors.isEmpty {
            return [
                Color(red: 0.1, green: 0.1, blue: 0.1),
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.05, green: 0.05, blue: 0.05),
                Color(red: 0.02, green: 0.02, blue: 0.02)
            ]
        }
        return cachedColors
    }

    private func updateCachedColors() {
        guard let track = engine.currentTrack else {
            withAnimation(.easeInOut(duration: 1.2)) {
                cachedColors = [state.theme.accent.opacity(0.8), state.theme.accent.opacity(0.6), state.theme.accent.opacity(0.4), state.theme.accent.opacity(0.2)]
            }
            return
        }
        if let colorsHex = track.artworkColors, colorsHex.count >= 4 {
            let extracted = colorsHex.compactMap { Color(hex: $0) }
            if extracted.count >= 4 {
                withAnimation(.easeInOut(duration: 1.2)) { cachedColors = extracted }
                return
            }
        }

        Task {
            let image = await ArtworkStore.shared.image(for: track, pixelSize: 128)
            let colors = await Task.detached(priority: .userInitiated) { Self.extractDominantColors(from: image) }.value
            let hexes = colors.map { $0.toHex() ?? "#1A1A1A" }
            if let idx = state.tracks.firstIndex(where: { $0.id == track.id }) {
                state.tracks[idx].artworkColors = hexes
            }
            if engine.currentTrack?.id == track.id {
                engine.currentTrack?.artworkColors = hexes
                withAnimation(.easeInOut(duration: 1.2)) { cachedColors = colors }
            }
        }
    }

    nonisolated private static func extractDominantColors(from image: NSImage?) -> [Color] {
        let defaultPalette = [
            Color(red: 0.15, green: 0.15, blue: 0.15),
            Color(red: 0.1, green: 0.1, blue: 0.1),
            Color(red: 0.05, green: 0.05, blue: 0.05),
            Color(red: 0.02, green: 0.02, blue: 0.02)
        ]
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return defaultPalette
        }

        let ciImage = CIImage(cgImage: cgImage)
        let w = ciImage.extent.size.width
        let h = ciImage.extent.size.height
        let quadrants = [
            CIVector(x: 0, y: h / 2, z: w / 2, w: h / 2),
            CIVector(x: w / 2, y: h / 2, z: w / 2, w: h / 2),
            CIVector(x: 0, y: 0, z: w / 2, w: h / 2),
            CIVector(x: w / 2, y: 0, z: w / 2, w: h / 2)
        ]

        var colors: [Color] = []
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        for extent in quadrants {
            if let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extent]),
               let avgOutput = avgFilter.outputImage {
                var bitmap = [UInt8](repeating: 0, count: 4)
                context.render(avgOutput, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                colors.append(Color(red: Double(bitmap[0]) / 255.0, green: Double(bitmap[1]) / 255.0, blue: Double(bitmap[2]) / 255.0))
            }
        }
        if colors.isEmpty { return defaultPalette }
        while colors.count < 4 { colors.append(colors.last!) }
        return colors
    }

    var body: some View {
        let theme = state.theme
        let effectiveRightPanel = (rightPanel == .lyrics && engine.parsedLyrics.isEmpty) ? .none : rightPanel

        ZStack {
            FluidBackgroundView(isIdle: state.isIdle, colors: activeBackgroundColors)
                .animation(.easeInOut(duration: 1.2), value: activeBackgroundColors)
                .overlay(Color.black.opacity(0.28))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(effectiveRightPanel)

                GeometryReader { geo in
                HStack(spacing: geo.size.width < 1000 ? 36 : 64) {
                    if effectiveRightPanel == .none { Spacer(minLength: 0) }

                    playerColumn(theme, art: Self.artworkSize(for: geo.size, hasPanel: effectiveRightPanel != .none))

                    if effectiveRightPanel == .none {
                        Spacer(minLength: 0)
                    } else {
                        Group {
                            switch effectiveRightPanel {
                            case .lyrics:
                                FullLyricsList(engine: engine, timeTracker: timeTracker)
                                    .frame(maxWidth: 560)
                            case .queue:
                                QueueSidebarView(state: state, engine: engine, isFullscreen: true)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .padding(.vertical, 24)
                            case .output:
                                OutputDeviceSidebarView(state: state, engine: engine, isFullscreen: true)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .padding(.vertical, 24)
                            case .none:
                                EmptyView()
                            }
                        }
                        .transition(.opacity.combined(with: .offset(x: 80)).combined(with: .scale(scale: 0.97, anchor: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 28)
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: effectiveRightPanel)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            updateCachedColors()
            // The artwork grows in first and the controls rise just after, like Apple Music.
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.08)) { appeared = true }
        }
        .onChange(of: engine.currentTrack?.id) { _, _ in updateCachedColors() }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                if !newPlaylistName.isEmpty, let track = engine.currentTrack {
                    state.createNewPlaylist(name: newPlaylistName, initialTrack: track)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new playlist.")
        }
    }

    private func topBar(_ effectiveRightPanel: FullLyricsRightPanel) -> some View {
        let glass = ThemeCatalog.theme(named: "True Black")
        let hasLyrics = !(engine.currentTrack?.lyrics.isEmpty ?? true)
        return HStack(spacing: 6) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(IconButtonStyle(theme: glass, size: 34))
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")

            Spacer()

            Button {
                rightPanel = rightPanel == .lyrics ? .none : .lyrics
            } label: {
                Image(systemName: "quote.bubble").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: glass, isActive: effectiveRightPanel == .lyrics, size: 34, activeColor: .white))
            .disabled(!hasLyrics)
            .help(hasLyrics ? "Lyrics" : "No Lyrics Available")

            Button {
                rightPanel = rightPanel == .queue ? .none : .queue
            } label: {
                Image(systemName: "list.bullet").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: glass, isActive: effectiveRightPanel == .queue, size: 34, activeColor: .white))
            .help("Playing Next")

            Button {
                rightPanel = rightPanel == .output ? .none : .output
            } label: {
                Image(systemName: "airplayaudio").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: glass, isActive: effectiveRightPanel == .output, size: 34, activeColor: .white))
            .help("Audio Output")

            Button {
                enableDynamicBackground.toggle()
                updateCachedColors()
            } label: {
                Image(systemName: "drop.halffull").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(theme: glass, isActive: enableDynamicBackground, size: 34, activeColor: .white))
            .help("Dynamic Background")
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 8)
    }

    /// Artwork size that fits the window: the controls below it need about 320 pt, and with a
    /// side panel open the player gets roughly half the width.
    static func artworkSize(for size: CGSize, hasPanel: Bool) -> CGFloat {
        let columnWidth = hasPanel ? (size.width - 64) * 0.48 : size.width
        return max(180, min(columnWidth, size.height - 320, 640))
    }

    private func playerColumn(_ theme: ThemeColor, art: CGFloat) -> some View {
        let glass = ThemeCatalog.theme(named: "True Black")
        // Controls scale with the artwork, within limits that keep them legible and clickable.
        let scale = min(max(art / 400, 0.8), 1.3)
        let rowWidth = max(art, 300) + 40
        return VStack(spacing: 26 * min(scale, 1)) {
            Button {
                if let track = engine.currentTrack {
                    state.showAlbum(of: track)
                    isPresented = false
                }
            } label: {
                ZStack {
                    if let track = engine.currentTrack {
                        // A new song's cover fades and settles in, like Apple Music.
                        ZStack {
                            ArtworkView(track: track, pixelSize: 900, cornerRadius: 20)
                            if state.animatedArtworkEnabled {
                                AnimatedArtworkView(track: track, cornerRadius: 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .id(track.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08))
                    }
                }
                .frame(width: art, height: art)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: engine.currentTrack?.id)
            }
            .buttonStyle(.plain)
            .scaleEffect(engine.isPlaying ? (hoveringArt ? 1.015 : 1.0) : 0.86)
            .shadow(color: .black.opacity(engine.isPlaying ? 0.5 : 0.25), radius: engine.isPlaying ? 40 : 16, y: engine.isPlaying ? 22 : 6)
            .animation(.spring(response: 0.55, dampingFraction: 0.68), value: engine.isPlaying)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveringArt)
            .onHover { hoveringArt = $0 }
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 22 * min(scale, 1)) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        MarqueeText(text: engine.currentTrack?.title ?? "Not Playing", font: .system(size: 22 * min(scale, 1.15), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        if let track = engine.currentTrack {
                            LinkText(text: "\(track.artist) — \(track.album)", font: .system(size: 17 * min(scale, 1.1)), color: .white.opacity(0.55), hoverColor: .white.opacity(0.85)) {
                                state.showArtist(track.artist)
                                isPresented = false
                            }
                        }
                    }
                    .id(engine.currentTrack?.id)
                    .transition(.opacity)
                    Spacer(minLength: 8)
                    if let track = engine.currentTrack {
                        let isFav = state.isFavorite(track.id)
                        Button {
                            state.toggleFavorite(track: track)
                        } label: {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(GlassCircleButtonStyle(size: 38 * min(scale, 1.1)))
                        .help(isFav ? "Undo Favorite" : "Favorite")

                        Menu {
                            Menu("Add to Playlist") {
                                Button("New Playlist…") {
                                    newPlaylistName = ""
                                    showNewPlaylistAlert = true
                                }
                                Divider()
                                ForEach(state.playlists) { playlist in
                                    Button(playlist.name) { state.addTrackToPlaylist(track: track, playlistId: playlist.id) }
                                }
                            }
                            Button("Go to Album") {
                                state.showAlbum(of: track)
                                isPresented = false
                            }
                            Button("Go to Artist") {
                                state.showArtist(track.artist)
                                isPresented = false
                            }
                            Divider()
                            Button("Show in Finder") {
                                if let url = track.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                        } label: {
                            GlassCircle(size: 38 * min(scale, 1.1)) {
                                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold))
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: engine.currentTrack?.id)

                FullscreenProgressBar(engine: engine, timeTracker: timeTracker)

                HStack(spacing: 0) {
                    Button {
                        state.toggleShuffle(currentTrack: engine.currentTrack)
                    } label: {
                        Image(systemName: "shuffle").font(.system(size: 18 * scale, weight: .semibold))
                    }
                    .buttonStyle(ToggleCircleButtonStyle(isOn: state.isQueueShuffled, size: 46 * scale))
                    .help("Shuffle")
                    Spacer()
                    Button {
                        backCount += 1
                        state.playPrevious(engine: engine)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 34 * scale))
                            .symbolEffect(.bounce.down, value: backCount)
                    }
                    .buttonStyle(TransportButtonStyle(size: 62 * scale))
                    Spacer()
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 46 * scale))
                            .contentTransition(.symbolEffect(.replace.downUp))
                    }
                    .buttonStyle(TransportButtonStyle(size: 72 * scale))
                    Spacer()
                    Button {
                        forwardCount += 1
                        state.playNext(engine: engine)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 34 * scale))
                            .symbolEffect(.bounce.down, value: forwardCount)
                    }
                    .buttonStyle(TransportButtonStyle(size: 62 * scale))
                    Spacer()
                    Button {
                        state.repeatMode = (state.repeatMode + 1) % 3
                    } label: {
                        Image(systemName: state.repeatMode == 2 ? "repeat.1" : "repeat")
                            .font(.system(size: 18 * scale, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(ToggleCircleButtonStyle(isOn: state.repeatMode > 0, size: 46 * scale))
                    .help("Repeat")
                }
                .padding(.horizontal, 2)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    ThinSlider(value: Binding(get: { Double(engine.volume) }, set: { engine.volume = Float($0) }), theme: glass)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(height: 16)
                .padding(.horizontal, 2)
            }
            .frame(width: rowWidth)
            .offset(y: appeared ? 0 : 30)
            .opacity(appeared ? 1 : 0)
        }
    }
}

// MARK: - Full screen player pieces (styled after Apple Music on the Mac)

/// One line of text that scrolls sideways when it doesn't fit, pausing at the start of each pass.
struct MarqueeText: View {
    let text: String
    let font: Font
    var gap: CGFloat = 48
    /// Points per second.
    var speed: CGFloat = 32

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { textWidth > boxWidth + 1 }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(spacing: gap) {
                    label
                    if overflows { label }
                }
                .offset(x: offset)
            }
            .clipped()
            .mask {
                if overflows {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .task(id: "\(text)|\(overflows)") { await scroll() }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }

    private func scroll() async {
        offset = 0
        guard overflows else { return }
        let distance = textWidth + gap
        let duration = Double(distance / speed)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            if Task.isCancelled { return }
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { offset = 0 }
        }
    }
}

/// Translucent circle used behind the full screen player's star and ••• buttons.
struct GlassCircle<Content: View>: View {
    let size: CGFloat
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(highlighted ? 0.24 : 0.14)))
            .contentShape(Circle())
    }
}

struct GlassCircleButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, size: size)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            GlassCircle(size: size, highlighted: hovering) {
                configuration.label.font(.system(size: size * 0.42, weight: .semibold))
            }
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
        }
    }
}

/// Shuffle / repeat: a filled circle marks them as on.
struct ToggleCircleButtonStyle: ButtonStyle {
    let isOn: Bool
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isOn: isOn, size: size)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isOn: Bool
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(isOn ? 0.95 : (hovering ? 0.85 : 0.6)))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(isOn ? 0.2 : (hovering ? 0.08 : 0))))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isOn)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Back / play-pause / forward: bare glyphs that dip when pressed, with a soft halo on hover.
struct TransportButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, size: size)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.9))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.07 : 0))))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.86 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Thick timeline with the elapsed and remaining times underneath and the audio quality in between.
struct FullscreenProgressBar: View {
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        let duration = max(0.1, engine.duration)
        let fraction = dragFraction ?? min(max(timeTracker.currentTime / duration, 0), 1)
        let shownTime = dragFraction.map { $0 * duration } ?? timeTracker.currentTime
        let active = hovering || dragFraction != nil

        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(active ? 0.26 : 0.2))
                    Capsule().fill(Color.white.opacity(active ? 0.9 : 0.62))
                        .frame(width: max(0, geo.size.width * fraction))
                }
                .frame(height: active ? 11 : 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in dragFraction = min(max(g.location.x / max(geo.size.width, 1), 0), 1) }
                        .onEnded { g in
                            let f = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                            engine.seek(to: f * engine.duration)
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 14)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
            .onHover { hovering = $0 }
            .disabled(engine.currentTrack == nil)

            ZStack {
                HStack {
                    Text(Fmt.time(shownTime))
                    Spacer()
                    Text("–" + Fmt.time(max(0, duration - shownTime)))
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(active ? 0.7 : 0.5))

                if let track = engine.currentTrack {
                    AudioQualityTagsView(track: track, theme: ThemeCatalog.theme(named: "True Black"))
                }
            }
        }
    }
}

/// Lyrics column for the full screen player; the only part that tracks playback time.
struct FullLyricsList: View {
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker
    @State private var activeLineId: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(engine.parsedLyrics) { line in
                        LyricLineView(
                            line: line,
                            isActive: activeLineId == line.id,
                            currentTime: line.isBreak ? timeTracker.currentTime : 0,
                            onSeek: { engine.seek(to: $0) }
                        )
                        .equatable()
                        .id(line.id)
                    }
                }
                .padding(.vertical, 260)
                .padding(.horizontal, 12)
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: timeTracker.currentTime) { _, newValue in
                guard let current = engine.parsedLyrics.last(where: { $0.timestamp <= newValue }),
                      current.id != activeLineId else { return }
                activeLineId = current.id
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - High-performance Equatable Cached Lyric Row Component
struct LyricLineView: View, Equatable {
    let line: SyncedLyricLine
    let isActive: Bool
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void
    @State private var isHovered = false

    static func == (lhs: LyricLineView, rhs: LyricLineView) -> Bool {
        if lhs.line.id != rhs.line.id { return false }
        if lhs.isActive != rhs.isActive { return false }
        if lhs.line.isBreak {
            return Int(lhs.currentTime * 4.0) == Int(rhs.currentTime * 4.0)
        }
        return true
    }

    private static let adlibRegex = try? NSRegularExpression(pattern: "(\\(.*?\\)|\\[.*?\\])", options: [])

    private func parseAdlibs(from text: String) -> (String, String?) {
        guard let regex = Self.adlibRegex else { return (text, nil) }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        if matches.isEmpty { return (text, nil) }

        var adlibs = [String]()
        var mainText = text
        for match in matches.reversed() {
            adlibs.append(nsString.substring(with: match.range))
            mainText = (mainText as NSString).replacingCharacters(in: match.range, with: "")
        }
        let finalMain = mainText.trimmingCharacters(in: .whitespaces)
        let finalAdlibs = adlibs.reversed().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (finalMain.isEmpty ? finalAdlibs : finalMain, finalMain.isEmpty ? nil : finalAdlibs)
    }

    var body: some View {
        Group {
            if line.isBreak {
                InstrumentalBreakDots(currentTime: currentTime, breakStart: line.breakStart, breakEnd: line.breakEnd)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let parsed = parseAdlibs(from: line.text)
                VStack(alignment: .leading, spacing: 4) {
                    Text(parsed.0)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(isActive ? .white : .white.opacity(0.28))
                    if let adlib = parsed.1 {
                        Text(adlib)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(isActive ? .white.opacity(0.55) : .white.opacity(0.14))
                    }
                }
                .blur(radius: isActive ? 0 : 0.6)
                .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .background(isHovered ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture { onSeek(line.timestamp) }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
    }
}
