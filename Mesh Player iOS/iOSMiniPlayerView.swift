import SwiftUI

struct iOSMiniPlayerView: View {
    @EnvironmentObject var engine: iOSAudioEngine
    @ObservedObject var appState: iOSAppState
    
    @State private var showFullPlayer = false
    
    var body: some View {
        if let currentSong = appState.currentSong {
            VStack(spacing: 0) {
                // Divider
                Divider()
                
                HStack(spacing: 12) {
                    // Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.systemGray5))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "music.note")
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentSong.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(currentSong.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        appState.isPlaying.toggle()
                        engine.togglePlayPause()
                    }) {
                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: {}) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .onTapGesture {
                    showFullPlayer = true
                }
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                iOSFullPlayerView(appState: appState)
            }
        }
    }
}
