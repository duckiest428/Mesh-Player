import SwiftUI

struct AudioQualityPopup: View {
    let track: LocalTrack
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 8) {
            // 1. Audio Format
            Text(track.isAtmos ? "Dolby Atmos" : (track.format == "Lossless" ? "Lossless" : track.format.uppercased()))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            // 2. Audio format notes
            Text(track.isAtmos ? "Spatial Audio with Dolby Atmos" : (track.format == "Lossless" ? "Apple Lossless Audio Codec" : "Advanced Audio Coding"))
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
                Text("Sample Rate: \(sampleRateStr) / \(bitRateStr)")
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
    
    var body: some View {
        HStack(spacing: 4) {
            if track.isAtmos {
                Button(action: {
                    showingPopover = true
                }) {
                    DolbyAtmosBadge(color: .blue, scale: 0.85, showText: true)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else if track.format == "Lossless" {
                Button(action: {
                    showingPopover = true
                }) {
                    Text("Lossless")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                Button(action: {
                    showingPopover = true
                }) {
                    Text(track.format)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.cardBackground)
                        .foregroundColor(theme.textSecondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            AudioQualityPopup(track: track)
        }
    }
}
