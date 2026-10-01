//
//  Artwork.swift
//  Mesh Player
//
//  Album artwork is kept out of the library database: it is extracted lazily from the
//  audio file (or a cover image next to it), written once to a disk cache, and decoded at
//  the size a view actually needs.
//

import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import SwiftUI

extension Notification.Name {
    /// Posted on the main thread with the artwork key as `object` when artwork is replaced.
    static let meshArtworkUpdated = Notification.Name("MeshArtworkUpdated")
}

nonisolated final class ArtworkStore: @unchecked Sendable {
    static let shared = ArtworkStore()

    let directory: URL
    private let memory = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var missingKeys = Set<String>()
    private var inflight: [String: Task<URL?, Never>] = [:]
    private static let buckets: [CGFloat] = [64, 128, 256, 512, 1024, 1600]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Mesh Player/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 800
        memory.totalCostLimit = 160 * 1024 * 1024
    }

    static func stableHash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key + ".img")
    }

    private static func bucket(for pixelSize: CGFloat) -> CGFloat {
        buckets.first(where: { $0 >= pixelSize }) ?? buckets.last!
    }

    // MARK: Writing

    func store(_ data: Data, forKey key: String, overwrite: Bool = true, notify: Bool = false) {
        let url = fileURL(forKey: key)
        if !overwrite && FileManager.default.fileExists(atPath: url.path) { return }
        try? data.write(to: url, options: .atomic)
        lock.withLock { _ = missingKeys.remove(key) }
        for bucket in Self.buckets {
            memory.removeObject(forKey: "\(key)@\(Int(bucket))" as NSString)
        }
        if notify {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .meshArtworkUpdated, object: key)
            }
        }
    }

    // MARK: Reading

    /// Synchronous memory-cache lookup so already-seen artwork renders without a flash.
    func cachedImage(for track: LocalTrack, pixelSize: CGFloat) -> NSImage? {
        memory.object(forKey: "\(track.artworkKey)@\(Int(Self.bucket(for: pixelSize)))" as NSString)
    }

    /// The sharpest size of this artwork already decoded in memory, if any. Shown (scaled) while
    /// a bigger size loads, so a larger view never flashes the placeholder.
    func anyCachedImage(for track: LocalTrack) -> NSImage? {
        for bucket in Self.buckets.reversed() {
            if let hit = memory.object(forKey: "\(track.artworkKey)@\(Int(bucket))" as NSString) { return hit }
        }
        return nil
    }

    func image(for track: LocalTrack, pixelSize: CGFloat) async -> NSImage? {
        let bucket = Self.bucket(for: pixelSize)
        let memKey = "\(track.artworkKey)@\(Int(bucket))" as NSString
        if let hit = memory.object(forKey: memKey) { return hit }
        guard let source = await sourceURL(for: track) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsample(url: source, maxPixel: bucket)
        }.value
        if let image {
            memory.setObject(image, forKey: memKey, cost: Int(bucket * bucket * 4))
        }
        return image
    }

    /// Raw artwork bytes (used for the Now Playing widget and dock tile).
    func imageData(for track: LocalTrack) async -> Data? {
        guard let url = await sourceURL(for: track) else { return nil }
        return try? Data(contentsOf: url)
    }

    func hasArtwork(for track: LocalTrack) async -> Bool {
        await sourceURL(for: track) != nil
    }

    /// Returns a file that holds artwork for the track, extracting it from the audio file once if needed.
    func sourceURL(for track: LocalTrack) async -> URL? {
        let key = track.artworkKey
        let cached = fileURL(forKey: key)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        if let cover = track.localCoverURL, FileManager.default.fileExists(atPath: cover.path) { return cover }
        guard let audioURL = track.fileURL else { return nil }

        let task: Task<URL?, Never>? = lock.withLock {
            if missingKeys.contains(key) { return nil }
            if let running = inflight[key] { return running }
            let newTask = Task.detached(priority: .utility) { [self] () -> URL? in
                if let data = await Self.extractEmbeddedArtwork(from: audioURL) {
                    self.store(data, forKey: key)
                    return cached
                }
                self.lock.withLock { _ = self.missingKeys.insert(key) }
                return nil
            }
            inflight[key] = newTask
            return newTask
        }
        guard let task else { return nil }
        let result = await task.value
        lock.withLock { inflight[key] = nil }
        return result
    }

    /// JPEG-encoded artwork no larger than `maxPixel` (used when syncing to the iPhone).
    func jpegData(for track: LocalTrack, maxPixel: CGFloat) async -> Data? {
        guard let url = await sourceURL(for: track) else { return nil }
        return await Task.detached(priority: .utility) { () -> Data? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }.value
    }

    static func extractEmbeddedArtwork(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        if let common = try? await asset.load(.commonMetadata) {
            for item in common where item.commonKey == .commonKeyArtwork {
                if let data = try? await item.load(.dataValue) { return data }
            }
        }
        if let all = try? await asset.load(.metadata) {
            for item in all where item.identifier == .iTunesMetadataCoverArt || item.identifier == .id3MetadataAttachedPicture {
                if let data = try? await item.load(.dataValue) { return data }
            }
        }
        return nil
    }

    static func downsample(url: URL, maxPixel: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func downsample(data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Small shared memory cache for non-album images (artist avatars).
final class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()
    let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()
}

// MARK: - Views

/// Deterministic, pleasant placeholder used while artwork loads (or when there is none).
struct ArtworkPlaceholder: View {
    let seed: String
    var symbol: String? = "music.note"

    private static let palettes: [[Color]] = [
        [Color(red: 0.95, green: 0.33, blue: 0.45), Color(red: 0.55, green: 0.18, blue: 0.62)],
        [Color(red: 0.28, green: 0.52, blue: 0.98), Color(red: 0.22, green: 0.18, blue: 0.55)],
        [Color(red: 0.99, green: 0.60, blue: 0.25), Color(red: 0.85, green: 0.22, blue: 0.32)],
        [Color(red: 0.22, green: 0.78, blue: 0.68), Color(red: 0.13, green: 0.35, blue: 0.55)],
        [Color(red: 0.62, green: 0.45, blue: 1.00), Color(red: 0.30, green: 0.18, blue: 0.60)],
        [Color(red: 0.40, green: 0.42, blue: 0.48), Color(red: 0.16, green: 0.17, blue: 0.20)]
    ]

    var body: some View {
        let colors = Self.palettes[Int(UInt(bitPattern: seed.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }) % UInt(Self.palettes.count))]
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: max(10, min(geo.size.width, geo.size.height) * 0.34), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}

struct ArtworkView: View {
    let track: LocalTrack?
    var pixelSize: CGFloat = 256
    var cornerRadius: CGFloat = 6
    /// Symbol drawn on the placeholder; nil draws a plain gradient (used behind blurs).
    var placeholderSymbol: String? = "music.note"

    @State private var image: NSImage?
    @State private var loadedKey: String?

    var body: some View {
        let key = track?.artworkKey
        let shown: NSImage? = (loadedKey == key ? image : nil)
            ?? track.flatMap { ArtworkStore.shared.cachedImage(for: $0, pixelSize: pixelSize) ?? ArtworkStore.shared.anyCachedImage(for: $0) }

        ZStack {
            if let shown {
                Image(nsImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ArtworkPlaceholder(seed: track?.album ?? "", symbol: placeholderSymbol.map { track?.isAtmos == true ? "sparkles" : $0 })
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: key) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .meshArtworkUpdated)) { note in
            guard let changed = note.object as? String, changed == key else { return }
            Task { await load() }
        }
    }

    private func load() async {
        guard let track else {
            image = nil
            loadedKey = nil
            return
        }
        let loaded = await ArtworkStore.shared.image(for: track, pixelSize: pixelSize)
        guard !Task.isCancelled else { return }
        image = loaded
        loadedKey = track.artworkKey
    }
}

/// Fixed-size artwork thumbnail (size is in points).
struct AsyncThumbnailView: View {
    let track: LocalTrack
    let size: CGFloat
    let theme: ThemeColor
    var cornerRadius: CGFloat = 4

    var body: some View {
        ArtworkView(track: track, pixelSize: size * 2, cornerRadius: cornerRadius)
            .frame(width: size, height: size)
    }
}

/// Artwork that fills whatever frame it is given (maxPixelSize is in pixels).
struct AsyncFlexibleThumbnailView: View {
    let track: LocalTrack
    let maxPixelSize: CGFloat
    let theme: ThemeColor
    var cornerRadius: CGFloat = 4

    var body: some View {
        ArtworkView(track: track, pixelSize: maxPixelSize, cornerRadius: cornerRadius)
    }
}
