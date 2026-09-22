import SwiftUI

struct iOSSearchView: View {
    @EnvironmentObject var engine: iOSAudioEngine
    @ObservedObject var appState: iOSAppState
    @State private var searchText = ""
    
    // 1. searchResults should ONLY handle data logic, not UI
    var searchResults: [iOSSong] {
        if searchText.isEmpty {
            return []
        } else {
            return appState.recentlyAddedSongs.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // 2. All UI code must live inside the body
    var body: some View {
        NavigationView {
            Group {
                if searchText.isEmpty {
                    // Default Browse View
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text("Browse Categories")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                                .padding(.top, 16)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                NavigationLink(destination: GenericListView(title: "Pop")) {
                                    CategoryCard(title: "Pop", color: .pink)
                                }
                                NavigationLink(destination: GenericListView(title: "Hip-Hop")) {
                                    CategoryCard(title: "Hip-Hop", color: .orange)
                                }
                                NavigationLink(destination: GenericListView(title: "Electronic")) {
                                    CategoryCard(title: "Electronic", color: .purple)
                                }
                                NavigationLink(destination: GenericListView(title: "Classical")) {
                                    CategoryCard(title: "Classical", color: .blue)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                } else {
                    // Active Search View
                    List {
                        if searchResults.isEmpty {
                            Text("No results found for \"\(searchText)\"")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(searchResults) { song in
                                iOSSongRow(song: song)
                                    .onTapGesture {
                                        appState.currentSong = song
                                        appState.isPlaying = true
                                        engine.playSong(song)
                                    }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Songs, Artists, Albums")
        }
    }
}

// 3. CategoryCard needs a body to conform to View
struct CategoryCard: View {
    let title: String
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .aspectRatio(2/1, contentMode: .fit)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}
