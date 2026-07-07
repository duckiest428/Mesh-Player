//
//  FullLyricsView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import AppKit
import CoreImage

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

struct FluidBackgroundView: View {
    let isIdle: Bool
    var colors: [Color]
    @State private var phase1 = false
    @State private var phase2 = false
    @State private var phase3 = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if colors.count >= 4 {
                    // Base background
                    colors[3]
                        .edgesIgnoringSafeArea(.all)
                    
                    // Blob 1
                    Ellipse()
                        .fill(colors[0])
                        .frame(width: geo.size.width * 1.0, height: geo.size.height * 1.0)
                        .scaleEffect(phase1 && !isIdle ? 1.2 : 0.8)
                        .offset(x: phase1 && !isIdle ? geo.size.width * 0.1 : -geo.size.width * 0.1,
                                y: phase1 && !isIdle ? geo.size.height * 0.1 : -geo.size.height * 0.1)
                        .rotationEffect(.degrees(phase1 && !isIdle ? 90 : 0))
                        .animation(isIdle ? .none : .easeInOut(duration: 15).repeatForever(autoreverses: true), value: phase1)
                        .onAppear { phase1.toggle() }
                    
                    // Blob 2
                    Ellipse()
                        .fill(colors[1])
                        .frame(width: geo.size.width * 1.1, height: geo.size.height * 0.9)
                        .scaleEffect(phase2 && !isIdle ? 1.3 : 0.9)
                        .offset(x: phase2 && !isIdle ? -geo.size.width * 0.2 : geo.size.width * 0.2,
                                y: phase2 && !isIdle ? geo.size.height * 0.2 : -geo.size.height * 0.1)
                        .rotationEffect(.degrees(phase2 && !isIdle ? -60 : 60))
                        .animation(isIdle ? .none : .easeInOut(duration: 18).repeatForever(autoreverses: true), value: phase2)
                        .onAppear { phase2.toggle() }
                    
                    // Blob 3
                    Ellipse()
                        .fill(colors[2])
                        .frame(width: geo.size.width * 0.9, height: geo.size.height * 1.1)
                        .scaleEffect(phase3 && !isIdle ? 0.9 : 1.4)
                        .offset(x: phase3 && !isIdle ? -geo.size.width * 0.15 : geo.size.width * 0.15,
                                y: phase3 && !isIdle ? -geo.size.height * 0.2 : geo.size.height * 0.2)
                        .rotationEffect(.degrees(phase3 && !isIdle ? 120 : -30))
                        .animation(isIdle ? .none : .easeInOut(duration: 22).repeatForever(autoreverses: true), value: phase3)
                        .onAppear { phase3.toggle() }
                }
            }
            .scaleEffect(1.15)
            .blur(radius: 90, opaque: true)
            .clipped()
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
    }
}

struct FullLyricsView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @ObservedObject var timeTracker: AudioTimeTracker
    @Binding var isPresented: Bool
    
    enum FullLyricsRightPanel {
        case lyrics, queue, output, none
    }
    @State private var rightPanel: FullLyricsRightPanel = .lyrics
    @State private var isAnimating: Bool = false
    @State private var isFavorite: Bool = false
    @State private var isShuffleActive: Bool = false
    @State private var isRepeatActive: Bool = false
    
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var trackToAdd: LocalTrack?
    @State private var activeLineId: UUID? = nil
    @State private var cachedColors: [Color] = []
    
    @State private var isHoveringArt = false
    @State private var isHoveringArtist = false
    
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
        if let track = engine.currentTrack {
            if let colorsHex = track.artworkColors, colorsHex.count >= 4 {
                let extracted = colorsHex.compactMap { Color(hex: $0) }
                if extracted.count >= 4 {
                    withAnimation(.easeInOut(duration: 1.2)) {
                        self.cachedColors = extracted
                    }
                    return
                }
            }
            
            var nsImage: NSImage? = nil
            if let artData = track.embeddedArtData, let img = NSImage(data: artData) {
                nsImage = img
            } else if let imageURL = track.localCoverURL, let img = NSImage(contentsOf: imageURL) {
                nsImage = img
            }
            
            extractDominantColors(from: nsImage, fallback: state.theme.accent) { colors in
                let hexes = colors.map { $0.toHex() ?? "#1A1A1A" }
                
                DispatchQueue.main.async {
                    if let idx = state.tracks.firstIndex(where: { $0.id == track.id }) {
                        state.tracks[idx].artworkColors = hexes
                        engine.currentTrack?.artworkColors = hexes
                    }
                    withAnimation(.easeInOut(duration: 1.2)) {
                        self.cachedColors = colors
                    }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 1.2)) {
                cachedColors = generateComplementaryColors(from: state.theme.accent)
            }
        }
    }
    
    private func extractDominantColors(from image: NSImage?, fallback: Color, completion: @escaping ([Color]) -> Void) {
        let defaultPalette = [
            Color(red: 0.15, green: 0.15, blue: 0.15),
            Color(red: 0.1, green: 0.1, blue: 0.1),
            Color(red: 0.05, green: 0.05, blue: 0.05),
            Color(red: 0.02, green: 0.02, blue: 0.02)
        ]
        
        guard let image = image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.global(qos: .userInitiated).async { completion(defaultPalette) }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let ciImage = CIImage(cgImage: cgImage)
            let w = ciImage.extent.size.width
            let h = ciImage.extent.size.height
            
            let tl = CIVector(x: 0, y: h/2, z: w/2, w: h/2)
            let tr = CIVector(x: w/2, y: h/2, z: w/2, w: h/2)
            let bl = CIVector(x: 0, y: 0, z: w/2, w: h/2)
            let br = CIVector(x: w/2, y: 0, z: w/2, w: h/2)
            
            var colors: [Color] = []
            let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            
            for extent in [tl, tr, bl, br] {
                if let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extent]),
                   let avgOutput = avgFilter.outputImage {
                    var bitmap = [UInt8](repeating: 0, count: 4)
                    context.render(avgOutput, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                    
                    let r = CGFloat(bitmap[0]) / 255.0
                    let g = CGFloat(bitmap[1]) / 255.0
                    let b = CGFloat(bitmap[2]) / 255.0
                    
                    let dominantColor = Color(red: Double(r), green: Double(g), blue: Double(b))
                    colors.append(dominantColor)
                }
            }
            
            if colors.isEmpty {
                completion(defaultPalette)
            } else {
                while colors.count < 4 { colors.append(colors.last!) }
                completion(colors)
            }
        }
    }
    
    private func generateComplementaryColors(from baseColor: Color) -> [Color] {
        return [baseColor.opacity(0.8), baseColor.opacity(0.6), baseColor.opacity(0.4), baseColor.opacity(0.2)]
    }
    
    var body: some View {
        ZStack {
            // Liquid Glass Background
            ZStack {
                FluidBackgroundView(isIdle: state.isIdle, colors: activeBackgroundColors)
                    .animation(.easeInOut(duration: 1.2), value: activeBackgroundColors)
                
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                    .ignoresSafeArea(.all)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                
                // Primary body split: Album details (left) & lyrics list (right)
                HStack(spacing: 64) {
                    let effectiveRightPanel = (rightPanel == .lyrics && engine.parsedLyrics.isEmpty) ? .none : rightPanel
                    
                    if effectiveRightPanel == .none {
                        Spacer()
                    }
                    
                    // LEFT COLUMN: Huge cover art, track metadata & embedded player
                    VStack(spacing: 32) {
                        Button(action: {
                            if let track = engine.currentTrack {
                                state.selectedTab = "albums"
                                state.activeFilterType = "album"
                                state.activeFilterValue = track.album
                                isPresented = false
                            }
                        }) {
                            ZStack {
                                if let primaryColor = cachedColors.first {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(primaryColor)
                                        .frame(width: 380, height: 380)
                                        .blur(radius: 60)
                                        .opacity(0.65)
                                        .animation(.easeOut(duration: 0.8), value: primaryColor)
                                }
                                
                                if let track = engine.currentTrack {
                                    AsyncFlexibleThumbnailView(track: track, maxPixelSize: 760, theme: state.theme, cornerRadius: 24)
                                        .frame(width: 380, height: 380)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .scaleEffect(engine.isPlaying ? (isHoveringArt ? 1.02 : 1.0) : 0.85)
                            .shadow(color: cachedColors.first?.opacity(engine.isPlaying ? 0.6 : 0.2) ?? Color.black.opacity(engine.isPlaying ? 0.5 : 0.2), radius: engine.isPlaying ? 40 : 15, x: 0, y: engine.isPlaying ? 20 : 5)
                            .animation(.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0), value: engine.isPlaying)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringArt)
                            .onHover { isHoveringArt = $0 }
                            
                            // Text descriptions and action row matching the reference layout
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(engine.currentTrack?.title ?? "Not Playing")
                                        .font(.system(size: 24, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    Button(action: {
                                        if let track = engine.currentTrack {
                                            state.selectedTab = "artists"
                                            state.activeFilterType = "artist"
                                            state.activeFilterValue = track.artist
                                            isPresented = false
                                        }
                                    }) {
                                        Text("\(engine.currentTrack?.artist ?? "---") — \(engine.currentTrack?.album ?? "---")")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(isHoveringArtist ? .white : .white.opacity(0.6))
                                            .lineLimit(1)
                                            .underline(isHoveringArtist)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .onHover { isHoveringArtist = $0 }
                                }
                                
                                Spacer()
                                
                                // Elegant transparent circle option triggers
                                HStack(spacing: 12) {
                                    Button(action: {
                                        isFavorite.toggle()
                                        if let currentTrack = engine.currentTrack {
                                            state.toggleFavorite(track: currentTrack)
                                        }
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white.opacity(0.06))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                                )
                                            
                                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                                .font(.system(size: 15))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .buttonStyle(PremiumButtonStyle())
                                    
                                    Menu {
                                        if let track = engine.currentTrack {
                                            Button("Play") {
                                                engine.playTrack(track)
                                            }
                                            
                                            Divider()
                                            
                                            Button(action: {
                                                state.toggleFavorite(track: track)
                                                isFavorite = track.isFavorite
                                            }) {
                                                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.fill" : "heart")
                                            }
                                            
                                            Divider()
                                            
                                            Menu("Add to Playlist") {
                                                Button("New Playlist...") {
                                                    trackToAdd = track
                                                    newPlaylistName = ""
                                                    showNewPlaylistAlert = true
                                                }
                                                
                                                Divider()
                                                
                                                ForEach(state.playlists) { playlist in
                                                    Button(playlist.name) {
                                                        state.addTrackToPlaylist(track: track, playlistId: playlist.id)
                                                    }
                                                }
                                            }
                                            
                                            Divider()
                                            
                                            Button("Show in Finder") {
                                                if let url = track.fileURL {
                                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                                }
                                            }
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white.opacity(0.06))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                                )
                                            
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: 15))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .menuStyle(.borderlessButton)
                                    .frame(width: 40, height: 40)
                                    .buttonStyle(PremiumButtonStyle())
                                }
                            }
                            .frame(width: 420)
                            
                            // Draggable Progress timeline & centring Dolby Atmos underneath
                            VStack(spacing: 12) {
                                Slider(value: Binding(
                                    get: { timeTracker.currentTime },
                                    set: { engine.seek(to: $0) }
                                ), in: 0...max(0.1, engine.duration))
                                .accentColor(.white)
                                .controlSize(.small)
                                
                                // Timestamps elapsed, atmos badge underlay, and remaining
                                HStack {
                                    Text(formatTime(timeTracker.currentTime))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    Spacer()
                                    
                                    if let track = engine.currentTrack {
                                        AudioQualityTagsView(track: track, theme: state.theme)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("-" + formatTime(max(0, engine.duration - timeTracker.currentTime)))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            .frame(width: 420)
                            
                            // Playback Controls (Matches double arrow and flat play styles)
                            HStack(alignment: .center) {
                                // Shuffle switch
                                Button(action: {
                                    engine.triggerHaptic(pattern: .generic)
                                    state.toggleShuffle(currentTrack: engine.currentTrack)
                                }) {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(state.isQueueShuffled ? Color.red : .white.opacity(0.44))
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(PremiumButtonStyle())
                                
                                Spacer()
                                
                                // Back button
                                Button(action: {
                                    engine.triggerHaptic(pattern: .alignment)
                                    state.playPrevious(engine: engine)
                                }) {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(PremiumButtonStyle())
                                
                                Spacer()
                                
                                // Play Pause central toggle (flat button with no colored circle, simple bold toggle)
                                Button(action: {
                                    engine.triggerHaptic(pattern: .generic)
                                    engine.togglePlayPause()
                                }) {
                                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 38))
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                }
                                .buttonStyle(PremiumButtonStyle())
                                
                                Spacer()
                                
                                // Forward button
                                Button(action: {
                                    engine.triggerHaptic(pattern: .alignment)
                                    state.playNext(engine: engine)
                                }) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(PremiumButtonStyle())
                                
                                Spacer()
                                
                                // Repeat switch
                                Button(action: {
                                    engine.triggerHaptic(pattern: .generic)
                                    state.repeatMode = (state.repeatMode + 1) % 3
                                }) {
                                    Image(systemName: state.repeatMode == 2 ? "repeat.1" : "repeat")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(state.repeatMode > 0 ? Color.red : .white.opacity(0.44))
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(PremiumButtonStyle())
                            }
                            .frame(width: 420)
                        }
                        
                        if effectiveRightPanel == .none {
                            Spacer()
                        } else {
                            // RIGHT COLUMN: Selected Panel
                            Group {
                                switch effectiveRightPanel {
                                case .lyrics:
                                    ScrollViewReader { proxy in
                                        ScrollView(showsIndicators: false) {
                                            if engine.parsedLyrics.isEmpty {
                                                EmptyView()
                                            } else {
                                                VStack(alignment: .leading, spacing: 36) {
                                                    ForEach(engine.parsedLyrics) { line in
                                                        LyricLineView(
                                                            line: line,
                                                            isActive: activeLineId == line.id,
                                                            currentTime: timeTracker.currentTime,
                                                            onSeek: { targetTime in
                                                                engine.seek(to: targetTime)
                                                            }
                                                        )
                                                        .equatable()
                                                        .id(line.id)
                                                    }
                                                }
                                                .padding(.vertical, 240) // Centers current line nicely
                                                .padding(.horizontal, 24)
                                            }
                                        }
                                        .frame(width: 540)
                                        .onChange(of: timeTracker.currentTime) { newValue in
                                            if let currentActive = engine.parsedLyrics.last(where: { $0.timestamp <= newValue }) {
                                                if activeLineId != currentActive.id { activeLineId = currentActive.id; withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                                    proxy.scrollTo(currentActive.id, anchor: .center) }
                                                }
                                            }
                                        }
                                    }
                                case .queue:
                                    QueueSidebarView(state: state, engine: engine, timeTracker: engine.timeTracker, isFullscreen: true)
                                        .frame(width: 440)
                                        .cornerRadius(16)
                                        .shadow(radius: 10)
                                        .padding(.vertical, 20)
                                case .output:
                                    OutputDeviceSidebarView(state: state, engine: engine, isFullscreen: true)
                                        .frame(width: 440)
                                        .cornerRadius(16)
                                        .shadow(radius: 10)
                                        .padding(.vertical, 20)
                                case .none:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 48)
                    
                    // Action Layout moved to the bottom (above footer specifications)
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path")
                                .font(.body)
                                .foregroundColor(.red)
                            Text("APPLE MUSIC THEATER PLAYER")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 20) {
                            let hasLyrics = !(engine.currentTrack?.lyrics.isEmpty ?? true)
                            Button(action: {
                                if hasLyrics {
                                    rightPanel = rightPanel == .lyrics ? .none : .lyrics
                                }
                            }) {
                                Image(systemName: "quote.bubble")
                                    .font(.title3)
                                    .foregroundColor(!hasLyrics ? .white.opacity(0.2) : (rightPanel == .lyrics ? .red : .white.opacity(0.6)))
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .disabled(!hasLyrics)
                            .help(hasLyrics ? "Synced Lyrics" : "No Lyrics Available")
                            
                            Button(action: {
                                rightPanel = rightPanel == .queue ? .none : .queue
                            }) {
                                Image(systemName: "list.bullet.rectangle.portrait")
                                    .font(.title3)
                                    .foregroundColor(rightPanel == .queue ? .red : .white.opacity(0.6))
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .help("Playing Next")
                            
                            Button(action: {
                                rightPanel = rightPanel == .output ? .none : .output
                            }) {
                                Image(systemName: "airplayaudio")
                                    .font(.title3)
                                    .foregroundColor(rightPanel == .output ? .indigo : .white.opacity(0.6))
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .help("Audio Output Device")
                        }
                        .padding(.trailing, 20)
                        
                        Button(action: { enableDynamicBackground.toggle(); updateCachedColors() }) {
                            Image(systemName: "drop.halffull")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(enableDynamicBackground ? .white : .white.opacity(0.3))
                        .help("Dynamic Liquid Background")
                        
                        Button(action: { isPresented = false }) {
                            Label("Exit Fullscreen", systemImage: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.15))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.3))
                    
                    // Bottom Specs status line
                    HStack {
                        Text("DAC CORE CONFIG: DIRECT MULTI-CHANNEL")
                        Spacer()
                        Text("DOLBY ATMOS BINAURAL DECODER")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 12)
                    .background(Color.black.opacity(0.5))
                }
                .onAppear {
                    updateCachedColors()
                }
                .onChange(of: engine.currentTrack) { newValue in
                    updateCachedColors()
                }
                .alert("New Playlist", isPresented: $showNewPlaylistAlert, actions: {
                    TextField("Playlist Name", text: $newPlaylistName)
                    Button("Create", action: {
                        if !newPlaylistName.isEmpty {
                            state.createNewPlaylist(name: newPlaylistName, initialTrack: trackToAdd)
                        }
                    })
                    Button("Cancel", role: .cancel, action: {})
                }, message: {
                    Text("Enter a name for the new playlist.")
                })
            }
            .ignoresSafeArea(.all)
        }
        
        private func isLineActive(_ line: SyncedLyricLine) -> Bool {
            if line.isBreak {
                return timeTracker.currentTime >= line.breakStart && timeTracker.currentTime <= line.breakEnd
            }
            return timeTracker.currentTime >= line.timestamp && timeTracker.currentTime < line.endTime
        }
        
        private func formatTime(_ sec: TimeInterval) -> String {
            let m = Int(sec) / 60
            let s = Int(sec) % 60
            return String(format: "%d:%02d", m, s)
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
            if lhs.isHovered != rhs.isHovered { return false }
            if lhs.line.isBreak {
                let lhsStep = Int(lhs.currentTime * 4.0)
                let rhsStep = Int(rhs.currentTime * 4.0)
                return lhsStep == rhsStep
            }
            return true
        }
        
        private func parseAdlibs(from text: String) -> (String, String?) {
            let pattern = "(\\(.*?\\)|\\[.*?\\])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return (text, nil)
            }
            
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            if matches.isEmpty { return (text, nil) }
            
            var adlibs = [String]()
            var mainText = text
            
            for match in matches.reversed() {
                let matchRange = match.range
                let adlib = nsString.substring(with: matchRange)
                adlibs.append(adlib)
                mainText = (mainText as NSString).replacingCharacters(in: matchRange, with: "")
            }
            
            let finalMain = mainText.trimmingCharacters(in: .whitespaces)
            let finalAdlibs = adlibs.reversed().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            
            return (finalMain.isEmpty ? finalAdlibs : finalMain, finalMain.isEmpty ? nil : finalAdlibs)
        }
        
        var body: some View {
            Group {
                if line.isBreak {
                    InstrumentalBreakDots(
                        currentTime: currentTime,
                        breakStart: line.breakStart,
                        breakEnd: line.breakEnd
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let parsed = parseAdlibs(from: line.text)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parsed.0)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(isActive ? .white : .white.opacity(0.24))
                        
                        if let adlib = parsed.1 {
                            Text(adlib)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(isActive ? .white.opacity(0.5) : .white.opacity(0.12))
                        }
                    }
                    .scaleEffect(isActive ? 1.04 : 1.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(isHovered ? Color.white.opacity(0.12).cornerRadius(8) : Color.clear.cornerRadius(8))
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                onSeek(line.timestamp)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
        }
    }
}

