//
//  SidebarView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import AVFoundation
import CoreAudio

struct SidebarView: View {
    @ObservedObject var state: AppStateManager
    
    // Store library tabs as state to make them interactive and movable!
    @State private var libraryTabs = ["songs", "albums", "artists", "genres", "recently-added"]
    
    var body: some View {
        List(selection: $state.selectedTab) {
            Section("Apple Music Library") {
                ForEach(libraryTabs, id: \.self) { tab in
                    if tab == "songs" {
                        NavigationLink(value: "songs") {
                            Label("Songs", systemImage: "music.note.list")
                        }
                    } else if tab == "albums" {
                        NavigationLink(value: "albums") {
                            Label("Albums", systemImage: "square.stack")
                        }
                    } else if tab == "artists" {
                        NavigationLink(value: "artists") {
                            Label("Artists", systemImage: "music.mic")
                        }
                    } else if tab == "genres" {
                        NavigationLink(value: "genres") {
                            Label("Genres", systemImage: "guitars")
                        }
                    } else if tab == "recently-added" {
                        NavigationLink(value: "recently-added") {
                            Label("Recently Added", systemImage: "clock")
                        }
                    }
                }
                .onMove { indices, newOffset in
                    libraryTabs.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            
            Section("Playlists (Imported)") {
                ForEach(state.playlists) { playlist in
                    NavigationLink(value: "playlist-\(playlist.id.uuidString)") {
                        Label(playlist.name, systemImage: "music.note.house")
                    }
                    .contextMenu {
                        Button("Delete Playlist") {
                            state.deletePlaylist(playlist.id)
                        }
                    }
                }
            }
            
            Section("Add Music") {
                NavigationLink(value: "expand-library") {
                    Label("Expand Library (am-dl)", systemImage: "plus.app.fill")
                }
            }
            
            Section("Mac Tools") {
                Button(action: scanLocalMusicDirectory) {
                     Label("Auto-Scan Local Music", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
    
    private func scanLocalMusicDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Apple Music Media Library Folder"
        panel.prompt = "Choose Folder"
        panel.message = "Choose your Apple Music/Media directory with Artist and Album subfolders to import your music."
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                self.importTracksFromFolder(at: selectedURL)
            }
        }
    }
    
    private func importTracksFromFolder(at folderURL: URL) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .localizedNameKey]
        
        let isScoped = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return
        }
        
        var importedTracks: [LocalTrack] = []
        let audioExtensions = ["mp3", "m4a", "wav", "flac", "alac", "m4b", "aac", "mp4", "ogg"]
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                guard let isRegularFile = resourceValues.isRegularFile else { continue }
                if isRegularFile {
                    let ext = fileURL.pathExtension.lowercased()
                    if audioExtensions.contains(ext) {
                        // Gather path components to detect Artist and Album
                        let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path, with: "")
                        let parts = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
                        
                        var title = fileURL.deletingPathExtension().lastPathComponent
                        var artist = "Unknown Artist"
                        var album = "Unknown Album"
                        
                        // If path is Artist/Album/Song.m4a
                        if parts.count >= 3 {
                            artist = parts[parts.count - 3]
                            album = parts[parts.count - 2]
                            title = fileURL.deletingPathExtension().lastPathComponent
                        } else if parts.count == 2 {
                            // If Artist/Song.m4a
                            artist = parts[parts.count - 2]
                            album = "Single"
                        }
                        
                        // Clean the song title to remove playlist/track numbering prefixes
                        title = cleanSongTitle(title)
                        
                        // Simple file size fetch helper
                        var fileSizeString = "Unknown Size"
                        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                           let size = attributes[.size] as? Int64 {
                            let mb = Double(size) / (1024.0 * 1024.0)
                            fileSizeString = String(format: "%.1f MB", mb)
                        }
                        
                        // Determine if it's potentially Dolby Atmos
                        let lowerName = title.lowercased()
                        var isAtmos = lowerName.contains("atmos") || lowerName.contains("spatial") || lowerName.contains("surround") || lowerName.contains("5.1")
                        
                        // Search for cover artwork inside the album folder
                        var coverURL: URL? = nil
                        let parentFolderURL = fileURL.deletingLastPathComponent()
                        if let enumerator = FileManager.default.enumerator(at: parentFolderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) {
                            for case let url as URL in enumerator {
                                let pathExt = url.pathExtension.lowercased()
                                if ["jpg", "jpeg", "png", "webp"].contains(pathExt) {
                                    coverURL = url
                                    break
                                }
                            }
                        }
                        
                        // Extract metadata from AVAsset directly!
                        let asset = AVAsset(url: fileURL)
                        
                        // Try reading embedded tags
                        var embeddedArtworkData: Data? = nil
                        for item in asset.metadata {
                            if item.commonKey == AVMetadataKey.commonKeyArtwork {
                                if let data = item.dataValue {
                                    embeddedArtworkData = data
                                    break
                                }
                            }
                        }
                        
                        // Read track info or use path fallbacks
                        var finalTitle = title
                        var finalArtist = artist
                        var finalAlbum = album
                        var finalGenre = "Alternative"
                        var finalDuration: TimeInterval = 240.0
                        
                        let durationVal = asset.duration
                        let secs = CMTimeGetSeconds(durationVal)
                        if !secs.isNaN && secs > 0 {
                            finalDuration = secs
                        }
                        
                        for item in asset.metadata {
                            let idRaw = item.identifier?.rawValue.lowercased() ?? ""
                            if let commonKey = item.commonKey {
                                switch commonKey {
                                case AVMetadataKey.commonKeyTitle:
                                    if let val = item.stringValue, !val.isEmpty { finalTitle = val }
                                case AVMetadataKey.commonKeyArtist:
                                    if let val = item.stringValue, !val.isEmpty { finalArtist = val }
                                case AVMetadataKey.commonKeyAlbumName:
                                    if let val = item.stringValue, !val.isEmpty { finalAlbum = val }
                                case AVMetadataKey.commonKeyType:
                                    if let val = item.stringValue, !val.isEmpty { finalGenre = val }
                                default:
                                    break
                                }
                            }
                            if idRaw.contains("gen") {
                                if let val = item.stringValue, !val.isEmpty { finalGenre = val }
                            }
                        }
                        
                        // Estimate format metadata and perform robust Dolby Atmos & Lossless analysis
                        let combinedMetaLower = "\(fileURL.lastPathComponent) \(finalTitle) \(finalAlbum) \(finalGenre) \(finalArtist)".lowercased()
                        var isCodecAtmos = false
                        var isLossless = false
                        let ext = fileURL.pathExtension.lowercased()
                        if ["flac", "wav", "aif", "aiff", "alac"].contains(ext) {
                            isLossless = true
                        }
                        
                        // Check structural track formats
                        if let audioTrack = asset.tracks(withMediaType: .audio).first {
                            let formatDescriptions = audioTrack.formatDescriptions
                            for desc in formatDescriptions {
                                let formatDesc = desc as! CMFormatDescription
                                let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
                                
                                // Convert FourCharCode to string safely
                                let byte1 = (subType >> 24) & 0xff
                                let byte2 = (subType >> 16) & 0xff
                                let byte3 = (subType >> 8) & 0xff
                                let byte4 = subType & 0xff
                                
                                if let scalar1 = UnicodeScalar(byte1),
                                   let scalar2 = UnicodeScalar(byte2),
                                   let scalar3 = UnicodeScalar(byte3),
                                   let scalar4 = UnicodeScalar(byte4) {
                                    let char1 = Character(scalar1)
                                    let char2 = Character(scalar2)
                                    let char3 = Character(scalar3)
                                    let char4 = Character(scalar4)
                                    let subTypeStr = "\(char1)\(char2)\(char3)\(char4)".trimmingCharacters(in: .whitespaces).lowercased()
                                    
                                    if ["ec-3", "ec3", "mlp", "ac-3", "ac3", "atmos"].contains(where: { subTypeStr.contains($0) }) {
                                        isCodecAtmos = true
                                    }
                                    if ["alac", "flac", "lpcm", "pcm"].contains(where: { subTypeStr.contains($0) }) {
                                        isLossless = true
                                    }
                                }
                            }
                        }
                        
                        isAtmos = isCodecAtmos || combinedMetaLower.contains("atmos") ||
                                  combinedMetaLower.contains("spatial") ||
                                  combinedMetaLower.contains("surround") ||
                                  combinedMetaLower.contains("5.1")
                        
                        var formatStr = "AAC 256kbps"
                        if isAtmos {
                            formatStr = "Dolby Atmos"
                        } else {
                            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                               let size = attributes[.size] as? Int64, finalDuration > 0 {
                                let estBitrate = Int(Double(size * 8) / (finalDuration * 1000.0))
                                if ext == "mp3" {
                                    let choices = [128, 160, 192, 256, 320]
                                    let closest = choices.min(by: { abs($0 - estBitrate) < abs($1 - estBitrate) }) ?? 320
                                    formatStr = "MP3 \(closest)kbps"
                                } else if ext == "m4a" || ext == "aac" {
                                    if isLossless {
                                        formatStr = "Lossless (ALAC)"
                                    } else {
                                        let choices = [128, 160, 256, 320]
                                        let closest = choices.min(by: { abs($0 - estBitrate) < abs($1 - estBitrate) }) ?? 256
                                        formatStr = "AAC \(closest)kbps"
                                    }
                                } else if ext == "wav" || ext == "flac" || ext == "alac" {
                                    formatStr = "Lossless (ALAC) \(estBitrate > 100 ? estBitrate : 1411)kbps"
                                } else {
                                    formatStr = "AUDIO \(estBitrate > 50 ? estBitrate : 256)kbps"
                                }
                            }
                        }
                        
                        // Scan for companion .lrc or .txt lyrics file (with the same name as the song) or any .lrc file in that folder
                        var lyricsContent = ""
                        
                        // Check standard id3/m4a lyrics tag first
                        for item in asset.metadata {
                            let idRaw = item.identifier?.rawValue.lowercased() ?? ""
                            let keyStr = (item.key as? String)?.lowercased() ?? ""
                            
                            if idRaw.contains("lyr") || idRaw.contains("uslt") || idRaw.contains("lyrics") ||
                               keyStr.contains("lyr") || keyStr.contains("uslt") || keyStr.contains("lyrics") {
                                if let val = item.stringValue, !val.isEmpty {
                                    lyricsContent = val.replacingOccurrences(of: "\n", with: "\\n")
                                    break
                                }
                            }
                        }
                        
                        let possibleLRCURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
                        let possibleTXTURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
                        
                        if fileManager.fileExists(atPath: possibleLRCURL.path) {
                            if let content = try? String(contentsOf: possibleLRCURL, encoding: .utf8) {
                                lyricsContent = content.replacingOccurrences(of: "\n", with: "\\n")
                            }
                        } else if fileManager.fileExists(atPath: possibleTXTURL.path) {
                            if let content = try? String(contentsOf: possibleTXTURL, encoding: .utf8) {
                                lyricsContent = content.replacingOccurrences(of: "\n", with: "\\n")
                            }
                        } else {
                            // Fallback: search for any .lrc file in same folder
                            if let enumerator = fileManager.enumerator(at: parentFolderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) {
                                for case let url as URL in enumerator {
                                    if url.pathExtension.lowercased() == "lrc" {
                                        if let content = try? String(contentsOf: url, encoding: .utf8) {
                                            lyricsContent = content.replacingOccurrences(of: "\n", with: "\\n")
                                            break
                                        }
                                    }
                                }
                            }
                        }
                        
                        var fileDateAdded = Date()
                        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path) {
                            if let creationDate = attrs[.creationDate] as? Date {
                                fileDateAdded = creationDate
                            } else if let modificationDate = attrs[.modificationDate] as? Date {
                                fileDateAdded = modificationDate
                            }
                        }
                        
                        let track = LocalTrack(
                            title: finalTitle,
                            artist: finalArtist,
                            album: finalAlbum,
                            genre: finalGenre,
                            duration: finalDuration,
                            fileURL: fileURL,
                            coverImageName: isAtmos ? "sparkles" : "music.note",
                            localCoverURL: coverURL,
                            embeddedArtData: embeddedArtworkData,
                            dateAdded: fileDateAdded,
                            isAtmos: isAtmos,
                            fileSize: fileSizeString,
                            lyrics: lyricsContent,
                            isFavorite: false,
                            playCount: 0,
                            format: formatStr
                        )
                        importedTracks.append(track)
                    }
                }
            } catch {
                print("Error scanning entry: \(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async {
            if !importedTracks.isEmpty {
                // Add scanning output to state, filtering out duplicates
                for track in importedTracks {
                    self.state.upsertTrack(track)
                }
                
                print("Successfully processed \(importedTracks.count) songs from selected folder!")
            }
        }
    }
    
    private func cleanSongTitle(_ rawTitle: String) -> String {
        let titleStr = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^(\\d+[-_.]\\d+|\\d+)\\s*[-_.]?\\s*"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: titleStr.utf16.count)
            let cleaned = regex.stringByReplacingMatches(in: titleStr, options: [], range: range, withTemplate: "")
            if !cleaned.isEmpty {
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return titleStr
    }
}

// MARK: - LyricsSidebarView

struct LyricsSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14))
                        .foregroundColor(state.theme.accent)
                    Text("Synced Lyrics")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(state.theme.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(state.theme.sidebarBackground.opacity(0.5))
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Lyrics scroll view
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    if engine.parsedLyrics.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.system(size: 32))
                                .foregroundColor(state.theme.accent.opacity(0.8))
                            Text("No Lyrics Available")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.theme.textPrimary)
                            Text("Instrumental Atmos stream active.")
                                .font(.system(size: 9.5))
                                .foregroundColor(state.theme.textSecondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(engine.parsedLyrics) { line in
                                let isActive = isLineActive(line)
                                
                                Group {
                                    if line.isBreak {
                                        InstrumentalBreakDots(
                                            currentTime: engine.currentTime,
                                            breakStart: line.breakStart,
                                            breakEnd: line.breakEnd
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .scaleEffect(0.65) // Scales wonderfully for small sidebars!
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundColor(isActive ? state.theme.textPrimary : state.theme.textPrimary.opacity(0.25))
                                            .scaleEffect(isActive ? 1.02 : 1.0)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    engine.seek(to: line.timestamp)
                                }
                                .id(line.id)
                            }
                        }
                        .padding(.vertical, 120)
                        .padding(.horizontal, 16)
                        .onChange(of: engine.currentTime) { newValue in
                            if let currentActive = engine.parsedLyrics.last(where: { $0.timestamp <= newValue }) {
                                withAnimation {
                                    proxy.scrollTo(currentActive.id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 280)
        .background(state.theme.sidebarBackground)
    }
    
    private func isLineActive(_ line: SyncedLyricLine) -> Bool {
        if line.isBreak {
            return engine.currentTime >= line.breakStart && engine.currentTime <= line.breakEnd
        }
        return engine.currentTime >= line.timestamp && engine.currentTime < line.endTime
    }
}

// MARK: - QueueSidebarView

struct QueueSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    var isFullscreen: Bool = false
    
    var upcomingTracks: [LocalTrack] {
        guard let currentTrack = engine.currentTrack else { return [] }
        guard let currentIndex = state.activeQueue.firstIndex(where: { $0.id == currentTrack.id }) else { return [] }
        if state.activeQueue.count <= 1 { return [] }
        
        var sorted: [LocalTrack] = []
        for i in (currentIndex + 1)..<state.activeQueue.count {
            sorted.append(state.activeQueue[i])
        }
        return sorted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 14))
                        .foregroundColor(state.theme.accent)
                    Text("Playing Next")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(state.theme.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(state.theme.sidebarBackground.opacity(0.5))
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Now Playing Block
            if let current = engine.currentTrack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOW PLAYING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(state.theme.accent)
                        .tracking(1.5)
                    
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.theme.cardBackground)
                                .frame(width: 44, height: 44)
                            
                            if let artData = current.embeddedArtData, let nsImage = NSImage(data: artData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                            } else if let imageURL = current.localCoverURL, let nsImage = NSImage(contentsOf: imageURL) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: current.coverImageName)
                                    .font(.system(size: 16))
                                    .foregroundColor(state.theme.accent)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(current.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.theme.textPrimary)
                                .lineLimit(1)
                            
                            Text(current.artist)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(state.theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.02))
                
                Divider()
                    .background(state.theme.textSecondary.opacity(0.1))
            }
            
            // Scrolling list of next up
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("NEXT UP (\(upcomingTracks.count) TRACKS)")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(state.theme.textSecondary.opacity(0.5))
                            .tracking(1.2)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    if upcomingTracks.isEmpty {
                        VStack {
                            Spacer()
                            Text("No tracks queued next")
                                .font(.system(size: 11))
                                .foregroundColor(state.theme.textSecondary.opacity(0.4))
                                .padding(.vertical, 40)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(upcomingTracks.prefix(100)) { track in
                                Button(action: {
                                    engine.playTrack(track)
                                }) {
                                    HStack(spacing: 10) {
                                        AsyncThumbnailView(track: track, size: 32, theme: state.theme)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.system(size: 10.5, weight: .bold))
                                                .foregroundColor(state.theme.textPrimary)
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(state.theme.textSecondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(state.theme.textSecondary.opacity(0.3))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(QueueRowButtonStyle(theme: state.theme))
                            }
                            
                            if upcomingTracks.count > 100 {
                                Text("+ \(upcomingTracks.count - 100) MORE TRACKS IN QUEUE")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(state.theme.textSecondary.opacity(0.4))
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(width: isFullscreen ? 440 : 280)
        .background(isFullscreen ? Color.clear : state.theme.sidebarBackground)
        .background(isFullscreen ? AnyView(Rectangle().fill(Material.ultraThin).opacity(0.85)) : AnyView(Color.clear))
    }
}

struct QueueRowButtonStyle: ButtonStyle {
    var theme: ThemeColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.cardBackground.opacity(0.2) : Color.clear)
            .cornerRadius(6)
            .padding(.horizontal, 6)
    }
}

// MARK: - OutputDeviceSidebarView

struct SwiftOutputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String // "built-in" | "headphones" | "airplay" | "bluetooth"
    let hasAtmos: Bool
    let model: String
}

struct OutputDeviceSidebarView: View {
    @ObservedObject var state: AppStateManager
    @ObservedObject var engine: AudioEngineManager
    var isFullscreen: Bool = false
    
    @State private var connectingDeviceId: String? = nil
    @State private var volumes: [String: Double] = [
        "peteys-macbook": 0.75,
        "peteys-airpods-2": 0.60,
        "peteys-airpods-3": 0.55
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 14))
                        .foregroundColor(.indigo)
                    Text("Audio Output Device")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(state.theme.textPrimary)
                }
                
                Spacer()
                
                Text("CoreAudio")
                    .font(.system(size: 8, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(3)
                    .foregroundColor(state.theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(state.theme.sidebarBackground.opacity(0.5))
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Devices scrolling list
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SELECT OUTPUT ZONE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(state.theme.textSecondary.opacity(0.5))
                        .tracking(1.2)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    
                    ForEach(engine.availableOutputs) { device in
                        let isActive = device.id == engine.activeOutputId
                        let isConnecting = device.id == connectingDeviceId
                        let volumeBinding = Binding<Double>(
                            get: { volumes[device.id] ?? 0.5 },
                            set: { volumes[device.id] = $0 }
                        )
                        
                        VStack(spacing: 0) {
                            Button(action: {
                                if device.id != engine.activeOutputId && connectingDeviceId == nil {
                                    connectingDeviceId = device.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                        engine.setOutputDevice(id: device.id)
                                        connectingDeviceId = nil
                                    }
                                }
                            }) {
                                HStack(spacing: 12) {
                                    // Device Type Icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isActive ? Color.indigo : state.theme.cardBackground)
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: getIconName(type: device.type))
                                            .font(.system(size: 14))
                                            .foregroundColor(isActive ? .white : state.theme.textPrimary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(device.name)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(state.theme.textPrimary)
                                                .lineLimit(1)
                                            
                                            if device.hasAtmos {
                                                DolbyAtmosBadge(color: .blue, scale: 0.6, showText: false)
                                            }
                                        }
                                        
                                        Text(device.model)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(state.theme.textSecondary.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    if isConnecting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if isActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.indigo)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if isActive {
                                VStack(spacing: 8) {
                                    VStack(spacing: 4) {
                                        HStack {
                                            HStack(spacing: 4) {
                                                Image(systemName: "volume.2.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.indigo)
                                                Text("Zone Output Limit")
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundColor(state.theme.textSecondary)
                                            }
                                            Spacer()
                                            Text("\(Int(volumeBinding.wrappedValue * 100))%")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(state.theme.textSecondary)
                                        }
                                        
                                        Slider(value: volumeBinding, in: 0...1)
                                            .accentColor(.indigo)
                                            .controlSize(.small)
                                    }
                                    
                                    if device.type == "headphones" {
                                        Divider()
                                            .background(state.theme.textSecondary.opacity(0.12))
                                            .padding(.vertical, 4)
                                        
                                        VStack(spacing: 6) {
                                            HStack {
                                                HStack(spacing: 4) {
                                                    Text(" Spatial Audio")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(state.theme.textPrimary)
                                                    Text("(AirPods Simulation)")
                                                        .font(.system(size: 8))
                                                        .foregroundColor(state.theme.textSecondary.opacity(0.6))
                                                }
                                                Spacer()
                                                Text(state.spatialAudioActive ? "ACTIVE" : "OFF")
                                                    .font(.system(size: 7, weight: .black, design: .monospaced))
                                                    .foregroundColor(state.spatialAudioActive ? Color.blue : state.theme.textSecondary)
                                                    .padding(.horizontal, 4.5)
                                                    .padding(.vertical, 1.5)
                                                    .background(state.spatialAudioActive ? Color.blue.opacity(0.15) : state.theme.textSecondary.opacity(0.1))
                                                    .cornerRadius(3.5)
                                            }
                                            
                                            HStack(spacing: 6) {
                                                Button(action: { state.spatialAudioActive = false }) {
                                                    Text("Stereo")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 6)
                                                        .background(!state.spatialAudioActive ? state.theme.accent.opacity(0.15) : state.theme.cardBackground)
                                                        .foregroundColor(!state.spatialAudioActive ? state.theme.accent : state.theme.textSecondary)
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button(action: { state.spatialAudioActive = true }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "dot.radiowaves.left.and.right")
                                                            .font(.system(size: 8))
                                                        Text("Spatialize")
                                                    }
                                                    .font(.system(size: 10, weight: .bold))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 6)
                                                    .background(state.spatialAudioActive ? Color.blue.opacity(0.15) : state.theme.cardBackground)
                                                    .foregroundColor(state.spatialAudioActive ? Color.blue : state.theme.textSecondary)
                                                    .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            
                                            if state.spatialAudioActive {
                                                Text("• Simulating Spatial Head Field •")
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(.blue)
                                                    .padding(.top, 2)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(isActive ? Color.indigo.opacity(0.06) : Color.clear)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isActive ? Color.indigo.opacity(0.2) : Color.clear, lineWidth: 1)
                        )
                        .padding(.horizontal, 10)
                    }
                }
            }
            
            Spacer()
            
            Divider()
                .background(state.theme.textSecondary.opacity(0.12))
            
            // Footer
            Text("LATENCY HANDSHAKE: 2ms • AAC LOSSLESS DIRECT")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(state.theme.textSecondary.opacity(0.4))
                .padding(.vertical, 8)
        }
        .frame(width: isFullscreen ? 440 : 280)
        .background(isFullscreen ? Color.clear : state.theme.sidebarBackground)
        .background(isFullscreen ? AnyView(Rectangle().fill(Material.ultraThin).opacity(0.85)) : AnyView(Color.clear))
    }
    
    private func getIconName(type: String) -> String {
        switch type {
        case "built-in":
            return "laptopcomputer"
        case "headphones":
            return "airpodspro"
        case "airplay":
            return "tv.and.mediabox"
        default: // bluetooth / wireless
            return "speaker.wave.2"
        }
    }
}

struct AsyncThumbnailView: View {
    let track: LocalTrack
    let size: CGFloat
    let theme: ThemeColor
    
    @State private var thumbnail: NSImage?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.cardBackground)
                .frame(width: size, height: size)
            
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .cornerRadius(4)
            } else {
                Image(systemName: track.coverImageName)
                    .font(.system(size: size * 0.4))
                    .foregroundColor(theme.accent)
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            var sourceImage: NSImage?
            if let artData = track.embeddedArtData {
                sourceImage = NSImage(data: artData)
            } else if let imageURL = track.localCoverURL {
                sourceImage = NSImage(contentsOf: imageURL)
            }
            
            if let img = sourceImage {
                let targetSize = NSSize(width: size * 2, height: size * 2)
                let newImage = NSImage(size: targetSize)
                newImage.lockFocus()
                img.draw(in: NSRect(origin: .zero, size: targetSize),
                         from: NSRect(origin: .zero, size: img.size),
                         operation: .copy,
                         fraction: 1.0)
                newImage.unlockFocus()
                
                DispatchQueue.main.async {
                    self.thumbnail = newImage
                }
            }
        }
    }
}
