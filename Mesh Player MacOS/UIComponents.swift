import AppKit
import CoreGraphics
import SwiftUI

// MARK: - PremiumButtonStyle.swift
//
//  PremiumButtonStyle.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-22.
//  SPDX-License-Identifier: Apache-2.0
//


struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PremiumButtonWrapper(configuration: configuration)
    }
}

private struct PremiumButtonWrapper: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : (isHovered ? 1.12 : 1.0))
            .opacity(configuration.isPressed ? 0.75 : (isHovered ? 1.0 : 0.88))
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: configuration.isPressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isHovered)
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - AudioQualityTags.swift
struct AudioQualityPopup: View {
    let track: LocalTrack
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 8) {
            // 1. Audio Format
            Text(track.isAtmos ? "Dolby Atmos" : track.format)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            // 2. Audio format notes
            Text(track.isAtmos ? "Spatial Audio with Dolby Atmos" : (track.format.localizedCaseInsensitiveContains("lossless") ? "Apple Lossless Audio Codec" : (track.format.hasPrefix("MP3") ? "MPEG-1 Audio Layer III" : "Advanced Audio Coding")))
                .font(.system(size: 11))
                .italic()
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            // 3. Channels
            if track.isAtmos {
                Text("Channels: Spatial Audio")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            } else if let channels = track.channels {
                Text("Channels: \(channels == 2 ? "Stereo" : (channels == 1 ? "Mono" : "\(channels)"))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Channels: Stereo")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 4. Sample Rate & Bitrate
            if !track.isAtmos {
                let sampleRateStr = track.sampleRate != nil ? String(format: "%.1f kHz", track.sampleRate! / 1000.0) : "44.1 kHz"
                let bitRateStr = track.bitRate != nil ? "\(track.bitRate!) kbps" : "256 kbps"
                let depthStr = track.bitDepth.map { "\($0)-bit / " } ?? ""
                Text("\(depthStr)\(sampleRateStr) / \(bitRateStr)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Sample Rate: 48.0 kHz / 768 kbps")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 5. Thin Divider Line
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)
            
            // 6. "Audio Settings" action button
            Button(action: {}) {
                Text("Audio Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            
            // 7. Thin Divider Line
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)
            
            // 8. "OK" dismiss button
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(20)
        .frame(width: 240)
        .background(Color(white: 0.15))
        .cornerRadius(12)
    }
}

struct AudioQualityTagsView: View {
    let track: LocalTrack
    let theme: ThemeColor
    @State private var showingPopover = false
    @State private var hovering = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            Group {
                if track.isAtmos {
                    DolbyAtmosBadge(color: theme.textSecondary, scale: 0.8, showText: true)
                } else if track.format.localizedCaseInsensitiveContains("lossless") {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform").font(.system(size: 8.5, weight: .bold))
                        Text(track.format.localizedCaseInsensitiveContains("hi-res") ? "Hi-Res Lossless" : "Lossless")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.hover, in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(track.format)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.hover, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .opacity(hovering ? 1 : 0.85)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Audio quality")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            AudioQualityPopup(track: track)
        }
    }
}
