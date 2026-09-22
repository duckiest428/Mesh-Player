//
//  iOSAlbum.swift
//  Mesh Player
//
//  Created by Peter Luedtke on 2026-07-12.
//


import SwiftUI
import UIKit
public import Combine

// Simplified models for the iOS app to build upon
struct iOSAlbum: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let artwork: UIImage?
}

struct iOSSong: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let duration: TimeInterval
    let fileURL: URL?
    let hasLossless: Bool
    let lyrics: String?
    var playCount: Int = 0
}

import AVFoundation

class iOSAppState: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    @Published var recentlyAddedAlbums: [iOSAlbum] = []
    @Published var recentlyAddedSongs: [iOSSong] = []
    
    @Published var currentSong: iOSSong?
    @Published var isPlaying: Bool = false
    
    init() {
        scanDocumentsDirectory()
    }
    
    func scanDocumentsDirectory() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            
            let audioExtensions = ["mp3", "m4a", "wav", "flac", "alac", "m4b", "aac", "mp4", "ogg"]
            var newSongs: [iOSSong] = []
            
            if let enumerator = fileManager.enumerator(at: docsURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                        let asset = AVAsset(url: fileURL)
                        var title = fileURL.deletingPathExtension().lastPathComponent
                        var artist = "Unknown Artist"
                        var duration: TimeInterval = CMTimeGetSeconds(asset.duration)
                        if duration.isNaN { duration = 0.0 }
                        
                        for format in asset.availableMetadataFormats {
                            for item in asset.metadata(forFormat: format) {
                                if let commonKey = item.commonKey {
                                    switch commonKey {
                                    case .commonKeyTitle:
                                        if let val = item.stringValue { title = val }
                                    case .commonKeyArtist:
                                        if let val = item.stringValue { artist = val }
                                    default:
                                        break
                                    }
                                }
                            }
                        }
                        
                        let newSong = iOSSong(
                            title: title,
                            artist: artist,
                            duration: duration,
                            fileURL: fileURL,
                            hasLossless: fileURL.pathExtension.lowercased() == "alac" || fileURL.pathExtension.lowercased() == "flac" || fileURL.pathExtension.lowercased() == "wav",
                            lyrics: nil,
                            playCount: 0
                        )
                        newSongs.append(newSong)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.recentlyAddedSongs = newSongs
            }
        }
    }
}
