//
//  AnimatedArtworkView.swift
//  AtmosAMPlayer
//
//  Created by Peter Luedtke on 2026-06-25.
//


import SwiftUI
import AppKit
import AVFoundation

struct AnimatedArtworkView: NSViewRepresentable {
    let track: LocalTrack
    let cornerRadius: CGFloat
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.cornerRadius = cornerRadius
        playerLayer.masksToBounds = true
        view.layer?.addSublayer(playerLayer)
        
        context.coordinator.playerLayer = playerLayer
        updatePlayer(for: track, in: context)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.currentTrackId != track.id {
            updatePlayer(for: track, in: context)
        }
        context.coordinator.playerLayer?.frame = nsView.bounds
    }
    
    private func updatePlayer(for track: LocalTrack, in context: Context) {
        context.coordinator.currentTrackId = track.id
        context.coordinator.player?.pause()
        context.coordinator.player = nil
        context.coordinator.playerLayer?.player = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let videoURL = self.findVideoURL(for: track) {
                DispatchQueue.main.async {
                    // Check if track is still the same
                    if context.coordinator.currentTrackId == track.id {
                        let player = AVPlayer(url: videoURL)
                        player.isMuted = true
                        context.coordinator.player = player
                        context.coordinator.playerLayer?.player = player
                        player.play()
                        
                        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                            player.seek(to: .zero)
                            player.play()
                        }
                    }
                }
            }
        }
    }
    
    private func findVideoURL(for track: LocalTrack) -> URL? {
        let extensions = ["mp4", "mov", "m4v"]
        
        if let fileURL = track.fileURL {
            let baseUrl = fileURL.deletingPathExtension()
            for ext in extensions {
                let videoURL = baseUrl.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
        }
        
        if let coverURL = track.localCoverURL {
            let baseUrl = coverURL.deletingPathExtension()
            for ext in extensions {
                let videoURL = baseUrl.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
            
            let dirUrl = coverURL.deletingLastPathComponent()
            for ext in extensions {
                let videoURL = dirUrl.appendingPathComponent("artwork").appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
        }
        
        if let fileURL = track.fileURL {
            let asset = AVAsset(url: fileURL)
            if asset.tracks(withMediaType: .video).count > 0 {
                return fileURL
            }
        }
        
        return nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var currentTrackId: UUID?
    }
}
