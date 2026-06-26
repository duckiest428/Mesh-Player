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
        
        var sortedLines = lines.sorted(by: { $0.timestamp < $1.timestamp })
        if sortedLines.isEmpty { return [] }
        
        // 1. Calculate an Artificial End Time for a Lyric Line
        for i in 0..<sortedLines.count {
            let wordCount = Double(sortedLines[i].text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)
            let calculatedDuration = min(6.0, max(2.5, wordCount / 3.0))
            let nextLineStart = (i < sortedLines.count - 1) ? sortedLines[i+1].timestamp : sortedLines[i].timestamp + calculatedDuration
            let lineEndTime = min(sortedLines[i].timestamp + calculatedDuration, nextLineStart)
            sortedLines[i].endTime = lineEndTime
        }
        
        var processed: [SyncedLyricLine] = []
        
        // 2 & 3. Intro break if first lyric starts at >= 5.0s
        if sortedLines[0].timestamp >= 5.0 {
            processed.append(SyncedLyricLine(
                timestamp: 1.0,
                text: "...",
                isBreak: true,
                breakStart: 1.0,
                breakEnd: sortedLines[0].timestamp - 1.0,
                endTime: sortedLines[0].timestamp - 1.0
            ))
        }
        
        for i in 0..<sortedLines.count {
            processed.append(sortedLines[i])
            
            if i < sortedLines.count - 1 {
                let currentLine = sortedLines[i]
                let nextLine = sortedLines[i+1]
                let gap = nextLine.timestamp - currentLine.endTime
                
                // Gap of 5 seconds or more -> instrumental break
                if gap >= 5.0 {
                    processed.append(SyncedLyricLine(
                        timestamp: currentLine.endTime + 1.0,
                        text: "...",
                        isBreak: true,
                        breakStart: currentLine.endTime + 1.0,
                        breakEnd: nextLine.timestamp - 1.0,
                        endTime: nextLine.timestamp - 1.0
                    ))
                }
            }
        }
        
        return processed
    }
}
