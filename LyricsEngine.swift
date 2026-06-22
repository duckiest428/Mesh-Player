//
//  LyricsEngine.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-14.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI

class LyricsEngine {
    /// Parses LRC lyrics formatted text with timestamps like [01:23.45] lyric text.
    /// If no timestamps are found, it falls back to evenly distributing the lines across the track duration.
    static func parse(lyricsText: String, duration: TimeInterval = 240.0) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        let cleanText = lyricsText.replacingOccurrences(of: "\\n", with: "\n")
        let nativeLines = cleanText.components(separatedBy: .newlines)
        
        var hasBrackets = false
        
        for rawLine in nativeLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            
            // Look for matching brackets e.g. [00:12.34] or [03.45]
            if let bracketIndex = line.firstIndex(of: "]") {
                let timeString = String(line[line.index(after: line.startIndex)..<bracketIndex])
                let lyricText = String(line[line.index(after: bracketIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                var seconds: TimeInterval = 0.0
                
                if timeString.contains(":") {
                    // MM:SS.XX or MM:SS format
                    let parts = timeString.components(separatedBy: ":")
                    if parts.count == 2 {
                        if let minutes = Double(parts[0]), let secs = Double(parts[1]) {
                            seconds = (minutes * 60.0) + secs
                            hasBrackets = true
                            lines.append(SyncedLyricLine(timestamp: seconds, text: lyricText.isEmpty ? "♫" : lyricText))
                        }
                    }
                } else {
                    // Direct seconds representation
                    if let secs = Double(timeString) {
                        seconds = secs
                        hasBrackets = true
                        lines.append(SyncedLyricLine(timestamp: seconds, text: lyricText.isEmpty ? "♫" : lyricText))
                    }
                }
            }
        }
        
        // If it's a plain text lyrics file or holds no timestamps, evenly space the lines across the song duration
        if !hasBrackets {
            let nonSpaceLines = nativeLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !nonSpaceLines.isEmpty {
                let totalLines = Double(nonSpaceLines.count)
                let trackDuration = duration > 0 ? duration : 240.0
                for (idx, lineText) in nonSpaceLines.enumerated() {
                    let timestamp = (trackDuration / totalLines) * Double(idx)
                    lines.append(SyncedLyricLine(timestamp: timestamp, text: lineText))
                }
            }
        }
        
        let sortedLines = lines.sorted(by: { $0.timestamp < $1.timestamp })
        if sortedLines.isEmpty { return [] }
        
        var processed: [SyncedLyricLine] = []
        
        // Match TSX logic: Intro break if first lyric starts at >= 3.0s
        if sortedLines[0].timestamp >= 3.0 {
            processed.append(SyncedLyricLine(
                timestamp: 0.5,
                text: "...",
                isBreak: true,
                breakStart: 0.5,
                breakEnd: sortedLines[0].timestamp - 0.5
            ))
        }
        
        for i in 0..<sortedLines.count {
            processed.append(sortedLines[i])
            
            if i < sortedLines.count - 1 {
                let currentLine = sortedLines[i]
                let nextLine = sortedLines[i+1]
                let gap = nextLine.timestamp - currentLine.timestamp
                
                // Gap of 3 seconds or more -> instrumental break
                if gap >= 3.0 {
                    processed.append(SyncedLyricLine(
                        timestamp: currentLine.timestamp + 1.0,
                        text: "...",
                        isBreak: true,
                        breakStart: currentLine.timestamp + 1.0,
                        breakEnd: nextLine.timestamp - 0.5
                    ))
                }
            }
        }
        
        return processed
    }
}
