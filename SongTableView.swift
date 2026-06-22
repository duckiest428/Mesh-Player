//
//  SongTableView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI

struct SongTableView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Search, dynamic sorting, and filter header strip
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search songs, artists, or albums...", text: $state.searchKeyword)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 300)
                
                Spacer()
                
                // Dynamic Sorting Picker Mirror
                HStack(spacing: 4) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Menu {
                        ForEach(["dateAdded", "title", "artist", "album", "playCount", "duration"], id: \.self) { criterion in
                            Button(action: { state.sortCriteria = criterion }) {
                                HStack {
                                    Text(getCriteriaLabel(criterion))
                                    if state.sortCriteria == criterion {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(getCriteriaLabel(state.sortCriteria))
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 140, alignment: .leading)
                }
                
                // Dynamic Sorting Order direction toggle
                Button(action: { state.sortAscending.toggle() }) {
                    Image(systemName: state.sortAscending ? "arrow.up" : "arrow.down")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .help("Toggle sorting direction")
            }
            .padding()
            .background(Color.secondary.opacity(0.04))
            
            Divider()
            
            // Custom Song List Grid with dynamic Column Headers
            List {
                // Table header row Simulation matching state preferences with clickable sort gestures
                HStack {
                    Text(state.sortCriteria == "title" ? "Title \(state.sortAscending ? "▲" : "▼")" : "Title")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(state.sortCriteria == "title" ? state.theme.accent : state.theme.textSecondary)
                        .frame(width: 220, alignment: .leading)
                        .onTapGesture {
                            if state.sortCriteria == "title" {
                                state.sortAscending.toggle()
                            } else {
                                state.sortCriteria = "title"
                            }
                        }
                    
                    if state.showArtistColumn {
                        Text(state.sortCriteria == "artist" ? "Artist \(state.sortAscending ? "▲" : "▼")" : "Artist")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "artist" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 120, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "artist" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "artist"
                                }
                            }
                    }
                    
                    if state.showAlbumColumn {
                        Text(state.sortCriteria == "album" ? "Album \(state.sortAscending ? "▲" : "▼")" : "Album")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "album" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 140, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "album" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "album"
                                }
                            }
                    }
                    
                    if state.showGenreColumn {
                        Text(state.sortCriteria == "genre" ? "Genre \(state.sortAscending ? "▲" : "▼")" : "Genre")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "genre" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 80, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "genre" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "genre"
                                }
                            }
                    }
                    
                    if state.showPlaysColumn {
                        Text(state.sortCriteria == "playCount" ? "Plays \(state.sortAscending ? "▲" : "▼")" : "Plays")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "playCount" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 80, alignment: .center)
                            .onTapGesture {
                                if state.sortCriteria == "playCount" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "playCount"
                                }
                            }
                    }
                    
                    if state.showDateAddedColumn {
                        Text(state.sortCriteria == "dateAdded" ? "Date Added \(state.sortAscending ? "▲" : "▼")" : "Date Added")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "dateAdded" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 90, alignment: .leading)
                            .onTapGesture {
                                if state.sortCriteria == "dateAdded" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "dateAdded"
                                }
                            }
                    }
                    
                    if state.showFormatColumn {
                        Text(state.sortCriteria == "format" ? "Format \(state.sortAscending ? "▲" : "▼")" : "Format")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "format" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 60, alignment: .center)
                            .onTapGesture {
                                if state.sortCriteria == "format" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "format"
                                }
                            }
                    }
                    
                    Spacer()
                    
                    if state.showFavoritesColumn {
                        Text(state.sortCriteria == "favourites" || state.sortCriteria == "favorites" ? "Fav \(state.sortAscending ? "▲" : "▼")" : "Fav")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "favourites" || state.sortCriteria == "favorites" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 40, alignment: .center)
                            .onTapGesture {
                                if state.sortCriteria == "favourites" || state.sortCriteria == "favorites" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "favourites"
                                }
                            }
                    }
                    
                    if state.showTimeColumn {
                        Text(state.sortCriteria == "duration" ? "Time \(state.sortAscending ? "▲" : "▼")" : "Time")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.sortCriteria == "duration" ? state.theme.accent : state.theme.textSecondary)
                            .frame(width: 50, alignment: .trailing)
                            .onTapGesture {
                                if state.sortCriteria == "duration" {
                                    state.sortAscending.toggle()
                                } else {
                                    state.sortCriteria = "duration"
                                }
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                
                Divider()
                
                ForEach(state.filteredTracks) { track in
                    let isPlayingThis = engine.currentTrack?.id == track.id
                    
                    HStack {
                        // Title block with alignment play spacer (artwork completely removed as requested)
                        HStack(spacing: 8) {
                            if isPlayingThis {
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundColor(state.theme.accent)
                                    .font(.system(size: 10))
                                    .frame(width: 14)
                            } else {
                                Spacer()
                                    .frame(width: 14)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .fontWeight(isPlayingThis ? .bold : .regular)
                                    .foregroundColor(isPlayingThis ? state.theme.accent : state.theme.textPrimary)
                                    .lineLimit(1)
                                
                                if !state.showArtistColumn {
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundColor(state.theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(width: 220, alignment: .leading)
                        
                        // Dynamic rendering of configured columns
                        if state.showArtistColumn {
                            Text(track.artist)
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                        }
                        
                        if state.showAlbumColumn {
                            Text(track.album)
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                        }
                        
                        if state.showGenreColumn {
                            Text(track.genre)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 80, alignment: .leading)
                        }
                        
                        if state.showPlaysColumn {
                            Text("\(formatNumber(track.playCount)) plays")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(state.currentThemeName == "Classic Light" ? 0.05 : 0.2))
                                .cornerRadius(4)
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 80, alignment: .center)
                        }
                        
                        if state.showDateAddedColumn {
                            Text(formatDate(track.dateAdded))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 90, alignment: .leading)
                        }
                        
                        if state.showFormatColumn {
                            if track.isAtmos {
                                Text("ATMOS")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(4)
                                    .frame(width: 60, alignment: .center)
                            } else {
                                Text(track.format)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(state.theme.textSecondary.opacity(0.6))
                                    .frame(width: 60, alignment: .center)
                            }
                        }
                        
                        Spacer()
                        
                        if state.showFavoritesColumn {
                            Button(action: {
                                state.toggleFavorite(track: track)
                            }) {
                                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                                    .foregroundColor(track.isFavorite ? .red : state.theme.textSecondary.opacity(0.5))
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40, alignment: .center)
                            .help(track.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        }
                        
                        if state.showTimeColumn {
                            Text(formatTime(track.duration))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(state.theme.textSecondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        track.id == state.selectedTrackId
                        ? state.theme.accent.opacity(0.12)
                        : (isPlayingThis ? state.theme.accent.opacity(0.06) : Color.clear)
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        engine.playTrack(track)
                    }
                    .onTapGesture(count: 1) {
                        state.selectedTrackId = track.id
                    }
                }
            }
            .listStyle(.inset)
        }
    }
    
    private func getCriteriaLabel(_ key: String) -> String {
        switch key {
        case "dateAdded": return "Date Added"
        case "title": return "Song Title"
        case "artist": return "Artist Name"
        case "album": return "Album Name"
        case "playCount": return "Plays Count"
        case "duration": return "Song Duration"
        default: return key.capitalized
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTime(_ sec: TimeInterval) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
