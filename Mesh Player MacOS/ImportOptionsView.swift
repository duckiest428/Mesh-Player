//
//  ImportOptionsView.swift
//  Mesh Player
//
//  Lets the user choose what an Apple Music import brings over, with a live look at what the
//  Music library actually contains.
//

import SwiftUI

struct AppleMusicImportSheet: View {
    @ObservedObject var state: AppStateManager
    @Environment(\.dismiss) private var dismiss

    @State private var options = AppleMusicImportOptions.saved
    @State private var preview: AppleMusicPreview?
    @State private var selected = Set<String>()
    @State private var loadedSelection = false

    var body: some View {
        let theme = state.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accentGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Apple Music")
                        .font(.system(size: 18, weight: .bold))
                    Text(summaryLine)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = preview?.error {
                        Label(error, systemImage: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    group("Music") {
                        option("Downloaded songs", detail: preview.map { "\(Fmt.count($0.downloadedSongs)) songs on this Mac" }, isOn: $options.songs)
                        option("Music videos", detail: preview.map { "\(Fmt.count($0.musicVideos)) videos (played as audio)" }, isOn: $options.musicVideos)
                        option("Also scan the Music folder", detail: "Picks up files the Music app doesn't list, like Dolby Atmos .mp4 downloads", isOn: $options.scanMediaFolder)
                            .disabled(!options.songs)
                    }

                    group("Your listening") {
                        option("Loved songs → Favorites", detail: preview.map { "\(Fmt.count($0.lovedSongs)) loved" }, isOn: $options.lovedSongs)
                        option("Play counts and last played dates", detail: preview.map { "\(Fmt.count($0.playedSongs)) songs have plays" }, isOn: $options.playCounts)
                        option("Keep the date each song was added", detail: "Otherwise new songs count as added today", isOn: $options.dateAdded)
                    }

                    group("Playlists") {
                        option("Playlists", detail: preview.map { "\($0.playlists.count) playlists with downloaded songs" }, isOn: $options.playlists)
                        if options.playlists, let lists = preview?.playlists, !lists.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Button("Select All") { selected = Set(lists.map(\.name)) }
                                    Button("Select None") { selected = [] }
                                    Spacer()
                                    Text("\(selected.count) of \(lists.count) selected")
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .font(.system(size: 11.5))
                                .buttonStyle(.link)
                                .padding(.bottom, 6)
                                ForEach(lists, id: \.name) { item in
                                    Toggle(isOn: Binding(
                                        get: { selected.contains(item.name) },
                                        set: { if $0 { selected.insert(item.name) } else { selected.remove(item.name) } }
                                    )) {
                                        HStack {
                                            Text(item.name).lineLimit(1)
                                            Spacer()
                                            Text(Fmt.songs(item.count)).foregroundStyle(theme.textTertiary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .padding(.vertical, 3)
                                }
                            }
                            .padding(12)
                            .card(theme, radius: 10)
                            option("Hide imported playlists' songs from the library", detail: "They'll only appear inside their playlists", isOn: $options.hideImportedPlaylistSongs)
                        }
                    }

                    if let preview, preview.cloudOnly + preview.protected > 0 {
                        Text("\(Fmt.count(preview.cloudOnly)) cloud-only and \(Fmt.count(preview.protected)) protected items can't be imported. Download songs in the Music app first.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .frame(height: 430)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { startImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!options.songs && !options.musicVideos && !options.playlists && !options.lovedSongs)
            }
            .padding(16)
        }
        .frame(width: 520)
        .task {
            let result = await LibraryImporter.shared.previewAppleMusicLibrary()
            preview = result
            if !loadedSelection {
                loadedSelection = true
                let names = Set(result.playlists.map(\.name))
                selected = options.selectedPlaylists.map { $0.intersection(names) } ?? names
            }
        }
    }

    private var summaryLine: String {
        guard let preview else { return "Reading your Music library…" }
        if preview.error != nil { return "Music library access is needed" }
        return "\(Fmt.songs(preview.downloadedSongs)) · \(preview.playlists.count) playlists"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(state.theme.textSecondary)
            content()
        }
    }

    private func option(_ title: String, detail: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(state.theme.textTertiary)
                }
            }
        }
    }

    private func startImport() {
        var final = options
        let all = Set(preview?.playlists.map(\.name) ?? [])
        final.selectedPlaylists = (selected == all || all.isEmpty) ? nil : selected
        AppleMusicImportOptions.saved = final
        dismiss()
        LibraryImporter.shared.importAppleMusicLibrary(into: state, options: final)
    }
}
