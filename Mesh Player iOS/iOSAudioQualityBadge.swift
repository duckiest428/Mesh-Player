//
//  iOSAudioQualityBadge.swift
//  Mesh Player
//
//  Created by Peter Luedtke on 2026-07-12.
//


import SwiftUI

struct iOSAudioQualityBadge: View {
    let qualityType: AudioQualityType
    
    enum AudioQualityType {
        case lossless
        case hiResLossless
        case dolbyAtmos
    }
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }
    
    private var title: String {
        switch qualityType {
        case .lossless: return "Lossless"
        case .hiResLossless: return "Hi-Res Lossless"
        case .dolbyAtmos: return "Dolby Atmos"
        }
    }
    
    private var backgroundColor: Color {
        switch qualityType {
        case .lossless, .hiResLossless:
            return Color.gray.opacity(0.2)
        case .dolbyAtmos:
            return Color.black
        }
    }
    
    private var foregroundColor: Color {
        switch qualityType {
        case .lossless, .hiResLossless:
            return Color.primary
        case .dolbyAtmos:
            return Color.white
        }
    }
}
