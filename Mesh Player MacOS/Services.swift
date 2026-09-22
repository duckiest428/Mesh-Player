import AppKit
import AuthenticationServices
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

// MARK: - DownloaderManager.swift
class DownloaderManager: ObservableObject {
    static let shared = DownloaderManager()
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var logs: String = ""
    
    private init() {}
    
    func downloadAudio(from urlString: String, destinationFolder: URL, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        
        isDownloading = true
        downloadProgress = 0.0
        logs = "Starting download from \(urlString)...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            
            // Assume am-dl is in /usr/local/bin or accessible via PATH
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/am-dl")
            process.arguments = [urlString, "--output", destinationFolder.path]
            process.standardOutput = pipe
            process.standardError = pipe
            
            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.logs += output
                        // Basic progress parsing (assuming am-dl outputs e.g. "[download] 45.3%")
                        if let range = output.range(of: "\\[download\\]\\s+([0-9.]+)", options: .regularExpression),
                           let percentageStr = output[range].components(separatedBy: .whitespaces).last,
                           let percentage = Double(percentageStr) {
                            self.downloadProgress = percentage / 100.0
                        }
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.downloadProgress = 1.0
                    self.logs += "Download finished with code \(process.terminationStatus)\n"
                    completion(process.terminationStatus == 0)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.logs += "Failed to start process: \(error.localizedDescription)\n"
                    completion(false)
                }
            }
        }
    }
}

// MARK: - LastFmAuthService.swift
/// A clean Swift service for handling Last.fm authentication via their official API.
final class LastFmAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    
    private let apiKey: String
    private let apiSecret: String
    private let redirectUri = "myapp://lastfm-auth"
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"
    
    init(apiKey: String, apiSecret: String) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }
    
    // MARK: - Core Flow
    
    /// Step 1: Fetch request token from Last.fm
    func fetchRequestToken() async throws -> String {
        let params = [
            "method": "auth.gettoken",
            "api_key": apiKey,
            "format": "json"
        ]
        
        let signedParams = sign(params: params)
        let request = try buildPostRequest(parameters: signedParams)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        return token
    }
    
    /// Step 2: Formulate the correct browser authentication web URL
    func buildAuthUrl(token: String) -> URL {
        // Last.fm documentation specifies the user auth URL format:
        // http://www.last.fm/api/auth/?api_key=[API_KEY]&token=[TOKEN]
        return URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")!
    }
    
    /// Step 3: Exchange authorized token for infinite session key
    func exchangeTokenForSession(token: String) async throws -> (username: String, sessionKey: String) {
        let params = [
            "method": "auth.getsession",
            "api_key": apiKey,
            "token": token,
            "format": "json"
        ]
        
        let signedParams = sign(params: params)
        let request = try buildPostRequest(parameters: signedParams)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionDict = json["session"] as? [String: Any],
              let sessionKey = sessionDict["key"] as? String,
              let username = sessionDict["name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        // Save to Keychain
        saveToKeychain(account: "lastfm_username", value: username)
        saveToKeychain(account: "lastfm_session", value: sessionKey)
        
        return (username, sessionKey)
    }
    
    // MARK: - Cryptographic Signature
    
    /// Implements the cryptographic API Signature (`api_sig`) constraint.
    private func sign(params: [String: String]) -> [String: String] {
        // Sort parameters alphabetically by keys
        let sortedKeys = params.keys.sorted()
        
        // Concatenate keys and values without delimiters (ignoring 'format' or 'callback' per Last.fm specs)
        var concatenated = ""
        for key in sortedKeys {
            if key != "format" && key != "callback" {
                concatenated += "\(key)\(params[key]!)"
            }
        }
        
        // Append raw Secret Key
        concatenated += apiSecret
        
        // Generate MD5 hash as 32-character hex string
        let digest = Insecure.MD5.hash(data: Data(concatenated.utf8))
        let apiSig = digest.map { String(format: "%02hhx", $0) }.joined()
        
        var signedParams = params
        signedParams["api_sig"] = apiSig
        return signedParams
    }
    
    // MARK: - Networking Utilities
    
    private func buildPostRequest(parameters: [String: String]) throws -> URLRequest {
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = parameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        return request
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
    
    // MARK: - Keychain Persistence
    
    private func saveToKeychain(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func clearKeychain() {
        let queryUser: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "lastfm_username"]
        let querySession: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "lastfm_session"]
        SecItemDelete(queryUser as CFDictionary)
        SecItemDelete(querySession as CFDictionary)
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Companion SwiftUI Settings View Snippet

struct LastFmSettingsView: View {
    // Inject the service with your API keys
    private let authService = LastFmAuthService(apiKey: "YOUR_API_KEY", apiSecret: "YOUR_API_SECRET")
    
    @State private var connectedUsername: String? = nil
    @State private var isConnecting = false
    @State private var authSession: ASWebAuthenticationSession?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Last.fm Integration")
                .font(.headline)
            
            if let username = connectedUsername {
                HStack {
                    Text("Connected as \(username)")
                        .foregroundColor(.green)
                    Spacer()
                    Button("Disconnect") {
                        authService.clearKeychain()
                        connectedUsername = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button(action: connectLastFm) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                            .padding(.horizontal, 4)
                    } else {
                        Text("Connect Last.fm")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)
            }
        }
        .padding()
        .onAppear {
            self.connectedUsername = authService.loadFromKeychain(account: "lastfm_username")
        }
    }
    
    private func connectLastFm() {
        isConnecting = true
        
        Task {
            do {
                let token = try await authService.fetchRequestToken()
                let authUrl = authService.buildAuthUrl(token: token)
                
                await MainActor.run {
                    self.authSession = ASWebAuthenticationSession(
                        url: authUrl,
                        callbackURLScheme: "myapp"
                    ) { callbackURL, error in
                        Task {
                            defer { self.isConnecting = false }
                            if let error = error {
                                print("Auth error: \(error)")
                                return
                            }
                            
                            guard let callbackURL = callbackURL else { return }
                            // Token is typically returned or we just use the original token requested.
                            // The Last.fm protocol doesn't always return the token in the URL params if they authorized the original token.
                            // We can just use the token we already have to get the session.
                            do {
                                let (username, _) = try await authService.exchangeTokenForSession(token: token)
                                await MainActor.run {
                                    self.connectedUsername = username
                                }
                            } catch {
                                print("Session exchange failed: \(error)")
                            }
                        }
                    }
                    
                    self.authSession?.presentationContextProvider = authService
                    self.authSession?.start()
                }
            } catch {
                print("Failed to start Last.fm auth: \(error)")
                await MainActor.run { isConnecting = false }
            }
        }
    }
}

