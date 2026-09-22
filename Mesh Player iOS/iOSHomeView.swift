//
//  iOSHomeView.swift
//  Mesh Player
//
//  Created by Peter Luedtke on 2026-07-12.
//


import SwiftUI

struct iOSHomeView: View {
    @ObservedObject var appState: iOSAppState
    
    // Derived statistics from appState (simulated for now, as we use mocked data mostly)
    var totalSongs: Int {
        appState.recentlyAddedSongs.count
    }
    
    var totalArtists: Int {
        Set(appState.recentlyAddedSongs.map { $0.artist }).count
    }
    
    var totalGenres: Int {
        // Mock genres count
        4
    }
    
    var recommendedSongs: [iOSSong] {
        // Just shuffling the available songs for now
        appState.recentlyAddedSongs.shuffled().prefix(5).map { $0 }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Statistics Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Library Stats")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                StatCard(title: "Songs", value: "\(totalSongs)", icon: "music.note", color: .pink)
                                StatCard(title: "Artists", value: "\(totalArtists)", icon: "person.fill", color: .indigo)
                                StatCard(title: "Genres", value: "\(totalGenres)", icon: "guitars.fill", color: .blue)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Recommendations Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Made For You")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        LazyVStack(spacing: 0) {
                            ForEach(recommendedSongs) { song in
                                iOSSongRow(song: song)
                                    .onTapGesture {
                                        appState.currentSong = song
                                        appState.isPlaying = true
                                    }
                            }
                        }
                    }
                    
                    // Recently Played or Top Played could go here...
                }
                .padding(.top, 16)
                .padding(.bottom, 100) // Space for mini player
            }
            .navigationTitle("Home")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 120, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}
