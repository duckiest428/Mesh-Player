//
//  Theme.swift
//  Mesh Player iOS
//
//  The theme follows the Mac's (sent when syncing) unless one is picked on the iPhone, plus the
//  artwork-tinted backgrounds Apple Music uses on album, playlist and Now Playing screens.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var meshTheme: ThemeColor = ThemeCatalog.theme(named: "Mesh Default (Apple Music)")
}

enum MeshTheme {
    static let followMac = ""

    /// The theme in use: the iPhone's own choice, else the Mac's, else the default.
    static func current(override: String, library: MobileLibrary) -> ThemeColor {
        ThemeCatalog.theme(named: name(override: override, library: library))
    }

    static func name(override: String, library: MobileLibrary) -> String {
        if !override.isEmpty { return override }
        return library.settings?.themeName ?? "Mesh Default (Apple Music)"
    }
}

/// Dominant colors of a cover, darkened enough for white text — cached per artwork key.
enum ArtworkPalette {
    private static var cache: [String: [Color]] = [:]

    static func cached(_ key: String?) -> [Color]? {
        key.flatMap { cache[$0] }
    }

    static func colors(for key: String?, darken: Double = 0.62) async -> [Color]? {
        guard let key else { return nil }
        if let hit = cache[key] { return hit }
        guard let image = await ArtworkCache.shared.image(key, size: 60), let cg = image.cgImage else { return nil }
        let colors = await Task.detached(priority: .utility) { () -> [Color]? in
            let width = 8, height = 8
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            func average(rows: Range<Int>) -> Color {
                var r = 0, g = 0, b = 0, n = 0
                for y in rows { for x in 0..<width { let i = (y * width + x) * 4; r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2]); n += 1 } }
                let (rr, gg, bb) = (Double(r) / Double(n) / 255, Double(g) / Double(n) / 255, Double(b) / Double(n) / 255)
                // Keep the hue, cap the brightness so white text always reads.
                let brightest = max(rr, gg, bb)
                let scale = brightest > darken ? darken / brightest : 1
                return Color(red: rr * scale, green: gg * scale, blue: bb * scale)
            }
            return [average(rows: 4..<8), average(rows: 0..<4)] // CG rows are bottom-up: top of the image first
        }.value
        if let colors { cache[key] = colors }
        return colors
    }
}

/// Background for album and playlist pages: the cover's color fading into the theme background.
struct ArtworkTintBackground: View {
    let artworkKey: String?
    @Environment(\.meshTheme) private var theme
    @State private var colors: [Color]?

    var body: some View {
        let top = colors?.first ?? theme.background
        LinearGradient(colors: [top, top.opacity(0.85), theme.background], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: colors?.first)
            .task(id: artworkKey) {
                colors = ArtworkPalette.cached(artworkKey)
                if colors == nil { colors = await ArtworkPalette.colors(for: artworkKey, darken: 0.42) }
            }
    }
}
