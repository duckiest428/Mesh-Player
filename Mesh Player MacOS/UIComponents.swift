import AppKit
import CoreGraphics
import SwiftUI

// MARK: - PremiumButtonStyle.swift
//
//  PremiumButtonStyle.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-22.
//  SPDX-License-Identifier: Apache-2.0
//


struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PremiumButtonWrapper(configuration: configuration)
    }
}

private struct PremiumButtonWrapper: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : (isHovered ? 1.12 : 1.0))
            .opacity(configuration.isPressed ? 0.75 : (isHovered ? 1.0 : 0.88))
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: configuration.isPressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isHovered)
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - AudioQualityTags.swift
struct AudioQualityPopup: View {
    let track: LocalTrack
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 8) {
            // 1. Audio Format
            Text(track.isAtmos ? "Dolby Atmos" : (track.format == "Lossless" ? "Lossless" : track.format.uppercased()))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            // 2. Audio format notes
            Text(track.isAtmos ? "Spatial Audio with Dolby Atmos" : (track.format == "Lossless" ? "Apple Lossless Audio Codec" : "Advanced Audio Coding"))
                .font(.system(size: 11))
                .italic()
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            // 3. Channels
            if track.isAtmos {
                Text("Channels: Spatial Audio")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            } else if let channels = track.channels {
                Text("Channels: \(channels == 2 ? "Stereo" : (channels == 1 ? "Mono" : "\(channels)"))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Channels: Stereo")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 4. Sample Rate & Bitrate
            if !track.isAtmos {
                let sampleRateStr = track.sampleRate != nil ? String(format: "%.1f kHz", track.sampleRate! / 1000.0) : "44.1 kHz"
                let bitRateStr = track.bitRate != nil ? "\(track.bitRate!) kbps" : "256 kbps"
                Text("Sample Rate: \(sampleRateStr) / \(bitRateStr)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Sample Rate: 48.0 kHz / 768 kbps")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 5. Thin Divider Line
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)
            
            // 6. "Audio Settings" action button
            Button(action: {}) {
                Text("Audio Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            
            // 7. Thin Divider Line
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)
            
            // 8. "OK" dismiss button
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(20)
        .frame(width: 240)
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
}

struct AudioQualityTagsView: View {
    let track: LocalTrack
    let theme: ThemeColor
    @State private var showingPopover = false
    
    var body: some View {
        HStack(spacing: 4) {
            if track.isAtmos {
                Button(action: {
                    showingPopover = true
                }) {
                    DolbyAtmosBadge(color: .blue, scale: 0.85, showText: true)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else if track.format == "Lossless" {
                Button(action: {
                    showingPopover = true
                }) {
                    Text("Lossless")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                Button(action: {
                    showingPopover = true
                }) {
                    Text(track.format)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.cardBackground)
                        .foregroundColor(theme.textSecondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            AudioQualityPopup(track: track)
        }
    }
}

// MARK: - ImageUtil.swift
func getDownsampledImage(from data: Data?, url: URL?, size: CGFloat = 200) -> NSImage? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: size * 2 // Retina scale
    ]
    
    var source: CGImageSource?
    if let data = data {
        source = CGImageSourceCreateWithData(data as CFData, nil)
    } else if let url = url {
        source = CGImageSourceCreateWithURL(url as CFURL, nil)
    }
    
    guard let imageSource = source,
          let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
        return nil
    }
    
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

// MARK: - ImageCacheManager
final class ImageCacheManager: @unchecked Sendable {
    static let shared = ImageCacheManager()
    let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.meshplayer.imagecache", attributes: .concurrent)
    private let semaphore = DispatchSemaphore(value: 8)
    
    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }
    
    func loadImage(for track: LocalTrack, targetSize: CGFloat) async -> NSImage? {
        let artHash = track.embeddedArtData?.hashValue ?? 0
        let cacheKey = NSString(string: "\(track.id.uuidString)_\(artHash)_\(Int(targetSize))")
        
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        return await withCheckedContinuation { continuation in
            queue.async {
                self.semaphore.wait()
                let downsampled = getDownsampledImage(from: track.embeddedArtData, url: track.localCoverURL, size: targetSize)
                self.semaphore.signal()
                
                if let img = downsampled {
                    let cost = Int(img.size.width * img.size.height * 4)
                    self.cache.setObject(img, forKey: cacheKey, cost: cost)
                }
                continuation.resume(returning: downsampled)
            }
        }
    }
}

class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()
    var cache: NSCache<NSString, NSImage> {
        return ImageCacheManager.shared.cache
    }
    
    func generate(for track: LocalTrack, size: CGFloat, completion: @escaping (NSImage?) -> Void) {
        Task {
            let img = await ImageCacheManager.shared.loadImage(for: track, targetSize: size)
            await MainActor.run {
                completion(img)
            }
        }
    }
}

struct AsyncThumbnailView: View {
    let track: LocalTrack
    let size: CGFloat
    let theme: ThemeColor
    var cornerRadius: CGFloat = 4
    
    @State private var thumbnail: NSImage?
    
    static let thumbnailCache = ImageCacheManager.shared.cache
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(theme.cardBackground)
                .frame(width: size, height: size)
                
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .cornerRadius(cornerRadius)
            } else {
                Image(systemName: track.coverImageName)
                    .font(.system(size: size * 0.4))
                    .foregroundColor(theme.accent)
            }
        }
        .task(id: "\(track.id.uuidString)_\(size)") {
            thumbnail = await ImageCacheManager.shared.loadImage(for: track, targetSize: size)
        }
    }
}

struct AsyncFlexibleThumbnailView: View {
    let track: LocalTrack
    let maxPixelSize: CGFloat
    let theme: ThemeColor
    var cornerRadius: CGFloat = 4
    
    @State private var thumbnail: NSImage?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(theme.cardBackground)
            
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .cornerRadius(cornerRadius)
            } else {
                Image(systemName: track.coverImageName)
                    .font(.system(size: maxPixelSize * 0.4))
                    .foregroundColor(theme.accent)
            }
        }
        .task(id: "\(track.id.uuidString)_\(maxPixelSize)") {
            thumbnail = await ImageCacheManager.shared.loadImage(for: track, targetSize: maxPixelSize)
        }
    }
}


