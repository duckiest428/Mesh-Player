//
//  InsightsViews.swift
//  Mesh Player iOS
//
//  Statistics and Replay on the iPhone. Both read the play history the two devices share (the
//  Mac sends its history when syncing; plays here are added and sent back), so the numbers
//  match the Mac's.
//

import Charts
import SwiftUI

// MARK: - Statistics

struct StatisticsView: View {
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @AppStorage("statistics.period") private var period: Period = .month

    enum Period: String, CaseIterable, Identifiable {
        case week = "7D"
        case month = "30D"
        case year = "12M"
        case all = "All"
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

        var bucket: Calendar.Component { self == .week || self == .month ? .day : .month }
    }

    var body: some View {
        let stats = PhoneStats(library: library, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Tile(value: "\(stats.plays)", label: "Plays")
                    Tile(value: Format.listening(stats.seconds), label: "Listening time")
                    Tile(value: "\(stats.streak)", label: "Day streak", detail: "Longest \(stats.longestStreak)")
                    Tile(value: "\(stats.uniqueSongs)", label: "Different songs")
                    Tile(value: "\(stats.uniqueArtists)", label: "Different artists")
                    Tile(value: "\(stats.firstListens)", label: "First listens")
                }

                if stats.plays == 0 {
                    Text("No plays in this period yet. A play counts once you've heard half of a song.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Card("Plays over time") {
                        Chart(stats.timeline) { point in
                            BarMark(x: .value("Date", point.date, unit: period.bucket), y: .value("Plays", point.value))
                                .foregroundStyle(.tint)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                        .frame(height: 170)
                    }
                    Card("Time of day") {
                        Chart(stats.byHour) { point in
                            BarMark(x: .value("Hour", point.label), y: .value("Plays", point.value))
                                .foregroundStyle(.tint)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                        }
                        .chartXAxis { AxisMarks(values: ["12a", "6a", "12p", "6p"]) }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                        .frame(height: 140)
                    }
                    Card("Top artists") { Ranked(items: stats.topArtists) }
                    Card("Top genres") { Ranked(items: stats.topGenres) }
                    Card("Top songs") {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.topSongs.enumerated()), id: \.element.song.id) { index, item in
                                Button { player.play(stats.topSongs.map(\.song), startAt: item.song) } label: {
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                        ArtworkImage(key: item.song.artworkKey, size: 40, cornerRadius: 5, seed: item.song.album).frame(width: 40, height: 40)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.song.title).lineLimit(1)
                                            Text(item.song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text("\(item.plays)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Text("Your Library").font(.title2.bold()).padding(.top, 8)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Tile(value: "\(stats.librarySongs)", label: "Songs")
                    Tile(value: "\(stats.playedPercent)%", label: "Played at least once")
                }
                if !stats.decades.isEmpty {
                    Card("Decades") {
                        Chart(stats.decades) { point in
                            BarMark(x: .value("Decade", point.label), y: .value("Songs", point.value))
                                .foregroundStyle(.tint)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                        .frame(height: 140)
                    }
                }
                Card("Audio quality") { Ranked(items: stats.quality) }
                Text(stats.note).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Statistics")
    }
}

struct CountPoint: Identifiable, Hashable { let label: String; let value: Int; var id: String { label } }
struct DatePoint: Identifiable, Hashable { let date: Date; let value: Int; var id: Date { date } }
struct RankedItem: Identifiable, Hashable { let name: String; let value: Int; var id: String { name } }

/// The statistics page's numbers for one period.
struct PhoneStats {
    var plays = 0, seconds: TimeInterval = 0, uniqueSongs = 0, uniqueArtists = 0, firstListens = 0
    var streak = 0, longestStreak = 0
    var timeline: [DatePoint] = []
    var byHour: [CountPoint] = []
    var topArtists: [RankedItem] = []
    var topGenres: [RankedItem] = []
    var topSongs: [(song: Song, plays: Int)] = []
    var librarySongs = 0, playedPercent = 0
    var decades: [CountPoint] = []
    var quality: [RankedItem] = []
    var note = ""

    init(library: MobileLibrary, period: StatisticsView.Period) {
        let cal = Calendar.current
        let log = library.playHistory
        let start = period.start
        let entries = start.map { s in log.filter { $0.timestamp >= s } } ?? log
        plays = entries.count
        seconds = entries.reduce(0) { $0 + $1.duration }
        uniqueSongs = Set(entries.map(\.trackId)).count
        uniqueArtists = Set(entries.map { library.displayArtist($0.artist) }).count

        var first: [UUID: Date] = [:]
        for e in log where first[e.trackId].map({ e.timestamp < $0 }) ?? true { first[e.trackId] = e.timestamp }
        firstListens = start.map { s in first.values.filter { $0 >= s }.count } ?? first.count

        let days = Set(log.map { cal.startOfDay(for: $0.timestamp) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) { streak += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        var run = 0, previous: Date?
        for d in days.sorted() {
            if let p = previous, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            longestStreak = max(longestStreak, run)
            previous = d
        }

        var buckets: [Date: Int] = [:]
        func key(_ date: Date) -> Date { period.bucket == .day ? cal.startOfDay(for: date) : cal.date(from: cal.dateComponents([.year, .month], from: date))! }
        for e in entries { buckets[key(e.timestamp), default: 0] += 1 }
        var cursor = key(start ?? buckets.keys.min() ?? Date())
        while cursor <= Date() {
            timeline.append(DatePoint(date: cursor, value: buckets[cursor] ?? 0))
            cursor = cal.date(byAdding: period.bucket, value: 1, to: cursor)!
        }

        var hours = [Int](repeating: 0, count: 24)
        var artists: [String: Int] = [:], genres: [String: Int] = [:], songs: [UUID: Int] = [:]
        for e in entries {
            hours[cal.component(.hour, from: e.timestamp)] += 1
            artists[library.displayArtist(e.artist), default: 0] += 1
            genres[e.genre.isEmpty ? "Unknown" : e.genre, default: 0] += 1
            songs[e.trackId, default: 0] += 1
        }
        byHour = hours.enumerated().map { CountPoint(label: $0.offset == 0 ? "12a" : $0.offset < 12 ? "\($0.offset)a" : $0.offset == 12 ? "12p" : "\($0.offset - 12)p", value: $0.element) }
        topArtists = artists.sorted { $0.value > $1.value }.prefix(6).map { RankedItem(name: $0.key, value: $0.value) }
        topGenres = genres.sorted { $0.value > $1.value }.prefix(6).map { RankedItem(name: $0.key, value: $0.value) }
        topSongs = songs.sorted { $0.value > $1.value }.compactMap { id, n in library.song(id).map { ($0, n) } }.prefix(10).map { $0 }

        let all = library.availableSongs
        librarySongs = all.count
        playedPercent = all.isEmpty ? 0 : Int((Double(all.filter { $0.playCount > 0 }.count) / Double(all.count) * 100).rounded())
        var decadeCounts: [Int: Int] = [:]
        for s in all { if let y = s.info.year, y > 1900 { decadeCounts[y / 10 * 10, default: 0] += 1 } }
        decades = decadeCounts.keys.sorted().map { CountPoint(label: "\(String($0).suffix(2))s", value: decadeCounts[$0]!) }
        var q: [String: Int] = [:]
        for s in all { q[s.qualityLabel ?? (s.info.format.localizedCaseInsensitiveContains("mp3") ? "MP3" : "AAC"), default: 0] += 1 }
        quality = q.sorted { $0.value > $1.value }.map { RankedItem(name: $0.key, value: $0.value) }

        note = log.isEmpty ? "Charts fill in as you listen. Plays from your Mac arrive when you sync."
            : "Includes plays from your Mac (as of the last sync) and from this iPhone, since \(log.map(\.timestamp).min()!.formatted(date: .abbreviated, time: .omitted))."
    }
}

private struct Tile: View {
    let value: String
    let label: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(detail ?? " ").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Ranked: View {
    let items: [RankedItem]

    var body: some View {
        let top = max(items.map(\.value).max() ?? 1, 1)
        VStack(spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("\(item.value)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(.tint).frame(width: max(4, geo.size.width * CGFloat(item.value) / CGFloat(top)))
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}

// MARK: - Replay

/// A year in listening: minutes, the top artist, songs and albums, and month by month.
struct ReplayView: View {
    @EnvironmentObject var library: MobileLibrary
    @EnvironmentObject var player: MobilePlayer
    @State private var year = Calendar.current.component(.year, from: Date())

    var body: some View {
        let cal = Calendar.current
        let years = Array(Set(library.playHistory.map { cal.component(.year, from: $0.timestamp) })).sorted(by: >)
        let entries = library.playHistory.filter { cal.component(.year, from: $0.timestamp) == year }
        let minutes = Int(entries.reduce(0) { $0 + $1.duration } / 60)
        var songCounts: [UUID: Int] = [:], artistCounts: [String: Int] = [:], albumCounts: [String: Int] = [:]
        var monthMinutes = [Double](repeating: 0, count: 12)
        for e in entries {
            songCounts[e.trackId, default: 0] += 1
            artistCounts[library.displayArtist(e.artist), default: 0] += 1
            albumCounts[e.album, default: 0] += 1
            monthMinutes[cal.component(.month, from: e.timestamp) - 1] += e.duration / 60
        }
        let topSongs = songCounts.sorted { $0.value > $1.value }.compactMap { id, n in library.song(id).map { ($0, n) } }.prefix(10)
        let topArtists = artistCounts.sorted { $0.value > $1.value }.prefix(5)
        let topAlbums = albumCounts.sorted { $0.value > $1.value }.compactMap { name, n in library.albums.first { $0.title == name }.map { ($0, n) } }.prefix(6)
        let months = monthMinutes.enumerated().map { CountPoint(label: cal.shortMonthSymbols[$0.offset], value: Int($0.element)) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Hero
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(red: 0.98, green: 0.24, blue: 0.42), Color(red: 0.55, green: 0.18, blue: 0.85), Color(red: 0.12, green: 0.08, blue: 0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let first = topSongs.first?.0 {
                        ArtworkImage(key: first.artworkKey, size: 220, cornerRadius: 12, seed: first.album)
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(8))
                            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(20)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replay \(String(year))").font(.title.bold())
                        Text("\(minutes.formatted()) minutes").font(.system(size: 40, weight: .heavy))
                        Text("\(entries.count.formatted()) plays · \(Set(entries.map(\.trackId)).count) songs · \(artistCounts.count) artists")
                            .font(.subheadline.weight(.medium)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if entries.isEmpty {
                    Text("No plays recorded in \(String(year)) yet.").foregroundStyle(.secondary)
                } else {
                    if let (artist, plays) = topArtists.first {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Top Artist").font(.headline).foregroundStyle(.secondary)
                            Text(artist).font(.largeTitle.bold())
                            Text("\(plays) plays").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    section("Top Songs") {
                        VStack(spacing: 0) {
                            ForEach(Array(topSongs.enumerated()), id: \.element.0.id) { index, item in
                                Button { player.play(topSongs.map(\.0), startAt: item.0) } label: {
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)").font(.title3.bold().monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
                                        ArtworkImage(key: item.0.artworkKey, size: 48, cornerRadius: 6, seed: item.0.album).frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.0.title).lineLimit(1)
                                            Text(item.0.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text("\(item.1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !topAlbums.isEmpty {
                        section("Top Albums") {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                                ForEach(Array(topAlbums), id: \.0.key) { album, plays in
                                    NavigationLink(value: album) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ArtworkImage(key: album.representative.artworkKey, size: 180, cornerRadius: 10, seed: album.title).aspectRatio(1, contentMode: .fit)
                                            Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                            Text("\(plays) plays").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    section("Top Artists") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(topArtists.enumerated()), id: \.element.key) { index, item in
                                HStack {
                                    Text("\(index + 1)").font(.title3.bold()).foregroundStyle(.secondary).frame(width: 28)
                                    Text(item.key).font(.title3)
                                    Spacer()
                                    Text("\(item.value) plays").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    section("Minutes by Month") {
                        Chart(months) { point in
                            BarMark(x: .value("Month", point.label), y: .value("Minutes", point.value))
                                .foregroundStyle(.tint)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                        .frame(height: 160)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Replay")
        .toolbar {
            if years.count > 1 {
                Menu {
                    Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                } label: { Label(String(year), systemImage: "calendar") }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            content()
        }
    }
}
