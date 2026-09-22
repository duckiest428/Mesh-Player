import SwiftUI
import AVKit

struct iOSFullPlayerView: View {
    @EnvironmentObject var engine: iOSAudioEngine
    @ObservedObject var appState: iOSAppState
    @Environment(\.presentationMode) var presentationMode
    @State private var showingLyrics = false
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(white: 0.15), Color(white: 0.05)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            if let song = appState.currentSong {
                VStack(spacing: 0) {
                    // Pull down indicator
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                    
                    // Header
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Text("Now Playing")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Menu {
                            Button(action: {}) { Label("Play Next", systemImage: "text.insert") }
                            Button(action: {}) { Label("Play Later", systemImage: "text.append") }
                            Button(action: {}) { Label("Add to a Playlist...", systemImage: "text.badge.plus") }
                            Button(action: {}) { Label("Share", systemImage: "square.and.arrow.up") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44) // Bigger tap target
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                    
                    // Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.9))
                            .aspectRatio(1.0, contentMode: .fit)
                        
                        Image(systemName: "music.note")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(80)
                            .foregroundColor(Color.gray.opacity(0.5))
                    }
                    .padding(.horizontal, 32)
                    .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 20)
                    
                    Spacer()
                    
                    // Song Info
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(song.artist)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Image(systemName: "star")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.trailing, 8)
                        
                        Menu {
                            Button(action: {}) { Label("Play Next", systemImage: "text.insert") }
                            Button(action: {}) { Label("Play Later", systemImage: "text.append") }
                            Button(action: {}) { Label("Add to a Playlist...", systemImage: "text.badge.plus") }
                            Button(action: {}) { Label("Share", systemImage: "square.and.arrow.up") }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                    
                    // Scrubber
                    VStack(spacing: 8) {
                        Slider(value: Binding(get: {
                            engine.currentTime
                        }, set: { newValue in
                            engine.seek(to: newValue)
                        }), in: 0...Double(song.duration))
                            .accentColor(.white)
                        
                        HStack {
                            Text(formatTime(Int(engine.currentTime)))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("-\(formatTime(Int(song.duration) - Int(engine.currentTime)))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 30)
                    
                    // Controls
                    HStack {
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button(action: {
                            appState.isPlaying.toggle()
                            engine.togglePlayPause()
                        }) {
                            Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 40)
                    
                    // Volume Slider
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Slider(value: Binding(get: {
                            Double(engine.volume)
                        }, set: { newValue in
                            engine.volume = Float(newValue)
                        }), in: 0...1)
                            .accentColor(.white.opacity(0.8))
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                    
                    // Bottom Controls
                    HStack {
                        Button(action: {
                            showingLyrics.toggle()
                        }) {
                            Image(systemName: "quote.bubble")
                                .font(.title2)
                                .foregroundColor(showingLyrics ? .white : .white.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        AirPlayView()
                            .frame(width: 44, height: 44)
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            } else {
                Text("No Song Playing")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingLyrics) {
            iOSLyricsView(song: appState.currentSong)
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct AirPlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.backgroundColor = .clear
        routePickerView.activeTintColor = .white
        routePickerView.tintColor = .white
        return routePickerView
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct iOSLyricsView: View {
    let song: iOSSong?
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(song?.lyrics ?? "No lyrics available for this song.\n\nEnjoy the music!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(10)
                    .padding(32)
            }
            .navigationTitle(song?.title ?? "Lyrics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
