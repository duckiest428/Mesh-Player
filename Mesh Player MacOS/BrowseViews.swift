//
//  BrowseViews.swift
//  Mesh Player
//
//  Apple Music–style browsing: the artist page, search results, "See All" lists, All Playlists,
//  the shared song / album shelves they use, and the remove-from-library confirmation.
//

import AppKit
import SwiftUI

// MARK: - Removing songs and playlists

extension View {
    /// One confirmation for removing songs or deleting a playlist, with the option to move the
    /// audio files to the Trash as well.
    func removalDialog(state: AppStateManager) -> some View {
        modifier(RemovalDialog(state: state))
    }
}

private struct RemovalDialog: ViewModifier {
    @ObservedObject var state: AppStateManager
    @State private var trashFailures = 0

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: Binding(get: { state.pendingRemoval != nil }, set: { if !$0 { state.pendingRemoval = nil } }), titleVisibility: .visible, presenting: state.pendingRemoval) { removal in
                switch removal {
                case .songs(let tracks):
                    let ids = Set(tracks.map(\.id))
                    Button("Remove from Library") { state.removeFromLibrary(ids, trashFiles: false) }
                    Button("Remove and Move \(tracks.count == 1 ? "File" : "Files") to Trash", role: .destructive) {
                        trashFailures = state.removeFromLibrary(ids, trashFiles: true)
                    }
                    Button("Cancel", role: .cancel) {}
                case .playlist(let playlist):
                    Button("Delete Playlist Only") { state.deletePlaylist(playlist.id, songs: .keep) }
                    Button("Delete Playlist and Remove Its Songs from Library") { state.deletePlaylist(playlist.id, songs: .removeFromLibrary) }
                    Button("Delete Playlist and Move Its Songs to Trash", role: .destructive) { state.deletePlaylist(playlist.id, songs: .moveFilesToTrash) }
                    Button("Cancel", role: .cancel) {}
                }
            } message: { removal in
                switch removal {
                case .songs(let tracks):
                    Text("Removing keeps the \(tracks.count == 1 ? "file" : "files") on disk. Moving to the Trash deletes \(tracks.count == 1 ? "it" : "them") from your Mac too (you can still restore from the Trash).")
                case .playlist(let playlist):
                    let count = state.resolvedTracks(of: playlist).count
                    Text("“\(playlist.name)” has \(Fmt.songs(count)). You can keep them, remove them from your library, or also move their files to the Trash.")
                }
            }
            .alert("Some files couldn't be moved to the Trash", isPresented: Binding(get: { trashFailures > 0 }, set: { if !$0 { trashFailures = 0 } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(trashFailures) \(trashFailures == 1 ? "file" : "files") couldn't be moved. They were still removed from your library.")
            }
    }

    private var title: String {
        switch state.pendingRemoval {
        case .songs(let tracks)?:
            return tracks.count == 1 ? "Remove “\(tracks[0].title)” from your library?" : "Remove \(tracks.count) songs from your library?"
        case .playlist(let playlist)?:
            return "Delete “\(playlist.name)”?"
        case nil:
            return ""
        }
    }
}
