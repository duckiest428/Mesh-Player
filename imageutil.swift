import SwiftUI
import AppKit
import CoreGraphics

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

struct AsyncThumbnailView: View {
    let track: LocalTrack
    let size: CGFloat
    let theme: ThemeColor
    var cornerRadius: CGFloat = 4
    
    @State private var thumbnail: NSImage?
    
    static let thumbnailCache = NSCache<NSString, NSImage>()
    
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
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        let cacheKey = NSString(string: "\(track.id.uuidString)_\(size)")
        if let cached = AsyncThumbnailView.thumbnailCache.object(forKey: cacheKey) {
            self.thumbnail = cached
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let downsampled = getDownsampledImage(from: track.embeddedArtData, url: track.localCoverURL, size: size)
            
            if let img = downsampled {
                AsyncThumbnailView.thumbnailCache.setObject(img, forKey: cacheKey)
                DispatchQueue.main.async {
                    self.thumbnail = img
                }
            }
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
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        let cacheKey = NSString(string: "\(track.id.uuidString)_\(maxPixelSize)")
        if let cached = AsyncThumbnailView.thumbnailCache.object(forKey: cacheKey) {
            self.thumbnail = cached
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let downsampled = getDownsampledImage(from: track.embeddedArtData, url: track.localCoverURL, size: maxPixelSize)
            
            if let img = downsampled {
                AsyncThumbnailView.thumbnailCache.setObject(img, forKey: cacheKey)
                DispatchQueue.main.async {
                    self.thumbnail = img
                }
            }
        }
    }
}
