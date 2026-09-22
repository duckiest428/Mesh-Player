import MusicKit
import Foundation
import SwiftUI
import Combine

// MARK: - MeshReplay.swift
// MARK: - Data Models & Analytics Schema

struct ReplayStats: Codable {
    let year: Int
    let totalListeningTimeSeconds: TimeInterval
    let topTracks: [TrackPlayHistory]
    let topArtists: [ArtistMilestone]
    let topAlbums: [String: Int] // Album Name : Play Count
    let topGenres: [String: Int] // Genre Name : Play Count
    let monthlyTrends: [MonthlyTrend]
}

struct TrackPlayHistory: Codable, Identifiable {
    var id: String { "\(trackId.uuidString)_\(title)" }
    let trackId: UUID // Reference to LocalTrack
    let title: String
    let artist: String
    let playCount: Int
    let totalListenDuration: TimeInterval
}

struct ArtistMilestone: Codable, Identifiable {
    var id: String { name }
    let name: String
    let playCount: Int
    let badge: ReplayBadge?
}

struct MonthlyTrend: Codable, Identifiable {
    var id: Int { month }
    let month: Int // 1-12
    let topArtist: String
    let topTrack: String
    let listeningMinutes: Int
}

enum ReplayBadge: String, Codable {
    case topOnePercent = "Top 1% Listener"
    case marathon = "5,000 Minutes Streamed"
    case deepCut = "Deep Cut Collector"
    case loyalty = "Loyalty"
    case discovery = "Discovery"
    case comeback = "Comeback"
    case heavyRotation = "Heavy Rotation"
}

enum ReplaySection: String, CaseIterable, Identifiable {
    case yearly = "Yearly"
    case monthly = "Monthly"
    case weekly = "Weekly"
    
    var id: String { rawValue }
}

// MARK: - Replay Time Window Utility
struct ReplayTimeWindow: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let interval: DateInterval
    let isConcluded: Bool
    
    static func previousWeek(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
            let start = referenceDate.addingTimeInterval(-14 * 86400)
            let end = referenceDate.addingTimeInterval(-7 * 86400)
            return DateInterval(start: start, end: end)
        }
        let end = currentWeekInterval.start
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-7 * 86400)
        return DateInterval(start: start, end: end)
    }
    
    static func currentWeek(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
            let start = referenceDate.addingTimeInterval(-7 * 86400)
            return DateInterval(start: start, end: referenceDate)
        }
        return DateInterval(start: currentWeekInterval.start, end: referenceDate)
    }
    
    static func previousMonth(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard let currentMonthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
            let start = referenceDate.addingTimeInterval(-60 * 86400)
            let end = referenceDate.addingTimeInterval(-30 * 86400)
            return DateInterval(start: start, end: end)
        }
        let end = currentMonthInterval.start
        let start = calendar.date(byAdding: .month, value: -1, to: end) ?? end.addingTimeInterval(-30 * 86400)
        return DateInterval(start: start, end: end)
    }
    
    static func currentMonth(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard let currentMonthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
            let start = referenceDate.addingTimeInterval(-30 * 86400)
            return DateInterval(start: start, end: referenceDate)
        }
        return DateInterval(start: currentMonthInterval.start, end: referenceDate)
    }
    
    static func previousYear(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard let currentYearInterval = calendar.dateInterval(of: .year, for: referenceDate) else {
            let start = referenceDate.addingTimeInterval(-730 * 86400)
            let end = referenceDate.addingTimeInterval(-365 * 86400)
            return DateInterval(start: start, end: end)
        }
        let end = currentYearInterval.start
        let start = calendar.date(byAdding: .year, value: -1, to: end) ?? end.addingTimeInterval(-365 * 86400)
        return DateInterval(start: start, end: end)
    }
    
    static func currentYear(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard let currentYearInterval = calendar.dateInterval(of: .year, for: referenceDate) else {
            let start = referenceDate.addingTimeInterval(-365 * 86400)
            return DateInterval(start: start, end: referenceDate)
        }
        return DateInterval(start: currentYearInterval.start, end: referenceDate)
    }
}

// MARK: - MeshReplayViewModel
@MainActor
final class MeshReplayViewModel: ObservableObject {
    @Published var selectedSection: ReplaySection = .yearly {
        didSet {
            updateCurrentStats()
        }
    }
    
    @Published var currentSectionStats: ReplayStats
    @Published var isHighlightReelPresented: Bool = false
    @Published var isExportCardPresented: Bool = false
    
    @Published var yearlyStats: ReplayStats
    @Published var monthlyStats: ReplayStats
    @Published var weeklyStats: ReplayStats
    
    private let appState: AppStateManager
    private let baseStats: ReplayStats
    
    // MARK: - Timegate Availability Checks
    var previousMonthName: String {
        let calendar = Calendar.current
        let prevInterval = ReplayTimeWindow.previousMonth()
        let m = calendar.component(.month, from: prevInterval.start)
        return calendar.monthSymbols[m - 1]
    }
    
    var isYearlyAvailable: Bool {
        if UserDefaults.standard.bool(forKey: "dev_bypass_replay_timegate") { return true }
        let currentMonth = Calendar.current.component(.month, from: Date())
        return currentMonth == 12 || yearlyStats.totalListeningTimeSeconds > 0
    }
    
    var isMonthlyAvailable: Bool {
        if UserDefaults.standard.bool(forKey: "dev_bypass_replay_timegate") { return true }
        return monthlyStats.totalListeningTimeSeconds > 0
    }
    
    var isWeeklyAvailable: Bool {
        if UserDefaults.standard.bool(forKey: "dev_bypass_replay_timegate") { return true }
        return weeklyStats.totalListeningTimeSeconds > 0
    }
    
    func isSectionAvailable(_ section: ReplaySection) -> Bool {
        switch section {
        case .yearly: return isYearlyAvailable
        case .monthly: return isMonthlyAvailable
        case .weekly: return isWeeklyAvailable
        }
    }
    
    init(state: AppStateManager, stats: ReplayStats) {
        self.appState = state
        self.baseStats = stats
        
        let calculatedYearly = Self.computeYearlyStats(from: state, base: stats)
        let calculatedMonthly = Self.computeMonthlyStats(from: state, base: stats)
        let calculatedWeekly = Self.computeWeeklyStats(from: state, base: stats)
        
        self.yearlyStats = calculatedYearly
        self.monthlyStats = calculatedMonthly
        self.weeklyStats = calculatedWeekly
        
        let devBypass = UserDefaults.standard.bool(forKey: "dev_bypass_replay_timegate")
        let currentMonth = Calendar.current.component(.month, from: Date())
        let isYearlyAvail = devBypass || currentMonth == 12 || calculatedYearly.totalListeningTimeSeconds > 0
        let isMonthlyAvail = devBypass || calculatedMonthly.totalListeningTimeSeconds > 0
        let isWeeklyAvail = devBypass || calculatedWeekly.totalListeningTimeSeconds > 0
        
        let initialSection: ReplaySection
        if isMonthlyAvail {
            initialSection = .monthly
        } else if isWeeklyAvail {
            initialSection = .weekly
        } else if isYearlyAvail {
            initialSection = .yearly
        } else {
            initialSection = .monthly
        }
        
        self.selectedSection = initialSection
        switch initialSection {
        case .yearly: self.currentSectionStats = calculatedYearly
        case .monthly: self.currentSectionStats = calculatedMonthly
        case .weekly: self.currentSectionStats = calculatedWeekly
        }
    }
    
    func refreshStats() {
        self.yearlyStats = Self.computeYearlyStats(from: appState, base: baseStats)
        self.monthlyStats = Self.computeMonthlyStats(from: appState, base: baseStats)
        self.weeklyStats = Self.computeWeeklyStats(from: appState, base: baseStats)
        updateCurrentStats()
    }
    
    private func updateCurrentStats() {
        switch selectedSection {
        case .yearly:
            currentSectionStats = yearlyStats
        case .monthly:
            currentSectionStats = monthlyStats
        case .weekly:
            currentSectionStats = weeklyStats
        }
    }
    
    // MARK: - Continuous Log Dynamic Time-Window Analytics Engine
    static func computeStats(for interval: DateInterval, from state: AppStateManager, base: ReplayStats) -> ReplayStats {
        let devBypass = UserDefaults.standard.bool(forKey: "dev_bypass_replay_timegate")
        let calendar = Calendar.current
        let year = calendar.component(.year, from: interval.start)
        
        if state.playHistoryLog.isEmpty && state.tracks.contains(where: { $0.playCount > 0 }) {
            state.seedPlayHistoryLogIfNeeded()
        }
        
        let entries = state.playHistoryLog.filter { entry in
            entry.timestamp >= interval.start && entry.timestamp <= interval.end
        }
        
        if entries.isEmpty {
            if !devBypass {
                return ReplayStats(
                    year: year,
                    totalListeningTimeSeconds: 0,
                    topTracks: [],
                    topArtists: [],
                    topAlbums: [:],
                    topGenres: [:],
                    monthlyTrends: []
                )
            } else {
                let activeTracks = state.tracks.filter { $0.playCount > 0 }.sorted(by: { $0.playCount > $1.playCount })
                let topTracks = activeTracks.prefix(5).map {
                    TrackPlayHistory(trackId: $0.id, title: $0.title, artist: $0.artist, playCount: $0.playCount, totalListenDuration: $0.duration * Double($0.playCount))
                }
                let artistGroup = Dictionary(grouping: activeTracks, by: { $0.artist })
                let topArtists = artistGroup.mapValues { $0.map { $0.playCount }.reduce(0, +) }
                    .map { ArtistMilestone(name: $0.key, playCount: $0.value, badge: .heavyRotation) }
                    .sorted(by: { $0.playCount > $1.playCount })
                let totalTime = activeTracks.reduce(0.0) { $0 + ($1.duration * Double($1.playCount)) }
                
                return ReplayStats(
                    year: year,
                    totalListeningTimeSeconds: totalTime > 0 ? totalTime : 3600,
                    topTracks: topTracks,
                    topArtists: Array(topArtists.prefix(5)),
                    topAlbums: base.topAlbums,
                    topGenres: base.topGenres,
                    monthlyTrends: computeMonthlyTrends(from: state)
                )
            }
        }
        
        let totalListeningTimeSeconds = entries.reduce(0.0) { $0 + $1.duration }
        
        var trackMap: [UUID: (title: String, artist: String, count: Int, duration: TimeInterval)] = [:]
        for entry in entries {
            let existing = trackMap[entry.trackId] ?? (title: entry.title, artist: entry.artist, count: 0, duration: 0.0)
            trackMap[entry.trackId] = (title: entry.title, artist: entry.artist, count: existing.count + 1, duration: existing.duration + entry.duration)
        }
        let topTracks = trackMap.map { (id, val) in
            TrackPlayHistory(trackId: id, title: val.title, artist: val.artist, playCount: val.count, totalListenDuration: val.duration)
        }.sorted(by: { $0.playCount > $1.playCount })
        
        var artistMap: [String: Int] = [:]
        for entry in entries {
            artistMap[entry.artist, default: 0] += 1
        }
        let topArtists = artistMap.map { (name, count) in
            ArtistMilestone(name: name, playCount: count, badge: count >= 10 ? .heavyRotation : nil)
        }.sorted(by: { $0.playCount > $1.playCount })
        
        var albumMap: [String: Int] = [:]
        var genreMap: [String: Int] = [:]
        for entry in entries {
            if !entry.album.isEmpty { albumMap[entry.album, default: 0] += 1 }
            if !entry.genre.isEmpty { genreMap[entry.genre, default: 0] += 1 }
        }
        
        let monthlyTrends = computeMonthlyTrendsFromLog(entries: entries)
        
        return ReplayStats(
            year: year,
            totalListeningTimeSeconds: totalListeningTimeSeconds,
            topTracks: Array(topTracks.prefix(10)),
            topArtists: Array(topArtists.prefix(10)),
            topAlbums: albumMap,
            topGenres: genreMap,
            monthlyTrends: monthlyTrends
        )
    }
    
    static func computeMonthlyTrendsFromLog(entries: [PlayLogEntry]) -> [MonthlyTrend] {
        guard !entries.isEmpty else { return [] }
        let calendar = Calendar.current
        var monthlyMap: [Int: [PlayLogEntry]] = [:]
        for entry in entries {
            let m = calendar.component(.month, from: entry.timestamp)
            monthlyMap[m, default: []].append(entry)
        }
        var trends: [MonthlyTrend] = []
        for monthNum in 1...12 {
            guard let monthEntries = monthlyMap[monthNum], !monthEntries.isEmpty else { continue }
            let totalSeconds = monthEntries.reduce(0.0) { $0 + $1.duration }
            let totalMins = Int(totalSeconds / 60.0)
            
            var trackCounts: [String: Int] = [:]
            var artistCounts: [String: Int] = [:]
            for e in monthEntries {
                trackCounts[e.title, default: 0] += 1
                artistCounts[e.artist, default: 0] += 1
            }
            let topTrackName = trackCounts.sorted(by: { $0.value > $1.value }).first?.key ?? "Top Track"
            let topArtistName = artistCounts.sorted(by: { $0.value > $1.value }).first?.key ?? "Top Artist"
            
            trends.append(MonthlyTrend(
                month: monthNum,
                topArtist: topArtistName,
                topTrack: topTrackName,
                listeningMinutes: max(1, totalMins)
            ))
        }
        return trends
    }
    
    static func computeMonthlyTrends(from state: AppStateManager) -> [MonthlyTrend] {
        if !state.playHistoryLog.isEmpty {
            return computeMonthlyTrendsFromLog(entries: state.playHistoryLog)
        }
        let activeTracks = state.tracks.filter { $0.playCount > 0 }
        if activeTracks.isEmpty { return [] }
        
        var monthlyMap: [Int: [LocalTrack]] = [:]
        let calendar = Calendar.current
        
        for track in activeTracks {
            let month: Int
            if let lastPlayed = track.lastPlayedDate {
                month = calendar.component(.month, from: lastPlayed)
            } else {
                month = calendar.component(.month, from: track.dateAdded)
            }
            monthlyMap[month, default: []].append(track)
        }
        
        var trends: [MonthlyTrend] = []
        for monthNum in 1...12 {
            guard let tracksInMonth = monthlyMap[monthNum], !tracksInMonth.isEmpty else { continue }
            let totalSeconds = tracksInMonth.reduce(0.0) { $0 + ($1.duration * Double($1.playCount)) }
            let totalMins = Int(totalSeconds / 60.0)
            let sortedByPlays = tracksInMonth.sorted(by: { $0.playCount > $1.playCount })
            let topTrack = sortedByPlays.first
            let artistGroup = Dictionary(grouping: tracksInMonth, by: { $0.artist })
            let topArtistName = artistGroup.mapValues { $0.map { $0.playCount }.reduce(0, +) }
                .sorted(by: { $0.value > $1.value }).first?.key ?? (topTrack?.artist ?? "Top Artist")
            
            if totalMins > 0 || (topTrack?.playCount ?? 0) > 0 {
                trends.append(MonthlyTrend(
                    month: monthNum,
                    topArtist: topArtistName,
                    topTrack: topTrack?.title ?? "Unknown Track",
                    listeningMinutes: max(1, totalMins)
                ))
            }
        }
        return trends
    }
    
    static func computeYearlyStats(from state: AppStateManager, base: ReplayStats) -> ReplayStats {
        let interval = ReplayTimeWindow.previousYear()
        return computeStats(for: interval, from: state, base: base)
    }
    
    static func computeMonthlyStats(from state: AppStateManager, base: ReplayStats) -> ReplayStats {
        let interval = ReplayTimeWindow.previousMonth()
        return computeStats(for: interval, from: state, base: base)
    }
    
    static func computeWeeklyStats(from state: AppStateManager, base: ReplayStats) -> ReplayStats {
        let interval = ReplayTimeWindow.previousWeek()
        return computeStats(for: interval, from: state, base: base)
    }
}

// MARK: - Social Export Card Component
struct ReplayShareCardView: View {
    let stats: ReplayStats
    let theme: ThemeColor
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.accent.opacity(0.85), theme.background]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Mesh")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Replay \(String(stats.year))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if let topArtist = stats.topArtists.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TOP ARTIST")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Text(topArtist.name)
                            .font(.system(size: 42, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("TOP TRACKS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(stats.topTracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 20)
                                
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("MINUTES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(Int(stats.totalListeningTimeSeconds / 60))")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    if let topGenre = stats.topGenres.sorted(by: { $0.value > $1.value }).first {
                        VStack(alignment: .trailing) {
                            Text("TOP GENRE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            Text(topGenre.key)
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(32)
        }
        .frame(width: 360, height: 640)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

// MARK: - MeshReplayView.swift
struct MeshReplayView: View {
    @ObservedObject var state: AppStateManager
    let stats: ReplayStats
    
    @StateObject private var viewModel: MeshReplayViewModel
    
    init(state: AppStateManager, stats: ReplayStats) {
        self.state = state
        self.stats = stats
        _viewModel = StateObject(wrappedValue: MeshReplayViewModel(state: state, stats: stats))
    }
    
    let chartColumns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                
                // Section Picker (Yearly, Monthly, Weekly)
                HStack {
                    Spacer()
                    Picker("Replay View", selection: $viewModel.selectedSection) {
                        ForEach(ReplaySection.allCases) { section in
                            Text(section.rawValue + (viewModel.isSectionAvailable(section) ? "" : " 🔒"))
                                .tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                    .onChange(of: viewModel.selectedSection) { _ in
                        viewModel.refreshStats()
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.horizontal, 32)
                
                if !viewModel.isSectionAvailable(viewModel.selectedSection) {
                    VStack(spacing: 20) {
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(state.theme.accent)
                            .shadow(color: state.theme.accent.opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        Text(lockedTitle(for: viewModel.selectedSection))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(state.theme.textPrimary)
                        
                        Text(lockReasonText(for: viewModel.selectedSection))
                            .font(.body)
                            .foregroundColor(state.theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape")
                            Text("Tip: Disable Replay Time-Gating in Preferences under Developer Settings.")
                        }
                        .font(.caption)
                        .foregroundColor(state.theme.textSecondary.opacity(0.8))
                        .padding(.top, 8)
                    }
                    .padding(48)
                    .frame(maxWidth: .infinity)
                    .background(state.theme.cardBackground)
                    .cornerRadius(20)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                } else {
                    // MARK: - 1. Immersive Hero Header Banner
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                state.theme.accent.opacity(0.85),
                                state.theme.accent.opacity(0.4),
                                Color.indigo.opacity(0.6),
                                state.theme.background
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        Circle()
                            .fill(state.theme.accent)
                            .frame(width: 320, height: 320)
                            .blur(radius: 80)
                            .offset(x: -100, y: -50)
                            .opacity(0.6)
                        
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 250, height: 250)
                            .blur(radius: 70)
                            .offset(x: 200, y: 30)
                            .opacity(0.5)
                    }
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text(heroTitle(for: viewModel.selectedSection))
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text("\(Int(viewModel.currentSectionStats.totalListeningTimeSeconds / 60)) Minutes of Music • \(viewModel.currentSectionStats.topTracks.count) Top Tracks")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        
                        HStack(spacing: 14) {
                            Button(action: { viewModel.isHighlightReelPresented = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Watch Highlight Reel")
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(state.theme.accent)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: state.theme.accent.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.isExportCardPresented = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.18))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(32)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                
                // MARK: - 2. Monthly Breakdown Carousel (Data Integrity Verified)
                let trendsToDisplay = viewModel.currentSectionStats.monthlyTrends
                
                if !trendsToDisplay.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(state.theme.accent)
                            Text("Monthly Breakdown")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(state.theme.textPrimary)
                        }
                        .padding(.horizontal, 32)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(trendsToDisplay) { trend in
                                    ReplayMonthlyCardView(trend: trend, state: state)
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // MARK: - 3 & 4. Top Artists & Top Tracks Grids
                LazyVGrid(columns: chartColumns, spacing: 28) {
                    // Top Artists Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.crop.artframe")
                                .foregroundColor(state.theme.accent)
                            Text("Top Artists")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(state.theme.textPrimary)
                        }
                        
                        VStack(spacing: 0) {
                            let topArtistsList = Array(viewModel.currentSectionStats.topArtists.prefix(5))
                            if topArtistsList.isEmpty {
                                Text("No artist stats available yet.")
                                    .font(.subheadline)
                                    .foregroundColor(state.theme.textSecondary)
                                    .padding(24)
                            } else {
                                ForEach(Array(topArtistsList.enumerated()), id: \.element.id) { index, artist in
                                    TopArtistRowView(index: index, artist: artist, state: state)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                    
                                    if index < topArtistsList.count - 1 {
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(state.theme.cardBackground.opacity(0.6))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .padding(.leading, 32)
                    
                    // Top Tracks Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "music.note.list")
                                .foregroundColor(state.theme.accent)
                            Text("Most Played Songs")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(state.theme.textPrimary)
                        }
                        
                        VStack(spacing: 0) {
                            let topTracksList = Array(viewModel.currentSectionStats.topTracks.prefix(5))
                            if topTracksList.isEmpty {
                                Text("No track stats available yet.")
                                    .font(.subheadline)
                                    .foregroundColor(state.theme.textSecondary)
                                    .padding(24)
                            } else {
                                ForEach(Array(topTracksList.enumerated()), id: \.element.id) { index, trackHistory in
                                    let localTrack = findLocalTrack(for: trackHistory)
                                    
                                    TopTrackRowView(index: index, trackHistory: trackHistory, track: localTrack, state: state)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                    
                                    if index < topTracksList.count - 1 {
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(state.theme.cardBackground.opacity(0.6))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .padding(.trailing, 32)
                }
                
                // MARK: - 5. Auto-Generated Playlist Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Replay Playlist")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(state.theme.textPrimary)
                        .padding(.horizontal, 32)
                    
                    HStack(spacing: 24) {
                        ZStack {
                            LinearGradient(
                                gradient: Gradient(colors: [state.theme.accent, Color.black.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: 140, height: 140)
                            .cornerRadius(16)
                            .shadow(color: state.theme.accent.opacity(0.3), radius: 10, x: 0, y: 5)
                            
                            VStack(spacing: 2) {
                                Text(String(stats.year))
                                    .font(.system(size: 34, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text("REPLAY")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mesh Replay \(String(stats.year))")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(state.theme.textPrimary)
                            
                            Text("Your top songs of the year compiled into an automatic playlist, updated weekly.")
                                .font(.subheadline)
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(2)
                            
                            Button(action: {
                                let topTracks = Array(state.tracks.sorted { $0.playCount > $1.playCount }.prefix(25))
                                let playlistTracks = topTracks.map { PlaylistTrack(track: $0) }
                                let newPlaylist = Playlist(
                                    name: "Mesh Replay \(stats.year)",
                                    description: "Top tracks of \(stats.year)",
                                    isImported: false,
                                    playlistTracks: playlistTracks
                                )
                                state.playlists.append(newPlaylist)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add to Library")
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(state.theme.accent)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                    .padding(24)
                    .background(state.theme.cardBackground.opacity(0.6))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                }
                }
                
                Spacer(minLength: 80)
            }
        }
        .background(state.theme.background)
        .sheet(isPresented: $viewModel.isHighlightReelPresented) {
            HighlightReelModalView(
                section: viewModel.selectedSection,
                stats: viewModel.currentSectionStats,
                state: state,
                isPresented: $viewModel.isHighlightReelPresented
            )
        }
        .sheet(isPresented: $viewModel.isExportCardPresented) {
            VStack {
                HStack {
                    Spacer()
                    Button("Close") { viewModel.isExportCardPresented = false }
                        .padding()
                }
                ReplayShareCardView(stats: viewModel.currentSectionStats, theme: state.theme)
                    .padding()
            }
            .frame(width: 480, height: 720)
            .background(state.theme.background)
        }
    }
    
    private func lockedTitle(for section: ReplaySection) -> String {
        switch section {
        case .yearly:
            return "Yearly Replay Locked"
        case .monthly:
            return "\(viewModel.previousMonthName) Recap Locked"
        case .weekly:
            return "Previous Week Overview Locked"
        }
    }
    
    private func lockReasonText(for section: ReplaySection) -> String {
        switch section {
        case .yearly:
            return "Yearly Replay statistics are unlocked automatically starting December 1st of each year."
        case .monthly:
            return "\(viewModel.previousMonthName) Recap is locked because no listening data was recorded for \(viewModel.previousMonthName)."
        case .weekly:
            return "Previous Week Overview is locked because no listening data was recorded over the past week."
        }
    }
    
    private func heroTitle(for section: ReplaySection) -> String {
        switch section {
        case .yearly:
            return "Mesh Replay \(viewModel.yearlyStats.year)"
        case .monthly:
            return "Mesh Replay \(viewModel.previousMonthName) Recap"
        case .weekly:
            return "Mesh Replay Previous Week Overview"
        }
    }
    
    private func findLocalTrack(for trackHistory: TrackPlayHistory) -> LocalTrack {
        if let found = state.tracks.first(where: { $0.id == trackHistory.trackId }) {
            return found
        }
        return LocalTrack(
            title: trackHistory.title,
            artist: trackHistory.artist,
            album: "Replay",
            genre: "Music",
            duration: trackHistory.totalListenDuration,
            fileURL: nil,
            coverImageName: "music.note",
            dateAdded: Date(),
            isAtmos: false,
            fileSize: "0 MB",
            lyrics: ""
        )
    }
}

// MARK: - Replay Monthly Card View
struct ReplayMonthlyCardView: View {
    let trend: MonthlyTrend
    @ObservedObject var state: AppStateManager
    @State private var isHovered = false
    
    var monthName: String {
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        guard trend.month >= 1 && trend.month <= 12 else { return "Month \(trend.month)" }
        return months[trend.month - 1]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(monthName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(state.theme.accent)
                
                Spacer()
                
                Text("\(trend.listeningMinutes) Mins")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state.theme.accent.opacity(0.15))
                    .foregroundColor(state.theme.accent)
                    .cornerRadius(6)
            }
            
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.theme.accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    if let track = state.tracks.first(where: { $0.title == trend.topTrack || $0.artist == trend.topArtist }) {
                        AsyncFlexibleThumbnailView(track: track, maxPixelSize: 88, theme: state.theme, cornerRadius: 8)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(state.theme.accent)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(trend.topTrack)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(state.theme.textPrimary)
                        .lineLimit(1)
                    
                    Text(trend.topArtist)
                        .font(.system(size: 11))
                        .foregroundColor(state.theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 210)
        .background(state.theme.cardBackground.opacity(isHovered ? 0.9 : 0.6))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHovered ? state.theme.accent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Top Artist Row View
struct TopArtistRowView: View {
    let index: Int
    let artist: ArtistMilestone
    @ObservedObject var state: AppStateManager
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(index == 0 ? state.theme.accent : state.theme.textSecondary.opacity(0.6))
                .frame(width: 24, alignment: .center)
            
            CachedArtistProfileView(artistName: artist.name, themeAccent: state.theme.accent)
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(state.theme.textPrimary)
                    .lineLimit(1)
                
                Text("\(artist.playCount) Plays • \(max(1, artist.playCount * 4)) mins")
                    .font(.system(size: 11))
                    .foregroundColor(state.theme.textSecondary)
            }
            
            Spacer()
            
            if let badge = artist.badge {
                Text(badge.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(state.theme.accent.opacity(0.15))
                    .foregroundColor(state.theme.accent)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        .cornerRadius(10)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Top Track Row View
struct TopTrackRowView: View {
    let index: Int
    let trackHistory: TrackPlayHistory
    let track: LocalTrack
    @ObservedObject var state: AppStateManager
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(index == 0 ? state.theme.accent : state.theme.textSecondary.opacity(0.6))
                .frame(width: 24, alignment: .center)
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(state.theme.cardBackground)
                    .frame(width: 46, height: 46)
                
                AsyncFlexibleThumbnailView(track: track, maxPixelSize: 92, theme: state.theme, cornerRadius: 8)
                    .frame(width: 46, height: 46)
            }
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(trackHistory.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(state.theme.textPrimary)
                    .lineLimit(1)
                
                Text("\(trackHistory.artist) • \(trackHistory.playCount) \(trackHistory.playCount == 1 ? "play" : "plays")")
                    .font(.system(size: 11))
                    .foregroundColor(state.theme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(trackHistory.playCount) Plays")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .foregroundColor(state.theme.textSecondary)
                .cornerRadius(6)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        .cornerRadius(10)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Highlight Reel Specs & Interactive Story Overlay
struct HighlightReelModalView: View {
    let section: ReplaySection
    let stats: ReplayStats
    @ObservedObject var state: AppStateManager
    @Binding var isPresented: Bool
    
    @State private var currentSlide: Int = 0
    @State private var isPaused: Bool = false
    
    var slideCount: Int {
        switch section {
        case .weekly: return 4
        case .monthly: return 4
        case .yearly: return 5
        }
    }
    
    var body: some View {
        ZStack {
            // Ambient Gradient Canvas
            LinearGradient(
                gradient: Gradient(colors: [
                    state.theme.accent.opacity(0.9),
                    Color.purple.opacity(0.8),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Top Progress Bar Indicators
                HStack(spacing: 6) {
                    ForEach(0..<slideCount, id: \.self) { index in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.3))
                                if index < currentSlide {
                                    Capsule().fill(Color.white)
                                } else if index == currentSlide {
                                    Capsule().fill(Color.white)
                                }
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Top Control Bar
                HStack {
                    Text("Mesh Replay Highlight")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Slide Content Rendering based on Section & Index
                Group {
                    switch section {
                    case .weekly:
                        renderWeeklySlide(index: currentSlide)
                    case .monthly:
                        renderMonthlySlide(index: currentSlide)
                    case .yearly:
                        renderYearlySlide(index: currentSlide)
                    }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
                .id("\(section.rawValue)_\(currentSlide)")
                
                Spacer()
                
                // Bottom Navigation Hints
                HStack {
                    Button(action: {
                        if currentSlide > 0 { currentSlide -= 1 }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Previous")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(currentSlide == 0 ? 0.3 : 0.9))
                    }
                    .disabled(currentSlide == 0)
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("\(currentSlide + 1) / \(slideCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Button(action: {
                        if currentSlide < slideCount - 1 {
                            currentSlide += 1
                        } else {
                            isPresented = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(currentSlide == slideCount - 1 ? "Finish" : "Next")
                            Image(systemName: currentSlide == slideCount - 1 ? "checkmark" : "chevron.right")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(state.theme.accent)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 520, height: 720)
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard !isPaused else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if currentSlide < slideCount - 1 {
                    currentSlide += 1
                } else {
                    isPresented = false
                }
            }
        }
    }
    
    // MARK: - Weekly Slides
    @ViewBuilder
    private func renderWeeklySlide(index: Int) -> some View {
        switch index {
        case 0:
            // Slide 1: Weekly Overview
            VStack(spacing: 20) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 56))
                    .foregroundColor(.white)
                Text("PREVIOUS WEEK OVERVIEW")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                VStack(spacing: 12) {
                    Text("\(Int(stats.totalListeningTimeSeconds / 60))")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Minutes Listened Last Week")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                    Text("\(stats.topTracks.count) Unique Songs Played")
                        .font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .foregroundColor(.white)
            }
            .padding(32)
            
        case 1:
            // Slide 2: Top Track of the Week
            let topTrackHistory = stats.topTracks.first
            let track = findLocalTrack(for: topTrackHistory)
            VStack(spacing: 20) {
                Text("TOP TRACK OF PREVIOUS WEEK")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                AsyncFlexibleThumbnailView(track: track, maxPixelSize: 320, theme: state.theme, cornerRadius: 18)
                    .frame(width: 200, height: 200)
                    .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
                
                VStack(spacing: 6) {
                    Text(topTrackHistory?.title ?? track.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(topTrackHistory?.artist ?? track.artist)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                
                Text("\(topTrackHistory?.playCount ?? 1) Plays Last Week")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(32)
            
        case 2:
            // Slide 3: Top Artist of the Week
            let topArtist = stats.topArtists.first
            VStack(spacing: 20) {
                Text("TOP ARTIST OF PREVIOUS WEEK")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                CachedArtistProfileView(artistName: topArtist?.name ?? "Top Artist", themeAccent: state.theme.accent, size: 160)
                    .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
                
                Text(topArtist?.name ?? "Top Artist")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(max(1, (topArtist?.playCount ?? 1) * 4)) Minutes Listened")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(32)
            
        default:
            // Slide 4: Weekly Vibe
            let topGenre = state.tracks.first(where: { $0.playCount > 0 })?.genre ?? "Pop"
            VStack(spacing: 24) {
                Text("WEEKLY VIBE")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 180, height: 180)
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.white)
                }
                
                Text(topGenre.uppercased())
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Your dominant soundscape over the previous week.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }
    
    // MARK: - Monthly Slides
    @ViewBuilder
    private func renderMonthlySlide(index: Int) -> some View {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let previousMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let previousMonthName = calendar.monthSymbols[previousMonth - 1]
        
        switch index {
        case 0:
            // Slide 1: Monthly Recap Header
            VStack(spacing: 20) {
                Text("\(previousMonthName.uppercased()) RECAP")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("\(Int(stats.totalListeningTimeSeconds / 3600)) Hours")
                    .font(.system(size: 64, weight: .black))
                    .foregroundColor(.white)
                
                Text("Total Stream Time")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                if let topGenre = state.tracks.first?.genre {
                    HStack {
                        Image(systemName: "music.quaver.line")
                        Text("Top Genre: \(topGenre)")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .foregroundColor(.white)
                }
            }
            .padding(32)
            
        case 1:
            // Slide 2: Top 3 Tracks of the Month
            VStack(spacing: 16) {
                Text("TOP 3 TRACKS IN \(previousMonthName.uppercased())")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                VStack(spacing: 12) {
                    ForEach(Array(stats.topTracks.prefix(3).enumerated()), id: \.element.id) { index, trackHistory in
                        let track = findLocalTrack(for: trackHistory)
                        HStack(spacing: 14) {
                            Text("#\(index + 1)")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.white.opacity(0.8))
                            AsyncFlexibleThumbnailView(track: track, maxPixelSize: 96, theme: state.theme, cornerRadius: 8)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading) {
                                Text(trackHistory.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Text(trackHistory.artist)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                            Text("\(trackHistory.playCount) plays")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(32)
            
        case 2:
            // Slide 3: Top Artist of the Month & Listener Badge
            let topArtist = stats.topArtists.first
            VStack(spacing: 20) {
                Text("TOP ARTIST IN \(previousMonthName.uppercased())")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                CachedArtistProfileView(artistName: topArtist?.name ?? "Top Artist", themeAccent: state.theme.accent, size: 150)
                
                Text(topArtist?.name ?? "Top Artist")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                
                Text("HEAVY ROTATION")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(state.theme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(32)
            
        default:
            // Slide 4: New Discovery
            let discoveryTrack = state.tracks.sorted(by: { $0.dateAdded > $1.dateAdded }).first ?? state.tracks.first
            let track = discoveryTrack ?? LocalTrack(title: "Discovery", artist: "Artist", album: "Album", genre: "Music", duration: 180, fileURL: nil, coverImageName: "music.note", dateAdded: Date(), isAtmos: false, fileSize: "0 MB", lyrics: "")
            
            VStack(spacing: 20) {
                Text("NEW DISCOVERY IN \(previousMonthName.uppercased())")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                AsyncFlexibleThumbnailView(track: track, maxPixelSize: 320, theme: state.theme, cornerRadius: 16)
                    .frame(width: 180, height: 180)
                
                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text(track.artist)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Text("Added this month & played repeatedly")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(32)
        }
    }
    
    // MARK: - Yearly Slides
    @ViewBuilder
    private func renderYearlySlide(index: Int) -> some View {
        switch index {
        case 0:
            // Slide 1: Year in Review
            VStack(spacing: 20) {
                Text("MESH REPLAY \(stats.year)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("\(Int(stats.totalListeningTimeSeconds / 3600)) Hours")
                    .font(.system(size: 64, weight: .black))
                    .foregroundColor(.white)
                
                Text("Total Music Listened")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                let uniqueArtists = Set(state.tracks.map { $0.artist }).count
                Text("\(uniqueArtists) Unique Artists Explored")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .foregroundColor(.white)
            }
            .padding(32)
            
        case 1:
            // Slide 2: Top Artist #1 + Total Minutes Streamed
            let topArtist = stats.topArtists.first
            VStack(spacing: 20) {
                Text("YOUR #1 ARTIST")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                CachedArtistProfileView(artistName: topArtist?.name ?? "Top Artist", themeAccent: state.theme.accent, size: 160)
                
                Text(topArtist?.name ?? "Top Artist")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)
                
                Text("\(max(1, (topArtist?.playCount ?? 1) * 8)) Minutes Streamed")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(32)
            
        case 2:
            // Slide 3: Top 5 Tracks Countdown
            VStack(spacing: 14) {
                Text("TOP 5 TRACKS COUNTDOWN")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                VStack(spacing: 8) {
                    ForEach(Array(stats.topTracks.prefix(5).enumerated()), id: \.element.id) { index, trackHistory in
                        let track = findLocalTrack(for: trackHistory)
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(state.theme.accent)
                                .frame(width: 24)
                            AsyncFlexibleThumbnailView(track: track, maxPixelSize: 80, theme: state.theme, cornerRadius: 6)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trackHistory.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(trackHistory.artist)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
            .padding(28)
            
        case 3:
            // Slide 4: Monthly Journey
            VStack(spacing: 18) {
                Text("MONTHLY JOURNEY")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(stats.monthlyTrends.prefix(6)) { trend in
                        VStack(spacing: 4) {
                            Text(Calendar.current.shortMonthSymbols[max(0, min(11, trend.month - 1))])
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.theme.accent)
                            Text(trend.topTrack)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(trend.topArtist)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(8)
                        .frame(height: 64)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(32)
            
        default:
            // Slide 5: Summary Card
            ReplayShareCardView(stats: stats, theme: state.theme)
                .scaleEffect(0.85)
        }
    }
    
    private func findLocalTrack(for trackHistory: TrackPlayHistory?) -> LocalTrack {
        guard let trackHistory = trackHistory else {
            return LocalTrack(title: "Track", artist: "Artist", album: "Album", genre: "Music", duration: 180, fileURL: nil, coverImageName: "music.note", dateAdded: Date(), isAtmos: false, fileSize: "0 MB", lyrics: "")
        }
        if let found = state.tracks.first(where: { $0.id == trackHistory.trackId }) {
            return found
        }
        return LocalTrack(
            title: trackHistory.title,
            artist: trackHistory.artist,
            album: "Replay",
            genre: "Music",
            duration: trackHistory.totalListenDuration,
            fileURL: nil,
            coverImageName: "music.note",
            dateAdded: Date(),
            isAtmos: false,
            fileSize: "0 MB",
            lyrics: ""
        )
    }
}
