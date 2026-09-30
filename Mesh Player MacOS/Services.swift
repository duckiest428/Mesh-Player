import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI

// MARK: - ArtistProfilePictureService.swift
actor ArtistProfilePictureService {
    static let shared = ArtistProfilePictureService()
    
    private let urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config)
    }
    
    func fetchAndCacheProfilePicture(for artistName: String) async throws -> URL? {
        guard !artistName.isEmpty && artistName != "Unknown Artist" else { return nil }
        
        // 1. Local Cache Check
        let fileManager = FileManager.default
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let safeName = artistName.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression).lowercased()
        let fileURL = cacheDir.appendingPathComponent("artist_avatar_\(safeName).jpg")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        guard let encodedArtist = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // 2. Try Deezer API for direct high-res artist avatars
        if let deezerURL = URL(string: "https://api.deezer.com/search/artist?q=\(encodedArtist)"),
           let (deezerData, _) = try? await urlSession.data(from: deezerURL) {
            struct DeezerArtistResponse: Decodable {
                let data: [DeezerArtist]?
                struct DeezerArtist: Decodable {
                    let picture_xl: String?
                    let picture_big: String?
                    let picture_medium: String?
                }
            }
            if let decoded = try? JSONDecoder().decode(DeezerArtistResponse.self, from: deezerData),
               let firstArtist = decoded.data?.first,
               let picStr = firstArtist.picture_xl ?? firstArtist.picture_big ?? firstArtist.picture_medium,
               let imageDownloadURL = URL(string: picStr),
               let (imgData, _) = try? await urlSession.data(from: imageDownloadURL) {
                try? imgData.write(to: fileURL)
                return fileURL
            }
        }
        
        // 3. Fallback to iTunes API Search
        if let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encodedArtist)&entity=musicArtist&limit=1"),
           let (data, _) = try? await urlSession.data(from: searchURL) {
            struct SearchResponse: Decodable {
                let results: [ArtistResult]
                struct ArtistResult: Decodable {
                    let artistLinkUrl: String?
                }
            }
            if let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
               let artistLinkUrlString = response.results.first?.artistLinkUrl,
               let artistLinkUrl = URL(string: artistLinkUrlString),
               let (htmlData, _) = try? await urlSession.data(from: artistLinkUrl),
               let htmlString = String(data: htmlData, encoding: .utf8) {
                let pattern = "<meta\\s+property=\"og:image\"\\s+content=\"([^\"]+)\"\\s*/?>"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: htmlString.utf16.count)
                    if let match = regex.firstMatch(in: htmlString, options: [], range: range),
                       let contentRange = Range(match.range(at: 1), in: htmlString),
                       let imageUrl = URL(string: String(htmlString[contentRange])),
                       let (imageData, _) = try? await urlSession.data(from: imageUrl) {
                        try? imageData.write(to: fileURL)
                        return fileURL
                    }
                }
            }
        }
        
        return nil
    }
}

// MARK: - ArtistBiographyService.swift
actor ArtistBiographyService {
    static let shared = ArtistBiographyService()
    
    private let urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config)
    }
    
    /// Fetches and locally caches an artist's biography text using Wikipedia / AudioDB multi-tiered fallbacks.
    /// Returns nil gracefully if all lookups fail.
    func fetchAndCacheArtistBio(for artistName: String) async -> String? {
        guard !artistName.isEmpty && artistName != "Unknown Artist" && artistName != "Local Artist" else {
            return nil
        }
        
        // 1. Local Cache Check
        let fileManager = FileManager.default
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let safeName = artistName.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression).lowercased()
        let txtFileURL = cacheDir.appendingPathComponent("\(safeName)_bio.txt")
        
        if fileManager.fileExists(atPath: txtFileURL.path),
           let cachedText = try? String(contentsOf: txtFileURL, encoding: .utf8),
           !cachedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cachedText
        }
        
        guard let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Step 1: Wikipedia Open Search / Extract API
        if let wikiURL = URL(string: "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=1&explaintext=1&titles=\(encodedName)&format=json&redirects=1"),
           let (wikiData, _) = try? await urlSession.data(from: wikiURL),
           let bioText = parseWikipediaExtract(from: wikiData),
           !bioText.isEmpty {
            let cleaned = cleanBioText(bioText)
            try? cleaned.write(to: txtFileURL, atomically: true, encoding: .utf8)
            return cleaned
        }
        
        // Step 2: AudioDB Backup Fallback
        if let audioDbURL = URL(string: "https://www.theaudiodb.com/api/v1/json/2/search.php?s=\(encodedName)"),
           let (adbData, _) = try? await urlSession.data(from: audioDbURL),
           let adbBio = parseAudioDbExtract(from: adbData),
           !adbBio.isEmpty {
            let cleaned = cleanBioText(adbBio)
            try? cleaned.write(to: txtFileURL, atomically: true, encoding: .utf8)
            return cleaned
        }
        
        return nil
    }
    
    private func parseWikipediaExtract(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else {
            return nil
        }
        
        for (_, pageObj) in pages {
            if let pageDict = pageObj as? [String: Any],
               let extract = pageDict["extract"] as? String,
               !extract.isEmpty {
                return extract
            }
        }
        return nil
    }
    
    private func parseAudioDbExtract(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artists = json["artists"] as? [[String: Any]],
              let firstArtist = artists.first,
              let bio = firstArtist["strBiographyEN"] as? String,
              !bio.isEmpty else {
            return nil
        }
        return bio
    }
    
    private func cleanBioText(_ raw: String) -> String {
        var text = raw
        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Remove citation brackets like [1], [citation needed]
        text = text.replacingOccurrences(of: "\\[\\d+\\]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[citation needed\\]", with: "", options: [.regularExpression, .caseInsensitive])
        // Trim double spaces or excess newlines
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ArtistBioView.swift (UI Integration Template)
struct ArtistBioView: View {
    let artistName: String
    let themeAccent: Color
    let textColor: Color
    
    @State private var biographyText: String? = nil
    @State private var isExpanded: Bool = false
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About \(artistName)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(textColor)
            
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading Biography...")
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.6))
                }
                .padding(.vertical, 8)
            } else {
                let bio = biographyText ?? "\(artistName) is a featured artist in your library. Explore their top tracks, albums, and statistics in Mesh Player."
                Text(bio)
                    .font(.subheadline)
                    .foregroundColor(textColor.opacity(0.85))
                    .lineSpacing(4)
                    .lineLimit(isExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Read Less" : "Read More")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(themeAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
        .task(id: artistName) {
            await loadBio()
        }
    }
    
    private func loadBio() async {
        guard !artistName.isEmpty && artistName != "Unknown Artist" else {
            biographyText = "Explore tracks and albums from \(artistName) in your Mesh Player library."
            return
        }
        isLoading = true
        defer { isLoading = false }
        
        let bio = await ArtistBiographyService.shared.fetchAndCacheArtistBio(for: artistName)
        await MainActor.run {
            self.biographyText = bio ?? "\(artistName) is a featured artist in your local music library. Stream their top tracks, create custom playlists, and view listening statistics in Mesh Player."
        }
    }
}

// MARK: - CachedArtistBannerService.swift
//
//  CachedArtistBannerService.swift
//  Mesh Player
//
//  Created by Peter Luedtke on 2026-07-20.
//



/// A service to fetch and locally cache high-resolution artist banner images from Apple Music.
actor CachedArtistBannerService {
    
    static let shared = CachedArtistBannerService()
    
    private let cacheDirectory: URL
    private let session: URLSession
    
    init() {
        // Set up the local Caches directory for offline storage
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let baseCacheDir = paths[0]
        self.cacheDirectory = baseCacheDir.appendingPathComponent("ArtistBanners", isDirectory: true)
        
        // Ensure the directory exists
        if !FileManager.default.fileExists(atPath: self.cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        }
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    /// Fetches a high-resolution banner for the specified artist.
    /// Returns a local file URL pointing to the cached image.
    func fetchAndCacheArtistBanner(for artistName: String) async throws -> URL? {
        guard !artistName.isEmpty else { return nil }
        
        // 1. Local Cache Check
        let sanitizedName = artistName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "UnknownArtist"
        
        let cachedFileURL = cacheDirectory.appendingPathComponent("\(sanitizedName).jpg")
        
        if FileManager.default.fileExists(atPath: cachedFileURL.path) {
            return cachedFileURL
        }
        
        // 2. Step 1 (iTunes API Search)
        guard let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encodedName)&entity=musicArtist&limit=1") else {
            throw URLError(.badURL)
        }
        
        let (searchData, _) = try await session.data(from: searchURL)
        
        guard let json = try JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let firstResult = results.first,
              let artistLinkUrlString = firstResult["artistLinkUrl"] as? String,
              let artistURL = URL(string: artistLinkUrlString) else {
            return nil
        }
        
        // 3. Step 2 (Apple Music Web Scraping)
        // Perform an HTTP GET request to the artist's Apple Music page.
        var request = URLRequest(url: artistURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (htmlData, _) = try await session.data(for: request)
        guard let htmlString = String(data: htmlData, encoding: .utf8) else {
            return nil
        }
        
        // Lightweight Regex to find the <meta property="og:image" content="..." />
        let pattern = "<meta[^>]+property=\"og:image\"[^>]+content=\"([^\"]+)\""
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        
        let nsRange = NSRange(htmlString.startIndex..<htmlString.endIndex, in: htmlString)
        guard let match = regex.firstMatch(in: htmlString, options: [], range: nsRange),
              let contentRange = Range(match.range(at: 1), in: htmlString) else {
            return nil
        }
        
        let imageURLString = String(htmlString[contentRange])
        
        // Optionally request a higher resolution by replacing the standard dimensions in the URL.
        // e.g. "1200x630cw.jpg" to "2000x2000cw.jpg" (or similar if applicable).
        let highResURLString = imageURLString.replacingOccurrences(of: "1200x630cw", with: "2000x2000cc")
        
        guard let imageURL = URL(string: highResURLString) ?? URL(string: imageURLString) else {
            return nil
        }
        
        // 4. Step 3 (Download & Cache)
        let (imageData, imageResponse) = try await session.data(from: imageURL)
        guard let httpResponse = imageResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        try imageData.write(to: cachedFileURL)
        
        return cachedFileURL
    }
}

/// Example SwiftUI View using the CachedArtistBannerService
struct ArtistBannerView: View {
    let artistName: String
    
    @State private var bannerURL: URL?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if let fileURL = bannerURL, let nsImage = NSImage(contentsOf: fileURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // Fallback placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .task {
            isLoading = true
            do {
                self.bannerURL = try await CachedArtistBannerService.shared.fetchAndCacheArtistBanner(for: artistName)
            } catch {
                print("Failed to fetch artist banner: \(error)")
            }
            isLoading = false
        }
    }
}
