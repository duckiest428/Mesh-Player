//
//  PlaylistViews.swift
//  Mesh Player
//
//  Playlist cover art, the playlist details / smart rules editor, and helpers shared by the
//  sidebar and the playlist page.
//

import AppKit
import SwiftUI
internal import UniformTypeIdentifiers

/// A playlist's cover: its custom image when one is set, otherwise a mosaic of its albums.
struct PlaylistCover: View {
    let playlist: Playlist
    let tracks: [LocalTrack]
    let state: AppStateManager
    let theme: ThemeColor

    @State private var custom: NSImage?

    var body: some View {
        let url = state.playlistArtworkURL(playlist)
        ZStack {
            if let custom {
                Image(nsImage: custom).resizable().scaledToFill()
            } else if playlist.isSmart && tracks.isEmpty {
                ArtworkPlaceholder(seed: playlist.name, symbol: "gearshape.fill")
            } else if playlist.isAppleMusicFavorites && tracks.isEmpty {
                ArtworkPlaceholder(seed: "favorites", symbol: "heart.fill")
            } else {
                PlaylistMosaic(tracks: tracks, theme: theme)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: url) {
            guard let url else { custom = nil; return }
            custom = await Task.detached(priority: .userInitiated) { ArtworkStore.downsample(url: url, maxPixel: 600) }.value
        }
    }
}

/// Edit a playlist's name, description, cover, library visibility and (for smart playlists) rules.
struct PlaylistEditorSheet: View {
    @ObservedObject var state: AppStateManager
    let playlist: Playlist
    var isNew = false
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var details = ""
    @State private var hideFromLibrary = false
    @State private var rules = SmartPlaylistRules()
    @State private var limitEnabled = false
    @State private var limitValue = 25
    @State private var loaded = false

    var body: some View {
        let theme = state.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    PlaylistCover(playlist: currentPlaylist, tracks: state.resolvedTracks(of: currentPlaylist), state: state, theme: theme)
                        .frame(width: 132, height: 132)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                    HStack(spacing: 6) {
                        Button("Choose…", action: chooseArtwork)
                        if currentPlaylist.artworkFileName != nil {
                            Button("Reset") { state.setPlaylistArtwork(playlist.id, from: nil) }
                        }
                    }
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: playlist.isSmart ? (isNew ? "New Smart Playlist" : "Smart Playlist") : "Playlist Details", color: theme.accent)
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .semibold))
                    TextField("Description (optional)", text: $details, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    if !playlist.isSmart {
                        Toggle(isOn: $hideFromLibrary) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide this playlist's songs from my library")
                                Text("They stay in this playlist but won't appear in Songs, Albums, Artists, Genres or Home.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)

            if playlist.isSmart {
                Divider()
                smartRulesEditor(theme)
                    .padding(20)
            }

            Divider()
            HStack {
                if playlist.isSmart {
                    Text("\(Fmt.songs(rules.evaluate(state.libraryTracks, seed: playlist.id).count)) match")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    if isNew { state.deletePlaylist(playlist.id) }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: playlist.isSmart ? 620 : 520)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = playlist.name
            details = playlist.description
            hideFromLibrary = playlist.hidesSongsFromLibrary
            if let r = playlist.smartRules {
                rules = r
                limitEnabled = r.limit != nil
                limitValue = r.limit ?? 25
            }
        }
    }

    private var currentPlaylist: Playlist {
        state.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    @ViewBuilder
    private func smartRulesEditor(_ theme: ThemeColor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Match")
                Picker("", selection: $rules.matchAll) {
                    Text("all").tag(true)
                    Text("any").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                Text("of the following rules:")
            }
            ForEach($rules.rules) { $rule in
                SmartRuleRow(rule: $rule, canRemove: rules.rules.count > 1) {
                    rules.rules.removeAll { $0.id == rule.id }
                } onAdd: {
                    if let idx = rules.rules.firstIndex(where: { $0.id == rule.id }) {
                        rules.rules.insert(SmartRule(), at: idx + 1)
                    }
                }
            }
            HStack(spacing: 6) {
                Toggle("Limit to", isOn: $limitEnabled).toggleStyle(.checkbox)
                TextField("", value: $limitValue, format: .number)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!limitEnabled)
                Text("songs selected by")
                Picker("", selection: $rules.limitOrder) {
                    ForEach(SmartPlaylistRules.LimitOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!limitEnabled)
            }
            .padding(.top, 4)
        }
        .font(.system(size: 12.5))
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Cover"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { state.setPlaylistArtwork(playlist.id, from: url) }
        }
    }

    private func save() {
        var finalRules = rules
        finalRules.limit = limitEnabled ? max(1, limitValue) : nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        state.updatePlaylist(playlist.id) { p in
            p.name = trimmed
            p.description = details
            if p.isSmart {
                p.smartRules = finalRules
            } else {
                p.excludeFromLibrary = hideFromLibrary
            }
        }
        if isNew { state.selectedTab = "playlist-\(playlist.id.uuidString)" }
        dismiss()
    }
}

private struct SmartRuleRow: View {
    @Binding var rule: SmartRule
    let canRemove: Bool
    let onRemove: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { rule.field }, set: { field in
                rule.field = field
                let ops = SmartRule.Op.options(for: field.kind)
                if !ops.contains(rule.op) { rule.op = ops[0] }
                if field.kind == .date && rule.number == 0 { rule.number = 30 }
            })) {
                ForEach(SmartRule.Field.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("", selection: $rule.op) {
                ForEach(SmartRule.Op.options(for: rule.field.kind)) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)

            switch rule.field.kind {
            case .text:
                TextField(rule.field == .quality ? "e.g. Lossless, Dolby Atmos" : "Value", text: $rule.text)
                    .textFieldStyle(.roundedBorder)
            case .number:
                TextField("", value: $rule.number, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Spacer(minLength: 0)
            case .date:
                TextField("", value: $rule.number, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("days")
                Spacer(minLength: 0)
            case .bool:
                Spacer(minLength: 0)
            }

            Button(action: onRemove) { Image(systemName: "minus") }
                .disabled(!canRemove)
            Button(action: onAdd) { Image(systemName: "plus") }
        }
        .controlSize(.small)
    }
}
