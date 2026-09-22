import SwiftUI

enum SortType {
    case title, artist, duration
}

struct iOSSongsListView: View {
    @EnvironmentObject var engine: iOSAudioEngine
    @ObservedObject var appState: iOSAppState
    @State private var searchText = ""
    @State private var sortType: SortType = .title
    
    var filteredAndSortedSongs: [iOSSong] {
        let filtered = searchText.isEmpty ? appState.recentlyAddedSongs : appState.recentlyAddedSongs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted {
            switch sortType {
            case .title: return $0.title < $1.title
            case .artist: return $0.artist < $1.artist
            case .duration: return $0.duration < $1.duration
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Play and Shuffle Buttons
                HStack(spacing: 16) {
                    Button(action: {
                        if let first = filteredAndSortedSongs.first {
                            appState.currentSong = first
                            appState.isPlaying = true
                            engine.playSong(first)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if let random = filteredAndSortedSongs.randomElement() {
                            appState.currentSong = random
                            appState.isPlaying = true
                            engine.playSong(random)
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Songs List
                LazyVStack(spacing: 0) {
                    ForEach(filteredAndSortedSongs) { song in
                        iOSSongRow(song: song)
                            .onTapGesture {
                                appState.currentSong = song
                                appState.isPlaying = true
                                engine.playSong(song)
                            }
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Songs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Picker("Sort By", selection: $sortType) {
                            Text("Title").tag(SortType.title)
                            Text("Artist").tag(SortType.artist)
                            Text("Duration").tag(SortType.duration)
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    Button(action: {}) {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

struct iOSSongRow: View {
    let song: iOSSong
    
    var body: some View {
        HStack(spacing: 16) {
            // Album Art
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "music.note")
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            
            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 20) {
                Button(action: {}) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.secondary)
                }
                
                
                Menu {
                    Button(action: {}) { Label("Play Next", systemImage: "text.insert") }
                    Button(action: {}) { Label("Play Later", systemImage: "text.append") }
                    Button(action: {}) { Label("Add to a Playlist...", systemImage: "text.badge.plus") }
                    Button(action: {}) { Label("Favorite", systemImage: "star") }
                    Button(action: {}) { Label("Share", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                }

            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        
        Divider()
            .padding(.leading, 82)
    }
}
