//
//  LibraryView.swift
//  Mesh Player
//
//  Created by Peter Luedtke on 2026-07-12.
//


import SwiftUI
import UIKit

struct LibraryView: View {
    @ObservedObject var appState: iOSAppState
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Navigation Rows
                    VStack(spacing: 0) {
                        LibraryNavigationRow(icon: "music.note.list", title: "Playlists", color: .red, appState: appState)
                        LibraryNavigationRow(icon: "music.note", title: "Songs", color: .pink, appState: appState)
                        LibraryNavigationRow(icon: "square.stack", title: "Albums", color: .purple, appState: appState)
                        LibraryNavigationRow(icon: "music.mic", title: "Artists", color: .indigo, appState: appState)
                        LibraryNavigationRow(icon: "guitars", title: "Genres", color: .blue, appState: appState)
                        LibraryNavigationRow(icon: "arrow.down.circle", title: "Downloaded", color: .teal, appState: appState)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)

                    // Recently Added Header
                    HStack {
                        Text("Recently Added")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    
                    // Grid for Recently Added Albums
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(appState.recentlyAddedAlbums) { album in
                            RecentlyAddedItemView(album: album)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        
                        Menu {
                            Button(action: {}) { Label("New Playlist", systemImage: "music.note.list") }
                            Button(action: {}) { Label("New Smart Playlist", systemImage: "gearshape") }
                            Button(action: {}) { Label("New Folder", systemImage: "folder") }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "text.badge.plus")
                                Image(systemName: "chevron.down")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                        }
                        .foregroundColor(.primary)

                        
                        Button(action: {
                            showingSettings = true
                        }) {
                            Text("PL")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.gray)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                iOSSettingsView()
            }
            // Apply iOS style background if desired
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
}

struct LibraryNavigationRow: View {
    let icon: String
    let title: String
    let color: Color
    let appState: iOSAppState
    
    var body: some View {
        VStack(spacing: 0) {
            if title == "Songs" {
                NavigationLink(destination: iOSSongsListView(appState: appState)) {
                    RowContent
                }
            } else {
                NavigationLink(destination: GenericListView(title: title)) {
                    RowContent
                }
            }
            
            Divider()
                .padding(.leading, 48) // Align with text
        }
    }
    
    private var RowContent: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32) // Keep icons aligned
            
            Text(title)
                .font(.title3)
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 12)
    }
}

struct RecentlyAddedItemView: View {
    let album: iOSAlbum
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Album Art Placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1.0, contentMode: .fit)
                
                if let art = album.artwork {
                    Image(uiImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .cornerRadius(12)
                } else {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                
                // Shadow for depth
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(album.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct RecentlyAddedSongView: View {
    let song: iOSSong
    
    var body: some View {
        HStack(spacing: 12) {
            // Placeholder art for song
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "music.note")
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if song.hasLossless {
                        iOSAudioQualityBadge(qualityType: .lossless)
                    }
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: {
                // Play action
            }) {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GenericListView: View {
    let title: String
    
    var items: [String] {
        switch title {
        case "Playlists": return ["Favorites", "Driving", "Chill", "Workout"]
        case "Albums": return ["Midnight Drives", "Acoustic Sessions", "Beat Tape Vol 2"]
        case "Artists": return ["Synthwave Hero", "The Folks", "Lo-Fi Beats", "London Symphony"]
        case "Genres": return ["Electronic", "Acoustic", "Lo-Fi", "Classical"]
        case "Downloaded": return ["Night Drive", "Acoustic Fire", "Chill Vibe"]
        default: return []
        }
    }
    
    var body: some View {
        List {
            ForEach(items, id: \.self) { item in
                HStack {
                    if title == "Playlists" || title == "Albums" {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
                    } else if title == "Artists" {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                    }
                    
                    Text(item)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
