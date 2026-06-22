//
//  PremiumButtonStyle.swift
//  AtmosAMPlayer
//
//  Created by Peter Luedtke on 2026-06-22.
//


//
//  PremiumButtonStyle.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-22.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI

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
