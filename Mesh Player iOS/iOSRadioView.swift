//
//  iOSRadioView.swift
//  Mesh Player
//
//  Created by Peter Luedtke on 2026-07-12.
//


import SwiftUI

struct iOSRadioView: View {
    @ObservedObject var appState: iOSAppState
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Featured Stations")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                RadioStationCard(title: "Mesh 1", subtitle: "Today's Hits", color: .purple)
                                RadioStationCard(title: "Mesh Chill", subtitle: "Lo-Fi & Acoustic", color: .blue)
                                RadioStationCard(title: "Mesh Workout", subtitle: "High Energy", color: .orange)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                RadioStationCard(title: "Synthwave Radio", subtitle: "Electronic", color: .pink)
                                RadioStationCard(title: "Classic Rock", subtitle: "70s & 80s", color: .gray)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .navigationTitle("Radio")
        }
    }
}

struct RadioStationCard: View {
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 160, height: 160)
                .overlay(
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))
                )
            
            Text(title)
                .font(.headline)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(width: 160)
    }
}
