//
//  GetMusic.swift
//  Mesh Player
//
//  "Get Music": search the Apple Music catalog (the same public iTunes Search API am-dl's own
//  look-up uses), then hand the chosen song / album / video to am-dl (https://am-dl.pages.dev)
//  running in an embedded web view. Whatever am-dl saves is caught as a download, unpacked if
//  it is a zip, and imported into the Mesh library automatically.
//

import AppKit
import Combine
import SwiftUI
import WebKit

// MARK: - Catalog search

nonisolated struct CatalogItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case song = "Song", album = "Album", musicVideo = "Music Video" }
    let id: String
    let kind: Kind
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let appleMusicURL: URL
    let year: String?
    let trackCount: Int?
    let isExplicit: Bool
}

nonisolated enum CatalogSearch {
    static func search(_ term: String) async -> [CatalogItem] {
        async let music = fetch(term: term, entity: "song,album", limit: 25)
        async let videos = fetch(term: term, entity: "musicVideo", limit: 10)
        let (a, b) = await (music, videos)
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0.id).inserted }
    }

    private static func fetch(term: String, entity: String, limit: Int) async -> [CatalogItem] {
        let country = (Locale.current.region?.identifier ?? "us").lowercased()
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap(parse)
    }

    private static func parse(_ r: [String: Any]) -> CatalogItem? {
        let wrapper = r["wrapperType"] as? String
        let kindName = r["kind"] as? String
        let art = (r["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "300x300bb")
        let year = (r["releaseDate"] as? String).map { String($0.prefix(4)) }
        let explicit = (r["collectionExplicitness"] as? String ?? r["trackExplicitness"] as? String) == "explicit"
        if wrapper == "collection" {
            guard let id = r["collectionId"] as? Int, let link = (r["collectionViewUrl"] as? String).flatMap(cleanURL) else { return nil }
            return CatalogItem(id: "album-\(id)", kind: .album, title: r["collectionName"] as? String ?? "", artist: r["artistName"] as? String ?? "",
                               album: nil, artworkURL: art.flatMap(URL.init(string:)), appleMusicURL: link, year: year,
                               trackCount: r["trackCount"] as? Int, isExplicit: explicit)
        }
        guard wrapper == "track", let id = r["trackId"] as? Int, let link = (r["trackViewUrl"] as? String).flatMap(cleanURL) else { return nil }
        let kind: CatalogItem.Kind = kindName == "music-video" ? .musicVideo : .song
        return CatalogItem(id: "\(kind.rawValue)-\(id)", kind: kind, title: r["trackName"] as? String ?? "", artist: r["artistName"] as? String ?? "",
                           album: r["collectionName"] as? String, artworkURL: art.flatMap(URL.init(string:)), appleMusicURL: link, year: year,
                           trackCount: nil, isExplicit: explicit)
    }

    /// iTunes links carry tracking parameters (`?uo=4`); song links keep their `?i=` id.
    private static func cleanURL(_ string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        components.queryItems = components.queryItems?.filter { $0.name == "i" }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.url
    }
}

// MARK: - Downloader

final class AmdlDownloader: NSObject, ObservableObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate {
    static let shared = AmdlDownloader()
    static let siteURL = URL(string: "https://am-dl.pages.dev")!

    enum Quality: String, CaseIterable, Identifiable {
        case aac = "off", alac = "alac", atmos = "atmos"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .aac: return "AAC 256"
            case .alac: return "Lossless (ALAC)"
            case .atmos: return "Dolby Atmos"
            }
        }
    }

    struct Job: Identifiable, Equatable {
        enum Phase: Equatable {
            case waiting, preparing, processing(String), downloading(Double), importing, done(String), failed(String)
        }
        let id = UUID()
        let item: CatalogItem
        let quality: Quality
        var phase: Phase = .waiting
        var progress: Double?

        var isFinished: Bool {
            if case .done = phase { return true }
            if case .failed = phase { return true }
            return false
        }
    }

    @Published private(set) var jobs: [Job] = []
    @Published var quality: Quality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "amdl.quality") }
    }
    @Published private(set) var pageReady = false

    private(set) lazy var webView: WKWebView = makeWebView()
    private weak var state: AppStateManager?
    private var activeJobId: UUID?
    private var watchdog: Task<Void, Never>?
    private var downloadsInFlight = 0
    private var finishedFiles: [URL] = []
    private var destinations: [ObjectIdentifier: URL] = [:]

    private override init() {
        quality = Quality(rawValue: UserDefaults.standard.string(forKey: "amdl.quality") ?? "") ?? .aac
        super.init()
    }

    var activeJob: Job? { jobs.first { $0.id == activeJobId } }
    var hasActiveWork: Bool { jobs.contains { !$0.isFinished } }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Keep am-dl's processing running at full speed while its page isn't on screen.
        config.preferences.inactiveSchedulingPolicy = .none
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        view.load(URLRequest(url: Self.siteURL))
        return view
    }

    func prepare() { _ = webView }

    func enqueue(_ item: CatalogItem, state: AppStateManager) {
        self.state = state
        if jobs.contains(where: { $0.item.id == item.id && !$0.isFinished }) { return }
        jobs.insert(Job(item: item, quality: quality), at: 0)
        prepare()
        startNextIfIdle()
    }

    func clearFinished() {
        jobs.removeAll { $0.isFinished }
    }

    func cancel(_ id: UUID) {
        if id == activeJobId {
            finish(id, .failed("Cancelled"))
            webView.load(URLRequest(url: Self.siteURL))
        } else {
            jobs.removeAll { $0.id == id }
        }
    }

    private func update(_ id: UUID, _ phase: Job.Phase, progress: Double? = nil) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].phase = phase
        jobs[idx].progress = progress
    }

    private func startNextIfIdle() {
        guard activeJobId == nil, pageReady,
              let next = jobs.last(where: { $0.phase == .waiting }) else { return }
        activeJobId = next.id
        finishedFiles = []
        downloadsInFlight = 0
        update(next.id, .preparing)
        submit(next)
    }

    /// Fills in am-dl's form the way a person would: pick the quality, paste the link, press Archive.
    private func submit(_ job: Job) {
        let link = job.item.appleMusicURL.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
          const input = document.querySelector('#urlInput');
          const button = document.querySelector('#fetch-button');
          if (!input || !button) return 'missing';
          const mode = document.querySelector('.url-mode-option[data-mode="\(job.quality.rawValue)"]');
          if (mode && !mode.classList.contains('is-active')) mode.click();
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(input, '\(link)');
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          setTimeout(() => button.click(), 350);
          return 'ok';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if (result as? String) != "ok" {
                    self.finish(job.id, .failed("am-dl's page didn't load correctly. Try again in a moment."))
                    return
                }
                self.update(job.id, .processing("Starting…"))
                self.watch(job.id)
            }
        }
    }

    /// Mirrors am-dl's status line and progress bar, confirms its track picker, and gives up after 15 minutes.
    private func watch(_ id: UUID) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            let started = Date()
            var lastStatus = ""
            var unchangedSince = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.activeJobId == id else { return }
                if self.downloadsInFlight > 0 { continue }
                let js = """
                (function() {
                  const status = (document.querySelector('#status') || {}).textContent || '';
                  const bar = document.querySelector('#enhanced-progress-bar');
                  const container = document.querySelector('#enhanced-progress-container');
                  const title = (document.querySelector('#enhanced-progress-title') || {}).textContent || '';
                  const cont = document.querySelector('#selectedTracksContinueButton');
                  if (cont && cont.offsetParent !== null) { cont.click(); }
                  let pct = -1;
                  if (bar && container && !container.classList.contains('hidden')) { pct = parseFloat(bar.style.width) || 0; }
                  return JSON.stringify({ status: status.trim(), pct: pct, title: title.trim() });
                })();
                """
                guard let raw = try? await self.webView.evaluateJavaScript(js) as? String,
                      let data = raw.data(using: .utf8),
                      let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let status = info["status"] as? String ?? ""
                let pct = info["pct"] as? Double ?? -1
                let title = info["title"] as? String ?? ""
                if status != lastStatus { lastStatus = status; unchangedSince = Date() }
                let lower = status.lowercased()
                if lower.contains("error") || lower.contains("failed") || lower.contains("invalid") || lower.contains("not available") {
                    self.finish(id, .failed(status))
                    return
                }
                let text = [title, status].filter { !$0.isEmpty }.joined(separator: " · ")
                self.update(id, .processing(text.isEmpty ? "Processing…" : text), progress: pct >= 0 ? pct / 100 : nil)
                if !self.finishedFiles.isEmpty && Date().timeIntervalSince(unchangedSince) > 4 {
                    // Everything am-dl produced has been saved and the page has gone quiet.
                    self.importFinishedFiles(for: id)
                    return
                }
                if Date().timeIntervalSince(started) > 15 * 60 {
                    self.finish(id, .failed(status.isEmpty ? "Timed out" : status))
                    return
                }
            }
        }
    }

    private func finish(_ id: UUID, _ phase: Job.Phase) {
        update(id, phase)
        if activeJobId == id {
            watchdog?.cancel()
            activeJobId = nil
            // Reset the page so the next job starts from a clean form.
            webView.load(URLRequest(url: Self.siteURL))
        }
    }

    // MARK: Import

    private static var stagingFolder: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mesh Player/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func importFinishedFiles(for id: UUID) {
        guard let state else { return }
        let files = finishedFiles
        finishedFiles = []
        update(id, .importing)
        Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) { Self.unpack(files) }.value
            guard let self else { return }
            if prepared.audio.isEmpty {
                self.finish(id, .failed("am-dl didn't produce any audio files."))
                return
            }
            let result = await LibraryImporter.shared.importDownloads(prepared.audio, into: state)
            if let video = prepared.animatedArtwork, let first = result.first?.fileURL {
                let destination = first.deletingLastPathComponent().appendingPathComponent("animated_artwork." + video.pathExtension)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.moveItem(at: video, to: destination)
                }
            }
            for file in files { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            self.finish(id, result.isEmpty ? .failed("Nothing could be imported.") : .done("Added \(Fmt.songs(result.count))"))
            self.startNextIfIdle()
        }
    }

    /// Expands zips and separates songs from square motion artwork.
    nonisolated private static func unpack(_ files: [URL]) -> (audio: [URL], animatedArtwork: URL?) {
        var candidates: [URL] = []
        for file in files {
            if file.pathExtension.lowercased() == "zip" {
                let folder = file.deletingPathExtension()
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-x", "-k", file.path, folder.path]
                try? process.run()
                process.waitUntilExit()
                candidates.append(contentsOf: LibraryFiles.collectAudioFiles(in: folder, includeArtworkVideos: true))
            } else {
                candidates.append(file)
            }
        }
        var audio: [URL] = []
        var artwork: URL?
        for url in candidates {
            if LibraryFiles.isArtworkVideo(url) {
                if !url.lastPathComponent.lowercased().contains("tall") { artwork = artwork ?? url }
            } else if MeshPaths.isAudioFile(url) {
                audio.append(url)
            }
        }
        return (audio, artwork)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        startNextIfIdle()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.shouldPerformDownload { return (.download, preferences) }
        // Links that leave am-dl (Discord, docs…) open in the real browser.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
           url.host != Self.siteURL.host, url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if !navigationResponse.canShowMIMEType || disposition.lowercased().contains("attachment") { return .download }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        downloadsInFlight += 1
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        downloadsInFlight += 1
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.host != Self.siteURL.host { NSWorkspace.shared.open(url) }
        return nil
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = Self.stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        if let id = activeJobId { update(id, .downloading(0)) }
        let destination = folder.appendingPathComponent(name)
        destinations[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        downloadsInFlight = max(0, downloadsInFlight - 1)
        if let url = destinations.removeValue(forKey: ObjectIdentifier(download)) {
            finishedFiles.append(url)
        }
        if activeJobId == nil, !finishedFiles.isEmpty {
            // A download started by hand in the am-dl panel: import it too.
            let manual = Job(item: CatalogItem(id: UUID().uuidString, kind: .song, title: finishedFiles.first?.deletingPathExtension().lastPathComponent ?? "Download", artist: "am-dl", album: nil, artworkURL: nil, appleMusicURL: Self.siteURL, year: nil, trackCount: nil, isExplicit: false), quality: quality, phase: .processing("Saved"))
            jobs.insert(manual, at: 0)
            activeJobId = manual.id
            watch(manual.id)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadsInFlight = max(0, downloadsInFlight - 1)
        destinations[ObjectIdentifier(download)] = nil
        if let id = activeJobId, finishedFiles.isEmpty { finish(id, .failed(error.localizedDescription)) }
    }
}

// MARK: - Views

/// Hosts the shared am-dl web view wherever it is shown.
struct AmdlWebPanel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if AmdlDownloader.shared.webView.superview !== nsView { attach(to: nsView) }
    }

    private func attach(to container: NSView) {
        let web = AmdlDownloader.shared.webView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

struct GetMusicView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject private var downloader = AmdlDownloader.shared

    @State private var query = ""
    @State private var results: [CatalogItem] = []
    @State private var isSearching = false
    @State private var filter: CatalogItem.Kind? = nil
    @State private var showSite = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let theme = state.theme
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Get Music", subtitle: "Search Apple Music, download with am-dl, and it lands in your library automatically.", theme: theme) {
                    Picker("Quality", selection: $downloader.quality) {
                        ForEach(AmdlDownloader.Quality.allCases) { Text($0.label).tag($0) }
                    }
                    .fixedSize()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showSite.toggle() }
                    } label: {
                        Label(showSite ? "Hide am-dl" : "Show am-dl", systemImage: "safari")
                    }
                    .buttonStyle(PillButtonStyle(kind: .ghost, theme: theme, compact: true))
                }

                searchField(theme)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)

                if !results.isEmpty {
                    Picker("", selection: $filter) {
                        Text("All").tag(CatalogItem.Kind?.none)
                        Text("Songs").tag(CatalogItem.Kind?.some(.song))
                        Text("Albums").tag(CatalogItem.Kind?.some(.album))
                        Text("Videos").tag(CatalogItem.Kind?.some(.musicVideo))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !downloader.jobs.isEmpty { downloadsSection(theme) }
                        resultsSection(theme)
                    }
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity)

            if showSite {
                Rectangle().fill(theme.hairline).frame(width: 1)
                VStack(spacing: 0) {
                    HStack {
                        Label("am-dl.pages.dev", systemImage: "lock.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button {
                            AmdlDownloader.shared.webView.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(IconButtonStyle(theme: theme, size: 24))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    AmdlWebPanel()
                }
                .frame(width: 440)
                .transition(.move(edge: .trailing))
            }
        }
        .background(theme.background)
        .onAppear {
            downloader.prepare()
            takePresetQuery()
        }
        .onChange(of: state.getMusicQuery) { _, _ in takePresetQuery() }
    }

    private func searchField(_ theme: ThemeColor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.textTertiary)
            TextField("Songs, albums, artists or an Apple Music link", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit(runSearch)
                .onChange(of: query) { _, _ in scheduleSearch() }
            if isSearching { ProgressView().controlSize(.small) }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    private var linkItem: CatalogItem? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("https://music.apple.com/"), let url = URL(string: trimmed) else { return nil }
        let kind: CatalogItem.Kind = trimmed.contains("/music-video/") ? .musicVideo : (trimmed.contains("?i=") || trimmed.contains("/song/") ? .song : .album)
        return CatalogItem(id: "link-\(trimmed)", kind: kind, title: url.pathComponents.dropLast().last?.replacingOccurrences(of: "-", with: " ").capitalized ?? "Apple Music link",
                           artist: "Apple Music link", album: nil, artworkURL: nil, appleMusicURL: url, year: nil, trackCount: nil, isExplicit: false)
    }

    /// Other pages (e.g. Essential Albums on an artist page) open Get Music with a search ready.
    private func takePresetQuery() {
        guard let preset = state.getMusicQuery else { return }
        state.getMusicQuery = nil
        query = preset
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard linkItem == nil else { results = []; return }
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await CatalogSearch.search(term)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private func runSearch() {
        if let link = linkItem {
            downloader.enqueue(link, state: state)
        } else {
            scheduleSearch()
        }
    }

    @ViewBuilder
    private func resultsSection(_ theme: ThemeColor) -> some View {
        if let link = linkItem {
            CatalogRow(item: link, theme: theme, inLibrary: false, job: job(for: link)) { downloader.enqueue(link, state: state) }
                .padding(.horizontal, 20)
        } else if results.isEmpty {
            if !isSearching && downloader.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                    Text(query.count >= 2 ? "No results" : "Find something to add")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text("Search the Apple Music catalog or paste a music.apple.com link. Downloads use the quality picked above.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            }
        } else {
            let shown = results.filter { filter == nil || $0.kind == filter }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shown) { item in
                    CatalogRow(item: item, theme: theme, inLibrary: isInLibrary(item), job: job(for: item)) {
                        downloader.enqueue(item, state: state)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func downloadsSection(_ theme: ThemeColor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if downloader.jobs.contains(where: \.isFinished) {
                    Button("Clear Finished") { downloader.clearFinished() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            ForEach(downloader.jobs) { job in
                DownloadJobRow(job: job, theme: theme) { downloader.cancel(job.id) }
            }
        }
        .padding(.horizontal, 28)
    }

    private func job(for item: CatalogItem) -> AmdlDownloader.Job? {
        downloader.jobs.first { $0.item.id == item.id }
    }

    private func isInLibrary(_ item: CatalogItem) -> Bool {
        state.hasCatalogItem(item)
    }
}

extension AppStateManager {
    /// Whether a catalog result already seems to be in the library.
    func hasCatalogItem(_ item: CatalogItem) -> Bool {
        let leadArtist = item.artist.components(separatedBy: " & ").first ?? item.artist
        switch item.kind {
        case .album:
            let name = AnimatedArtworkService.normalize(item.title)
            return albumsList.contains { AnimatedArtworkService.normalize($0.name).caseInsensitiveCompare(name) == .orderedSame && $0.artist.localizedCaseInsensitiveContains(leadArtist) }
        default:
            return tracks.contains { $0.title.caseInsensitiveCompare(item.title) == .orderedSame && $0.artist.localizedCaseInsensitiveContains(leadArtist) }
        }
    }
}

struct CatalogRow: View {
    let item: CatalogItem
    let theme: ThemeColor
    let inLibrary: Bool
    let job: AmdlDownloader.Job?
    let onDownload: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkPlaceholder(seed: item.title, symbol: item.kind == .musicVideo ? "play.rectangle.fill" : "music.note")
            }
            .frame(width: item.kind == .musicVideo ? 76 : 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if item.isExplicit {
                        Image(systemName: "e.square.fill").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if inLibrary && job == nil {
                Label("In Library", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            if let job {
                JobBadge(job: job, theme: theme)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 28, height: 28)
                        .background(theme.accent, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .help("Download with am-dl and add to Mesh Player")
            }
        }
        .padding(8)
        .background(hovering ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if job == nil { onDownload() } }
    }

    private var subtitle: String {
        var parts = [item.kind.rawValue, item.artist]
        if let album = item.album, item.kind == .song { parts.append(album) }
        if let count = item.trackCount, item.kind == .album { parts.append(Fmt.songs(count)) }
        if let year = item.year { parts.append(year) }
        return parts.joined(separator: " · ")
    }
}

struct JobBadge: View {
    let job: AmdlDownloader.Job
    let theme: ThemeColor

    var body: some View {
        switch job.phase {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .waiting:
            Image(systemName: "clock").foregroundStyle(theme.textTertiary)
        default:
            if let p = job.progress {
                ProgressView(value: p).progressViewStyle(.circular).controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct DownloadJobRow: View {
    let job: AmdlDownloader.Job
    let theme: ThemeColor
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: job.item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkPlaceholder(seed: job.item.title, symbol: "arrow.down")
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(job.item.title) — \(job.item.artist)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(isFailed ? Color.orange : theme.textSecondary)
                    .lineLimit(1)
                if let p = job.progress, !job.isFinished {
                    ProgressView(value: p).progressViewStyle(.linear).tint(theme.accent)
                }
            }
            Spacer()
            if !job.isFinished {
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(IconButtonStyle(theme: theme, size: 22))
                .help("Cancel")
            } else {
                JobBadge(job: job, theme: theme)
            }
        }
        .padding(10)
        .card(theme, radius: 10)
    }

    private var isFailed: Bool {
        if case .failed = job.phase { return true }
        return false
    }

    private var statusText: String {
        switch job.phase {
        case .waiting: return "Waiting · \(job.quality.label)"
        case .preparing: return "Opening am-dl…"
        case .processing(let text): return text
        case .downloading: return "Saving…"
        case .importing: return "Adding to your library…"
        case .done(let text): return text
        case .failed(let text): return text
        }
    }
}

/// Small sidebar card shown while am-dl downloads are running.
struct DownloadStatusCard: View {
    @ObservedObject private var downloader = AmdlDownloader.shared
    let theme: ThemeColor

    var body: some View {
        if let job = downloader.jobs.first(where: { !$0.isFinished }) {
            let remaining = downloader.jobs.filter { !$0.isFinished }.count
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(remaining > 1 ? "Downloading \(remaining) items" : "Downloading")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(job.item.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .card(theme, radius: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
