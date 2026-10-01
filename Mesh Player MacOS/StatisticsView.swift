//
//  StatisticsView.swift
//  Mesh Player
//
//  The expanded version of Home's stat cards: listening over time, when you listen, top
//  artists / songs / genres, and how the library itself is made up. Listening charts use the
//  play history Mesh Player records (one entry per counted play); library charts use the songs.
//

import Charts
import SwiftUI

struct StatisticsView: View {
    @ObservedObject var state: AppStateManager
    let engine: AudioEngineManager

    enum Period: String, CaseIterable, Identifiable {
        case week = "7 Days"
        case month = "30 Days"
        case year = "12 Months"
        case all = "All Time"
        var id: String { rawValue }

        var start: Date? {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            switch self {
            case .week: return cal.date(byAdding: .day, value: -6, to: today)
            case .month: return cal.date(byAdding: .day, value: -29, to: today)
            case .year: return cal.date(byAdding: .month, value: -11, to: cal.date(from: cal.dateComponents([.year, .month], from: today))!)
            case .all: return nil
            }
        }

        /// Bars per day for short periods, per month for long ones.
        var bucket: Calendar.Component { self == .week || self == .month ? .day : .month }
    }

    @AppStorage("statistics.period") private var period: Period = .month

    var body: some View {
        let theme = state.theme
        let stats = ListeningStats(state: state, period: period)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Statistics", subtitle: stats.historyNote, theme: theme) {
                    Picker("", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.bottom, -8)

                // Headline numbers for the period.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    StatTile(value: Fmt.count(stats.plays), label: "Plays", detail: stats.playsDelta, theme: theme)
                    StatTile(value: Fmt.listening(stats.listeningSeconds), label: "Listening time", detail: stats.dailyAverage, theme: theme)
                    StatTile(value: "\(stats.streak) day\(stats.streak == 1 ? "" : "s")", label: "Current streak", detail: "Longest: \(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")", theme: theme)
                    StatTile(value: Fmt.count(stats.uniqueSongs), label: "Different songs", detail: nil, theme: theme)
                    StatTile(value: Fmt.count(stats.uniqueArtists), label: "Different artists", detail: nil, theme: theme)
                    StatTile(value: Fmt.count(stats.newSongsPlayed), label: "First listens", detail: "Songs played for the first time", theme: theme)
                }
                .padding(.horizontal, 28)

                if stats.plays == 0 {
                    Text("No plays recorded in this period yet. A play counts once you've heard half of a song.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 28)
                } else {
                    ChartCard(title: "Plays over time", subtitle: period.bucket == .day ? "Per day" : "Per month", theme: theme) {
                        TimeBarChart(points: stats.timeline, unit: period.bucket, theme: theme)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        ChartCard(title: "Time of day", subtitle: "Plays by hour", theme: theme, padded: false) {
                            CategoryBarChart(points: stats.byHour, theme: theme, valueLabel: "plays")
                        }
                        ChartCard(title: "Day of week", subtitle: "Plays by weekday", theme: theme, padded: false) {
                            CategoryBarChart(points: stats.byWeekday, theme: theme, valueLabel: "plays")
                        }
                    }
                    .padding(.horizontal, 28)

                    HStack(alignment: .top, spacing: 16) {
                        ChartCard(title: "Top artists", subtitle: "By plays", theme: theme, padded: false) {
                            RankedBars(items: stats.topArtists, theme: theme) { state.showArtist($0) }
                        }
                        ChartCard(title: "Top genres", subtitle: "By plays", theme: theme, padded: false) {
                            RankedBars(items: stats.topGenres, theme: theme) { state.showGenre($0) }
                        }
                    }
                    .padding(.horizontal, 28)

                    ChartCard(title: "Top songs", subtitle: "Most played in this period", theme: theme) {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.topSongs.enumerated()), id: \.element.track.id) { index, item in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                                        .foregroundStyle(theme.textTertiary)
                                        .frame(width: 22, alignment: .trailing)
                                    ArtworkView(track: item.track, pixelSize: 80, cornerRadius: 4)
                                        .frame(width: 34, height: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.track.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textPrimary).lineLimit(1)
                                        Text(item.track.artist).font(.system(size: 11.5)).foregroundStyle(theme.textSecondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(Fmt.count(item.plays)) play\(item.plays == 1 ? "" : "s")")
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { state.play(stats.topSongs.map(\.track), startingAt: item.track, engine: engine) }
                            }
                        }
                    }
                }

                // Library make-up (independent of the period).
                Text("Your Library")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    StatTile(value: Fmt.count(stats.library.songs), label: "Songs", detail: Fmt.longDuration(stats.library.totalSeconds), theme: theme)
                    StatTile(value: "\(stats.library.playedPercent)%", label: "Played at least once", detail: "\(Fmt.count(stats.library.neverPlayed)) never played", theme: theme)
                    StatTile(value: Fmt.count(stats.library.favorites), label: "Favorites", detail: nil, theme: theme)
                }
                .padding(.horizontal, 28)

                ChartCard(title: "Songs added", subtitle: "Per month, last two years", theme: theme) {
                    TimeBarChart(points: stats.library.addedPerMonth, unit: .month, theme: theme, valueLabel: "songs added")
                }

                HStack(alignment: .top, spacing: 16) {
                    ChartCard(title: "Decades", subtitle: "Songs by release year", theme: theme, padded: false) {
                        CategoryBarChart(points: stats.library.byDecade, theme: theme, valueLabel: "songs")
                    }
                    ChartCard(title: "Audio quality", subtitle: "Songs by format", theme: theme, padded: false) {
                        RankedBars(items: stats.library.byQuality, theme: theme, onSelect: nil)
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(theme.background)
    }
}

// MARK: - Numbers

struct CountPoint: Identifiable, Hashable {
    let label: String
    let value: Int
    var id: String { label }
}

struct DatePoint: Identifiable, Hashable {
    let date: Date
    let value: Int
    var id: Date { date }
}

struct RankedItem: Identifiable, Hashable {
    let name: String
    let value: Int
    var id: String { name }
}

/// Everything the statistics page shows, worked out in one pass.
struct ListeningStats {
    struct Library {
        var songs = 0
        var totalSeconds: TimeInterval = 0
        var neverPlayed = 0
        var playedPercent = 0
        var favorites = 0
        var addedPerMonth: [DatePoint] = []
        var byDecade: [CountPoint] = []
        var byQuality: [RankedItem] = []
    }

    var plays = 0
    var listeningSeconds: TimeInterval = 0
    var uniqueSongs = 0
    var uniqueArtists = 0
    var newSongsPlayed = 0
    var streak = 0
    var longestStreak = 0
    var playsDelta: String?
    var dailyAverage: String?
    var timeline: [DatePoint] = []
    var byHour: [CountPoint] = []
    var byWeekday: [CountPoint] = []
    var topArtists: [RankedItem] = []
    var topGenres: [RankedItem] = []
    var topSongs: [(track: LocalTrack, plays: Int)] = []
    var historyNote = ""
    var library = Library()

    init(state: AppStateManager, period: StatisticsView.Period) {
        let cal = Calendar.current
        let log = state.playHistoryLog
        let start = period.start
        let entries = start.map { s in log.filter { $0.timestamp >= s } } ?? log
        let byId = Dictionary(state.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        plays = entries.count
        listeningSeconds = entries.reduce(0) { $0 + $1.duration }
        uniqueSongs = Set(entries.map(\.trackId)).count
        uniqueArtists = Set(entries.map { state.displayArtist($0.artist) }).count

        // First listens: songs whose first logged play falls in the period.
        var firstPlay: [UUID: Date] = [:]
        for entry in log where firstPlay[entry.trackId].map({ entry.timestamp < $0 }) ?? true { firstPlay[entry.trackId] = entry.timestamp }
        newSongsPlayed = start.map { s in firstPlay.values.filter { $0 >= s }.count } ?? firstPlay.count

        // Compared with the period before.
        if let start, let length = cal.dateComponents([.day], from: start, to: Date()).day, length > 0,
           let previousStart = cal.date(byAdding: .day, value: -(length + 1), to: start) {
            let previous = log.filter { $0.timestamp >= previousStart && $0.timestamp < start }.count
            if previous > 0 {
                let change = Int((Double(plays - previous) / Double(previous) * 100).rounded())
                playsDelta = change == 0 ? "Same as the period before" : "\(change > 0 ? "+" : "")\(change)% vs. the period before"
            }
            dailyAverage = "\(Fmt.listening(listeningSeconds / Double(length + 1))) a day on average"
        }

        // Streaks of consecutive days with at least one play.
        let days = Set(log.map { cal.startOfDay(for: $0.timestamp) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var run = 0
        var previousDay: Date?
        for d in days.sorted() {
            if let p = previousDay, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            longestStreak = max(longestStreak, run)
            previousDay = d
        }

        // Timeline with empty buckets filled in.
        var buckets: [Date: Int] = [:]
        for entry in entries {
            let key = period.bucket == .day ? cal.startOfDay(for: entry.timestamp) : cal.date(from: cal.dateComponents([.year, .month], from: entry.timestamp))!
            buckets[key, default: 0] += 1
        }
        let first = start ?? buckets.keys.min() ?? Date()
        var cursor = period.bucket == .day ? cal.startOfDay(for: first) : cal.date(from: cal.dateComponents([.year, .month], from: first))!
        while cursor <= Date() {
            timeline.append(DatePoint(date: cursor, value: buckets[cursor] ?? 0))
            cursor = cal.date(byAdding: period.bucket, value: 1, to: cursor)!
        }

        var hours = [Int](repeating: 0, count: 24)
        var weekdays = [Int](repeating: 0, count: 7)
        for entry in entries {
            hours[cal.component(.hour, from: entry.timestamp)] += 1
            weekdays[cal.component(.weekday, from: entry.timestamp) - 1] += 1
        }
        byHour = hours.enumerated().map { CountPoint(label: Self.hourLabel($0.offset), value: $0.element) }
        let symbols = cal.shortWeekdaySymbols
        let firstWeekday = cal.firstWeekday - 1
        byWeekday = (0..<7).map { i in let d = (i + firstWeekday) % 7; return CountPoint(label: symbols[d], value: weekdays[d]) }

        var artistCounts: [String: Int] = [:]
        var genreCounts: [String: Int] = [:]
        var songCounts: [UUID: Int] = [:]
        for entry in entries {
            artistCounts[state.displayArtist(entry.artist), default: 0] += 1
            genreCounts[entry.genre.isEmpty ? "Unknown" : entry.genre, default: 0] += 1
            songCounts[entry.trackId, default: 0] += 1
        }
        topArtists = artistCounts.sorted { $0.value > $1.value }.prefix(8).map { RankedItem(name: $0.key, value: $0.value) }
        topGenres = genreCounts.sorted { $0.value > $1.value }.prefix(8).map { RankedItem(name: $0.key, value: $0.value) }
        topSongs = songCounts.sorted { $0.value > $1.value }.compactMap { id, count in byId[id].map { ($0, count) } }.prefix(10).map { $0 }

        if let earliest = log.map(\.timestamp).min() {
            historyNote = "Listening charts cover plays recorded since \(Fmt.date(earliest))"
        } else {
            historyNote = "Listening charts fill in as you play music in Mesh Player"
        }

        // Library.
        let songs = state.libraryTracks
        library.songs = songs.count
        library.totalSeconds = songs.reduce(0) { $0 + $1.duration }
        library.neverPlayed = songs.filter { $0.playCount == 0 }.count
        library.playedPercent = songs.isEmpty ? 0 : Int((Double(songs.count - library.neverPlayed) / Double(songs.count) * 100).rounded())
        library.favorites = songs.filter(\.isFavorite).count

        var added: [Date: Int] = [:]
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let addedStart = cal.date(byAdding: .month, value: -23, to: thisMonth)!
        for track in songs where track.dateAdded >= addedStart {
            added[cal.date(from: cal.dateComponents([.year, .month], from: track.dateAdded))!, default: 0] += 1
        }
        var month = addedStart
        while month <= thisMonth {
            library.addedPerMonth.append(DatePoint(date: month, value: added[month] ?? 0))
            month = cal.date(byAdding: .month, value: 1, to: month)!
        }

        var decades: [Int: Int] = [:]
        for track in songs { if let year = track.year, year > 1900 { decades[year / 10 * 10, default: 0] += 1 } }
        library.byDecade = decades.keys.sorted().map { CountPoint(label: "\(String($0).suffix(2))s", value: decades[$0]!) }

        var quality: [String: Int] = [:]
        for track in songs {
            let format = track.format.lowercased()
            let kind = track.isAtmos ? "Dolby Atmos" : (format.contains("alac") || format.contains("lossless") || format.contains("flac") ? ((track.bitDepth ?? 16) > 16 || (track.sampleRate ?? 44_100) > 48_000 ? "Hi-Res Lossless" : "Lossless") : (format.contains("mp3") ? "MP3" : "AAC"))
            quality[kind, default: 0] += 1
        }
        library.byQuality = quality.sorted { $0.value > $1.value }.map { RankedItem(name: $0.key, value: $0.value) }
    }

    private static func hourLabel(_ hour: Int) -> String {
        hour == 0 ? "12a" : hour < 12 ? "\(hour)a" : hour == 12 ? "12p" : "\(hour - 12)p"
    }
}

// MARK: - Pieces

private struct StatTile: View {
    let value: String
    let label: String
    let detail: String?
    let theme: ThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text(detail ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card(theme, radius: 14)
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    let theme: ThemeColor
    var padded = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(theme.textPrimary)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(theme.textSecondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme, radius: 14)
        .padding(.horizontal, padded ? 28 : 0)
    }
}

/// Bars over time (single series in the accent color) with a hover readout.
private struct TimeBarChart: View {
    let points: [DatePoint]
    let unit: Calendar.Component
    let theme: ThemeColor
    var valueLabel = "plays"
    @State private var selected: Date?

    var body: some View {
        let hovered = selected.flatMap { s in points.first { Calendar.current.isDate($0.date, equalTo: s, toGranularity: unit) } }
        Chart(points) { point in
            BarMark(x: .value("Date", point.date, unit: unit), y: .value("Count", point.value), width: .ratio(0.7))
                .foregroundStyle(theme.accent.opacity(hovered == nil || hovered == point ? 1 : 0.45))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            if let hovered, hovered == point {
                RuleMark(x: .value("Date", point.date, unit: unit))
                    .foregroundStyle(theme.textTertiary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Tooltip(title: point.date.formatted(unit == .day ? .dateTime.weekday(.abbreviated).month(.abbreviated).day() : .dateTime.month(.wide).year()),
                                value: "\(Fmt.count(point.value)) \(valueLabel)", theme: theme)
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(theme.hairline)
                AxisValueLabel().foregroundStyle(theme.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisValueLabel(format: unit == .day ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated)).foregroundStyle(theme.textTertiary)
            }
        }
        .frame(height: 200)
    }
}

/// Bars over fixed categories (hours, weekdays, decades) with a hover readout.
private struct CategoryBarChart: View {
    let points: [CountPoint]
    let theme: ThemeColor
    let valueLabel: String
    @State private var selected: String?

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Category", point.label), y: .value("Count", point.value), width: .ratio(0.7))
                .foregroundStyle(theme.accent.opacity(selected == nil || selected == point.label ? 1 : 0.45))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                .annotation(position: .top) {
                    if selected == point.label {
                        Tooltip(title: point.label, value: "\(Fmt.count(point.value)) \(valueLabel)", theme: theme)
                    }
                }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(theme.hairline)
                AxisValueLabel().foregroundStyle(theme.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(theme.textTertiary) }
        }
        .frame(height: 170)
    }
}

/// Horizontal ranked bars with the name and value as text (no color-only reading needed).
private struct RankedBars: View {
    let items: [RankedItem]
    let theme: ThemeColor
    let onSelect: ((String) -> Void)?

    var body: some View {
        let maxValue = max(items.map(\.value).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(Fmt.count(item.value))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.accent)
                            .frame(width: max(4, geo.size.width * CGFloat(item.value) / CGFloat(maxValue)))
                    }
                    .frame(height: 6)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect?(item.name) }
                .help(onSelect == nil ? "" : "Open \(item.name)")
            }
        }
    }
}

private struct Tooltip: View {
    let title: String
    let value: String
    let theme: ThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.textSecondary)
            Text(value).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
