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

struct FullLyricsView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    @Binding var isPresented: Bool
    
    enum FullLyricsRightPanel {
        case lyrics, queue, output, none
    }
    @State private var rightPanel: FullLyricsRightPanel = .lyrics
    @State private var isAnimating: Bool = false
    @State private var isFavorite: Bool = false
    @State private var isShuffleActive: Bool = false
    @State private var isRepeatActive: Bool = false
    @State private var activeLineId: UUID? = nil
    @State private var cachedColors: [Color] = []
    
    @State private var isHoveringArt = false
    @State private var isHoveringArtist = false

    private var activeBackgroundColors: [Color] {
        if cachedColors.isEmpty {
            return generateComplementaryColors(from: state.theme.accent)
        }
        return cachedColors
    }
    
    private func updateCachedColors() {
        if let track = engine.currentTrack {
            var nsImage: NSImage? = nil
            if let artData = track.embeddedArtData, let img = NSImage(data: artData) {
                nsImage = img
            } else if let imageURL = track.localCoverURL, let img = NSImage(contentsOf: imageURL) {
                nsImage = img
            }
            extractDominantColors(from: nsImage, fallback: state.theme.accent) { colors in
                withAnimation(.easeOut(duration: 0.8)) {
                    self.cachedColors = colors
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.8)) {
                cachedColors = generateComplementaryColors(from: state.theme.accent)
            }
        }
    }

    private func extractDominantColors(from image: NSImage?, fallback: Color, completion: @escaping ([Color]) -> Void) {
        guard let image = image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async { completion(self.generateComplementaryColors(from: fallback)) }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let ciImage = CIImage(cgImage: cgImage)
            let extentVector = CIVector(x: ciImage.extent.origin.x, y: ciImage.extent.origin.y, z: ciImage.extent.size.width, w: ciImage.extent.size.height)
            
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extentVector]),
                  let outputImage = filter.outputImage else {
                DispatchQueue.main.async { completion(self.generateComplementaryColors(from: fallback)) }
                return
            }
            
            var bitmap = [UInt8](repeating: 0, count: 4)
            let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
            context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            
            let r = CGFloat(bitmap[0]) / 255.0
            let g = CGFloat(bitmap[1]) / 255.0
            let b = CGFloat(bitmap[2]) / 255.0
            
            let dominantColor = Color(red: Double(r), green: Double(g), blue: Double(b))
            
            let hsb = NSColor(red: r, green: g, blue: b, alpha: 1.0)
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bri: CGFloat = 0
            var alpha: CGFloat = 0
            hsb.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            
            let secondaryHue = fmod(hue + 0.15, 1.0)
            let secondaryColor = Color(hue: Double(secondaryHue), saturation: Double(sat), brightness: Double(max(0.3, bri - 0.2)))
            
            var colors: [Color] = []
            for i in 0..<9 {
                colors.append(i % 2 == 0 ? dominantColor : secondaryColor)
            }
            
            DispatchQueue.main.async {
                completion(colors)
            }
        }
    }

    private func generateComplementaryColors(from baseColor: Color) -> [Color] {
        let ns = NSColor(baseColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        var colors: [Color] = []
        let hueOffsets: [CGFloat] = [0.0, 0.05, -0.05, 0.08, -0.08, 0.12, -0.12, 0.15, -0.15]
        let scaleSats: [CGFloat] = [0.8, 0.95, 0.75, 0.9, 0.7, 0.85, 0.65, 0.8, 0.9]
        let scaleBrights: [CGFloat] = [0.5, 0.65, 0.45, 0.6, 0.75, 0.55, 0.6, 0.45, 0.75]
        for i in 0..<9 {
            let h = (hue + hueOffsets[i] + 1.0).truncatingRemainder(dividingBy: 1.0)
            let s = min(max(saturation * scaleSats[i], 0.35), 0.95)
            let b = min(max(brightness * scaleBrights[i], 0.25), 0.8)
            let newNS = NSColor(hue: h, saturation: s, brightness: b, alpha: 1.0)
            colors.append(Color(newNS))
        }
        return colors
    }
    
    var body: some View {
        ZStack {
            // Dark elegant background with soft blue atmospheric glow
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Dynamic animated fluid MeshGradient or fluidly breathing circles
            Group {
                if #available(macOS 15.0, iOS 18.0, *) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let speed = engine.isPlaying ? 0.35 : 0.08
                        let xOffset = Float(sin(time * speed) * 0.15)
                        let yOffset = Float(cos(time * speed * 0.7) * 0.15)
                        
                        let xOffset2 = Float(cos(time * speed * 1.3) * 0.12)
                        let yOffset2 = Float(sin(time * speed) * 0.12)
                        
                        let points: [SIMD2<Float>] = [
                            [0.0, 0.0], [0.5 + xOffset2, 0.0], [1.0, 0.0],
                            [0.0, 0.5 + yOffset2], [0.5 + xOffset, 0.5 + yOffset], [1.0, 0.5 + yOffset2],
                            [0.0, 1.0], [0.5 + xOffset2, 1.0], [1.0, 1.0]
                        ]
                        
                        MeshGradient(
                            width: 3,
                            height: 3,
                            points: points,
                            colors: activeBackgroundColors
                        )
                    }
                } else {
                    ZStack {
                        // Blob 1
                        Circle()
                            .fill(activeBackgroundColors.count > 4 ? activeBackgroundColors[4] : state.theme.accent.opacity(0.28))
                            .frame(width: 480, height: 480)
                            .offset(x: isAnimating ? -140 : 140, y: isAnimating ? -100 : 120)
                            .scaleEffect(isAnimating ? 1.25 : 0.8)
                        
                        // Blob 2
                        Circle()
                            .fill(activeBackgroundColors.count > 7 ? activeBackgroundColors[7] : Color.indigo.opacity(0.24))
                            .frame(width: 550, height: 550)
                            .offset(x: isAnimating ? 180 : -120, y: isAnimating ? 120 : -140)
                            .scaleEffect(isAnimating ? 0.85 : 1.3)
                        
                        // Blob 3
                        Circle()
                            .fill(activeBackgroundColors.count > 2 ? activeBackgroundColors[2] : Color.purple.opacity(0.22))
                            .frame(width: 420, height: 420)
                            .offset(x: isAnimating ? -60 : 100, y: isAnimating ? 160 : -110)
                            .scaleEffect(isAnimating ? 1.2 : 0.85)
                    }
                    .blur(radius: 110)
                    .opacity(engine.isPlaying ? 0.65 : 0.35)
                    .animation(engine.isPlaying ? .easeInOut(duration: 18.0).repeatForever(autoreverses: true) : .default, value: isAnimating)
                    .onAppear {
                        isAnimating = true
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            // Dark elegant vignette details
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.7)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                
                // Primary body split: Album details (left) & lyrics list (right)
                HStack(spacing: 64) {
                    if rightPanel == .none {
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
                                    if let artData = track.embeddedArtData, let nsImage = NSImage(data: artData) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 380, height: 380)
                                            .cornerRadius(24)
                                    } else if let imageURL = track.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 380, height: 380)
                                            .cornerRadius(24)
                                    } else {
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(LinearGradient(
                                                gradient: Gradient(colors: [state.theme.accent, state.theme.background]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(width: 380, height: 380)
                                        
                                        Image(systemName: track.coverImageName)
                                            .font(.system(size: 130))
                                            .foregroundColor(.white)
                                    }
                                    
                                    AnimatedArtworkView(track: track, cornerRadius: 24)
                                        .frame(width: 380, height: 380)
                                        .allowsHitTesting(false)
                                } else {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(width: 380, height: 380)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isHoveringArt ? 1.02 : 1.0)
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
                                    Button(action: {
                                        // Play Next simulation
                                    }) {
                                        Label("Play Next", systemImage: "text.insert")
                                    }
                                    Button(action: {
                                        // Play Later simulation
                                    }) {
                                        Label("Play Later", systemImage: "text.append")
                                    }
                                    Divider()
                                    Button(action: {
                                        if let current = engine.currentTrack {
                                            state.toggleFavorite(track: current)
                                            isFavorite = current.isFavorite
                                        }
                                    }) {
                                        Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.fill" : "heart")
                                    }
                                    Button(role: .destructive, action: {
                                        // Remove simulation
                                    }) {
                                        Label("Remove...", systemImage: "trash")
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
                                get: { engine.currentTime },
                                set: { engine.seek(to: $0) }
                            ), in: 0...max(0.1, engine.duration))
                            .accentColor(.white)
                            .controlSize(.small)
                            
                            // Timestamps elapsed, atmos badge underlay, and remaining
                            HStack {
                                Text(formatTime(engine.currentTime))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Spacer()
                                
                                if engine.isAtmosTrack {
                                    DolbyAtmosBadge(color: .white, scale: 1.1, showText: true)
                                } else {
                                    Text(engine.currentTrack?.format ?? "AAC 256kbps")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(4)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                Text("-" + formatTime(max(0, engine.duration - engine.currentTime)))
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
                                isShuffleActive.toggle()
                            }) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(isShuffleActive ? Color.red : .white.opacity(0.44))
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(PremiumButtonStyle())
                            
                            Spacer()
                            
                            // Back button
                            Button(action: {
                                engine.triggerHaptic(pattern: .alignment)
                                if let current = engine.currentTrack, let idx = state.tracks.firstIndex(where: { $0.id == current.id }) {
                                    let prevIdx = (idx - 1 + state.tracks.count) % state.tracks.count
                                    engine.playTrack(state.tracks[prevIdx])
                                }
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
                                if let current = engine.currentTrack, let idx = state.tracks.firstIndex(where: { $0.id == current.id }) {
                                    let nextIdx = (idx + 1) % state.tracks.count
                                    engine.playTrack(state.tracks[nextIdx])
                                }
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
                                isRepeatActive.toggle()
                            }) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(isRepeatActive ? Color.red : .white.opacity(0.44))
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(PremiumButtonStyle())
                        }
                        .frame(width: 420)
                    }
                    
                    if rightPanel == .none {
                            Spacer()
                        } else {
                            // RIGHT COLUMN: Selected Panel
                            Group {
                                switch rightPanel {
                                case .lyrics:
                                    ScrollViewReader { proxy in
                                        ScrollView(showsIndicators: false) {
                                            if engine.parsedLyrics.isEmpty {
                                                VStack(spacing: 16) {
                                                    Spacer()
                                                    Image(systemName: "waveform.circle")
                                                        .font(.system(size: 56))
                                                        .foregroundColor(.red.opacity(0.8))
                                                    Text("Instrumental Track")
                                                        .font(.title3)
                                                        .bold()
                                                        .foregroundColor(.white)
                                                    Text("Listening to spatial audio waves. Dolby is dynamically mixing objects above and around you.")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                        .multilineTextAlignment(.center)
                                                        .frame(maxWidth: 320)
                                                    Spacer()
                                                }
                                                .frame(height: 500)
                                            } else {
                                                VStack(alignment: .leading, spacing: 36) {
                                                    ForEach(engine.parsedLyrics) { line in
                                                        LyricLineView(
                                                            line: line,
                                                            isActive: activeLineId == line.id,
                                                            currentTime: engine.currentTime,
                                                            onSeek: { targetTime in
                                                                engine.seek(to: targetTime)
                                                            }
                                                        )
                                                        .id(line.id)
                                                    }
                                                }
                                                .padding(.vertical, 240) // Centers current line nicely
                                                .padding(.horizontal, 24)
                                            }
                                        }
                                        .frame(width: 540)
                                        .onChange(of: engine.currentTime) { newValue in
                                            if let currentActive = engine.parsedLyrics.last(where: { $0.timestamp <= newValue }) {
                                                if activeLineId != currentActive.id { activeLineId = currentActive.id; withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                                    proxy.scrollTo(currentActive.id, anchor: .center) }
                                                }
                                            }
                                        }
                                    }
                                case .queue:
                                    QueueSidebarView(state: state, engine: engine, isFullscreen: true)
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
                        Button(action: {
                            rightPanel = rightPanel == .lyrics ? .none : .lyrics
                        }) {
                            Image(systemName: "quote.bubble")
                                .font(.title3)
                                .foregroundColor(rightPanel == .lyrics ? .red : .white.opacity(0.6))
                        }
                        .buttonStyle(PremiumButtonStyle())
                        .help("Synced Lyrics")
                        
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
                    
                    Button(action: { isPresented = false }) {
                        Label("Exit Fullscreen", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.15))
                    .foregroundColor(.white)
                    .cornerRadius(20)
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
        }
    }
    
    private func isLineActive(_ line: SyncedLyricLine) -> Bool {
        if line.isBreak {
            return engine.currentTime >= line.breakStart && engine.currentTime <= line.breakEnd
        }
        return engine.currentTime >= line.timestamp && engine.currentTime < line.endTime
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
    
    static func == (lhs: LyricLineView, rhs: LyricLineView) -> Bool {
        if lhs.line.id != rhs.line.id { return false }
        if lhs.isActive != rhs.isActive { return false }
        if lhs.line.isBreak {
            // Only update break dots when 0.25s intervals cross over
            let lhsStep = Int(lhs.currentTime * 4.0)
            let rhsStep = Int(rhs.currentTime * 4.0)
            return lhsStep == rhsStep
        }
        return true
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
                Text(line.text)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(isActive ? .white : .white.opacity(0.24))
                    .scaleEffect(isActive ? 1.04 : 1.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek(line.timestamp)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}
