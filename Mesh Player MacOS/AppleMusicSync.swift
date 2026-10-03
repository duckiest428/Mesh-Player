//
//  AppleMusicSync.swift
//  Mesh Player
//
//  Sends changes made in Mesh Player back to the Music app:
//   • songs added to Mesh that the Music library doesn't have yet
//   • playlists created or edited in Mesh (mirrored: same songs, same order)
//   • favorites → loved
//  The Music app's current state is read first (iTunesLibrary) so the user sees exactly what
//  will change before anything is sent. Changes are applied through Music's AppleScript
//  interface in small batches.
//

import AppKit
import Combine
import iTunesLibrary
import SwiftUI

final class AppleMusicSync: ObservableObject {
    static let shared = AppleMusicSync()

    nonisolated struct PlaylistChange: Identifiable {
        let id: UUID
        let name: String
        let exists: Bool
        let musicPlaylistID: String?
        let desired: [LocalTrack]
        let adds: Int
        let removes: Int
        var include = true
    }

    nonisolated struct Plan {
        var songsToAdd: [LocalTrack] = []
        var playlists: [PlaylistChange] = []
        var toLove: [LocalTrack] = []
        var includeSongs = true
        var includeLoves = true
        /// Songs unticked in the review sheet: not added to Music / not marked as loved.
        var skippedAdds: Set<UUID> = []
        var skippedLoves: Set<UUID> = []
        /// Mesh track id → Music persistent ID (hex) for songs Music already has.
        var knownIDs: [UUID: String] = [:]
        var error: String?

        var isEmpty: Bool { songsToAdd.isEmpty && playlists.isEmpty && toLove.isEmpty }
    }

    @Published var isPresented = false
    @Published var plan: Plan?
    @Published private(set) var isApplying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressText = ""
    @Published private(set) var resultText: String?

    private weak var state: AppStateManager?

    // MARK: Planning

    /// - Parameter playlists: the playlists to export, or nil for "everything that changed".
    func presentExport(playlists: [UUID]?, state: AppStateManager) {
        self.state = state
        plan = nil
        resultText = nil
        progress = 0
        isPresented = true
        let tracks = state.tracks
        let hidden = Set(tracks.filter { state.isHiddenFromLibrary($0.id) }.map(\.id))
        let chosen: [Playlist]
        if let playlists {
            chosen = state.playlists.filter { playlists.contains($0.id) }
        } else {
            chosen = state.playlists.filter { !$0.isAppleMusicFavorites }
        }
        let resolved = chosen.map { ($0, state.resolvedTracks(of: $0)) }
        let everything = playlists == nil
        Task { [weak self] in
            let plan = await Task.detached(priority: .userInitiated) {
                Self.makePlan(tracks: tracks, hidden: hidden, playlists: resolved, everything: everything)
            }.value
            self?.plan = plan
        }
    }

    nonisolated private static func hex(_ decimal: String?) -> String? {
        guard let decimal, let value = UInt64(decimal) else { return nil }
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 16 - text.count)) + text
    }

    nonisolated private static func makePlan(tracks: [LocalTrack], hidden: Set<UUID>, playlists: [(Playlist, [LocalTrack])], everything: Bool) -> Plan {
        var plan = Plan()
        let library: ITLibrary
        do {
            library = try ITLibrary(apiVersion: "1.0")
        } catch {
            plan.error = "Mesh Player needs access to your Music library. Allow it in System Settings › Privacy & Security › Media & Apple Music."
            return plan
        }

        var byPath: [String: String] = [:]
        var existingIDs = Set<String>()
        for item in library.allMediaItems {
            let id = hex(item.persistentID.stringValue) ?? ""
            existingIDs.insert(id)
            if let path = item.location?.standardizedFileURL.path { byPath[path] = id }
        }
        var loved = Set<String>()
        var musicPlaylists: [String: (id: String, items: [String], smart: Bool)] = [:]
        var musicPlaylistsByID: [String: (name: String, items: [String])] = [:]
        for playlist in library.allPlaylists {
            let items = playlist.items.map { hex($0.persistentID.stringValue) ?? "" }
            if playlist.distinguishedKind == .kindLovedSongs { loved.formUnion(items); continue }
            guard !playlist.isPrimary, playlist.distinguishedKind == .kindNone, playlist.kind == .regular || playlist.kind == .smart else { continue }
            let pid = hex(playlist.persistentID.stringValue) ?? ""
            if musicPlaylists[playlist.name] == nil {
                musicPlaylists[playlist.name] = (pid, items, playlist.kind == .smart)
            }
            musicPlaylistsByID[pid] = (playlist.name, items)
        }

        func musicID(of track: LocalTrack) -> String? {
            if let id = hex(track.persistentID), existingIDs.contains(id) { return id }
            if let path = track.fileURL?.standardizedFileURL.path { return byPath[path] }
            return nil
        }

        var needed: [UUID: LocalTrack] = [:]
        for track in tracks {
            guard let url = track.fileURL, FileManager.default.fileExists(atPath: url.path) else { continue }
            if let id = musicID(of: track) {
                plan.knownIDs[track.id] = id
            } else if everything && !hidden.contains(track.id) {
                needed[track.id] = track
            }
        }

        for (playlist, songs) in playlists {
            let playable = songs.filter { $0.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
            for song in playable where plan.knownIDs[song.id] == nil { needed[song.id] = song }
            let exportName = playlist.name
            let existing = playlist.appleMusicID.flatMap { hex($0) }.flatMap { id in musicPlaylistsByID[id].map { (id, $0.items) } }
                ?? musicPlaylists[exportName].flatMap { $0.smart ? nil : ($0.id, $0.items) }
            let desiredIDs = playable.map { plan.knownIDs[$0.id] ?? "new-\($0.id)" }
            let current = existing?.1 ?? []
            if existing != nil && desiredIDs == current { continue } // already identical
            let currentSet = Set(current), desiredSet = Set(desiredIDs)
            // When syncing everything, only touch imported playlists that actually differ.
            if everything && playlist.isImported && existing == nil { continue }
            plan.playlists.append(PlaylistChange(
                id: playlist.id,
                name: exportName,
                exists: existing != nil,
                musicPlaylistID: existing?.0,
                desired: playable,
                adds: desiredSet.subtracting(currentSet).count,
                removes: currentSet.subtracting(desiredSet).count
            ))
        }

        plan.songsToAdd = needed.values.sorted { ($0.artist, $0.album, $0.discNumber, $0.trackNumber) < ($1.artist, $1.album, $1.discNumber, $1.trackNumber) }
        if everything {
            plan.toLove = tracks.filter { $0.isFavorite && plan.knownIDs[$0.id].map { !loved.contains($0) } == true }
        }
        return plan
    }

    // MARK: Applying

    func apply() {
        guard var plan, let state, !isApplying else { return }
        plan.songsToAdd.removeAll { plan.skippedAdds.contains($0.id) }
        plan.toLove.removeAll { plan.skippedLoves.contains($0.id) }
        isApplying = true
        progress = 0
        resultText = nil
        Task { [weak self] in
            guard let self else { return }
            var added = 0, failedAdds = 0, playlistsDone = 0, lovedCount = 0
            var newIDs: [UUID: String] = [:]
            let songSteps = plan.includeSongs ? plan.songsToAdd.count : 0
            let playlistSteps = plan.playlists.filter(\.include).reduce(0) { $0 + max(1, $1.desired.count) }
            let loveSteps = plan.includeLoves ? plan.toLove.count : 0
            let totalSteps = Double(max(1, songSteps + playlistSteps + loveSteps))
            var done = 0.0

            // 1. New songs → Music library, 20 files per script.
            if plan.includeSongs {
                for chunk in plan.songsToAdd.chunked(20) {
                    self.progressText = "Adding songs to Music… \(added + failedAdds) of \(plan.songsToAdd.count)"
                    let paths = chunk.map { $0.fileURL?.path ?? "" }
                    let ids = await Self.run(Self.addScript(paths))?.stringList ?? []
                    for (i, track) in chunk.enumerated() {
                        if i < ids.count, !ids[i].isEmpty {
                            newIDs[track.id] = ids[i]
                            plan.knownIDs[track.id] = ids[i]
                            added += 1
                        } else {
                            failedAdds += 1
                        }
                    }
                    done += Double(chunk.count)
                    self.progress = done / totalSteps
                }
            }

            // 2. Playlists, mirrored in Mesh order.
            var playlistIDs: [UUID: String] = [:]
            for change in plan.playlists where change.include {
                self.progressText = "Updating “\(change.name)”…"
                let ids = change.desired.compactMap { plan.knownIDs[$0.id] }
                var first = true
                var musicID = change.musicPlaylistID
                for chunk in (ids.isEmpty ? [[]] : ids.chunked(40)) {
                    let script = Self.playlistScript(name: change.name, playlistID: musicID, clear: first, trackIDs: chunk)
                    if let result = await Self.run(script)?.stringValue, !result.isEmpty { musicID = result }
                    first = false
                    done += Double(max(1, chunk.count))
                    self.progress = done / totalSteps
                }
                if let musicID { playlistIDs[change.id] = musicID }
                playlistsDone += 1
            }

            // 3. Favorites → loved.
            if plan.includeLoves {
                for chunk in plan.toLove.chunked(40) {
                    self.progressText = "Marking favorites as loved…"
                    let ids = chunk.compactMap { plan.knownIDs[$0.id] }
                    if await Self.run(Self.loveScript(ids)) != nil { lovedCount += ids.count }
                    done += Double(chunk.count)
                    self.progress = done / totalSteps
                }
            }

            // Remember the Music IDs so the next sync matches songs and playlists directly.
            state.recordAppleMusicIDs(tracks: newIDs.compactMapValues(Self.decimal), playlists: playlistIDs.compactMapValues(Self.decimal))

            var parts: [String] = []
            if plan.includeSongs { parts.append("\(Fmt.songs(added)) added") }
            if failedAdds > 0 { parts.append("\(failedAdds) the Music app wouldn't accept") }
            if playlistsDone > 0 { parts.append("\(playlistsDone) playlist\(playlistsDone == 1 ? "" : "s") updated") }
            if lovedCount > 0 { parts.append("\(lovedCount) loved") }
            self.resultText = parts.isEmpty ? "Nothing to send." : parts.joined(separator: " · ")
            self.progress = 1
            self.progressText = ""
            self.isApplying = false
            self.plan = nil
        }
    }

    nonisolated private static func decimal(_ hex: String) -> String? {
        UInt64(hex, radix: 16).map { String($0) }
    }

    // MARK: AppleScript

    nonisolated private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated private static func list(_ items: [String]) -> String {
        "{" + items.map(quote).joined(separator: ", ") + "}"
    }

    nonisolated private static func addScript(_ paths: [String]) -> String {
        """
        set out to {}
        repeat with p in \(list(paths))
          try
            set f to POSIX file (p as text)
            tell application "Music"
              set t to add f to library playlist 1
              set end of out to (persistent ID of t)
            end tell
          on error
            set end of out to ""
          end try
        end repeat
        return out
        """
    }

    nonisolated private static func playlistScript(name: String, playlistID: String?, clear: Bool, trackIDs: [String]) -> String {
        let find: String
        if let playlistID {
            find = "set pl to first user playlist whose persistent ID is \(quote(playlistID))"
        } else {
            find = """
            if exists (first user playlist whose name is \(quote(name)) and smart is false) then
                set pl to first user playlist whose name is \(quote(name)) and smart is false
              else
                set pl to make new user playlist with properties {name:\(quote(name))}
              end if
            """
        }
        return """
        tell application "Music"
          try
            \(find)
          on error
            set pl to make new user playlist with properties {name:\(quote(name))}
          end try
          \(clear ? "delete every track of pl" : "")
          repeat with pid in \(list(trackIDs))
            try
              duplicate (first track of library playlist 1 whose persistent ID is (pid as text)) to pl
            end try
          end repeat
          return persistent ID of pl
        end tell
        """
    }

    nonisolated private static func loveScript(_ ids: [String]) -> String {
        """
        tell application "Music"
          repeat with pid in \(list(ids))
            try
              set t to (first track of library playlist 1 whose persistent ID is (pid as text))
              try
                set favorited of t to true
              on error
                set loved of t to true
              end try
            end try
          end repeat
          return "ok"
        end tell
        """
    }

    /// Runs a script on the main thread (NSAppleScript's requirement), yielding between batches.
    private static func run(_ source: String) async -> NSAppleEventDescriptor? {
        await Task.yield()
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { print("Apple Music sync script error: \(error)") }
        return error == nil ? result : nil
    }
}

private extension NSAppleEventDescriptor {
    var stringList: [String] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).map { atIndex($0)?.stringValue ?? "" }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension AppStateManager {
    /// Stores Music persistent IDs learned during a sync (decimal strings, as iTunesLibrary reports them).
    func recordAppleMusicIDs(tracks trackIDs: [UUID: String], playlists playlistIDs: [UUID: String]) {
        if !trackIDs.isEmpty {
            var updated = tracks
            for i in updated.indices { if let id = trackIDs[updated[i].id] { updated[i].persistentID = id } }
            tracks = updated
        }
        if !playlistIDs.isEmpty {
            var updated = playlists
            for i in updated.indices { if let id = playlistIDs[updated[i].id] { updated[i].appleMusicID = id } }
            playlists = updated
        }
    }
}

// MARK: - Sheet

struct AppleMusicSyncSheet: View {
    @ObservedObject var sync = AppleMusicSync.shared
    let theme: ThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accentGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Changes to Apple Music")
                        .font(.system(size: 18, weight: .bold))
                    Text("Review what will change in the Music app.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(20)
            Divider()

            Group {
                if let result = sync.resultText {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(.green)
                        Text(result).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if sync.isApplying {
                    VStack(spacing: 12) {
                        ProgressView(value: sync.progress).frame(width: 300)
                        Text(sync.progressText).font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if let plan = sync.plan {
                    planView(plan)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Comparing with your Music library…").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
            }

            Divider()
            HStack {
                Spacer()
                if sync.resultText != nil {
                    Button("Done") { sync.isPresented = false }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { sync.isPresented = false }
                        .keyboardShortcut(.cancelAction)
                        .disabled(sync.isApplying)
                    Button("Send to Music") { sync.apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(sync.plan == nil || sync.plan?.isEmpty == true || sync.plan?.error != nil || sync.isApplying)
                }
            }
            .padding(16)
        }
        .frame(width: 520)
    }

    @ViewBuilder
    private func planView(_ plan: AppleMusicSync.Plan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = plan.error {
                    Label(error, systemImage: "lock.fill").foregroundStyle(.orange).font(.system(size: 12))
                } else if plan.isEmpty {
                    Label("The Music app is already up to date.", systemImage: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                if !plan.songsToAdd.isEmpty {
                    let chosen = plan.songsToAdd.count - plan.skippedAdds.count
                    Toggle(isOn: binding(\.includeSongs)) {
                        Text("Add \(Fmt.songs(chosen)) to the Music library")
                    }
                    if plan.includeSongs {
                        songPicker(plan.songsToAdd, skipped: \.skippedAdds)
                    }
                }
                if !plan.playlists.isEmpty {
                    Text("Playlists").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textSecondary)
                    ForEach(Array(plan.playlists.enumerated()), id: \.element.id) { index, change in
                        Toggle(isOn: Binding(
                            get: { sync.plan?.playlists[index].include ?? false },
                            set: { sync.plan?.playlists[index].include = $0 }
                        )) {
                            HStack {
                                Text(change.name).lineLimit(1)
                                Spacer()
                                Text(change.exists ? "+\(change.adds)  −\(change.removes)" : "New · \(Fmt.songs(change.desired.count))")
                                    .font(.system(size: 11.5).monospacedDigit())
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                    Text("Playlists are mirrored: the Music playlist ends up with the same songs, in the same order, as in Mesh Player. Songs removed from a playlist stay in your Music library.")
                        .font(.system(size: 11)).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                if !plan.toLove.isEmpty {
                    Toggle("Mark \(Fmt.songs(plan.toLove.count - plan.skippedLoves.count)) from your Favorites as loved", isOn: binding(\.includeLoves))
                    if plan.includeLoves {
                        songPicker(plan.toLove, skipped: \.skippedLoves)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
            .padding(20)
        }
        .frame(height: 440)
    }

    /// A ticked list of songs, so you can leave some out.
    private func songPicker(_ songs: [LocalTrack], skipped: WritableKeyPath<AppleMusicSync.Plan, Set<UUID>>) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Button("Select All") { sync.plan?[keyPath: skipped] = [] }
                    Button("Select None") { sync.plan?[keyPath: skipped] = Set(songs.map(\.id)) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(songs) { track in
                        Toggle(isOn: Binding(
                            get: { !(sync.plan?[keyPath: skipped].contains(track.id) ?? false) },
                            set: { on in
                                if on { sync.plan?[keyPath: skipped].remove(track.id) } else { sync.plan?[keyPath: skipped].insert(track.id) }
                            }
                        )) {
                            HStack(spacing: 4) {
                                Text(track.title).lineLimit(1)
                                Text("— \(track.artist) · \(track.album)")
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.top, 4)
        } label: {
            Text("Choose songs (\(songs.count - (sync.plan?[keyPath: skipped].count ?? 0)) of \(songs.count))")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.leading, 20)
    }

    private func binding(_ keyPath: WritableKeyPath<AppleMusicSync.Plan, Bool>) -> Binding<Bool> {
        Binding(get: { sync.plan?[keyPath: keyPath] ?? false }, set: { sync.plan?[keyPath: keyPath] = $0 })
    }
}
