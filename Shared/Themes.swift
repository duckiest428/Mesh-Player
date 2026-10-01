//
//  Themes.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  The color themes. The Mac picks one and sends its name to the iPhone when syncing.
//

import SwiftUI

nonisolated struct ThemeColor: Sendable {
    let background: Color
    let sidebarBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let cardBackground: Color
    let isDark: Bool
}

// MARK: - Theme catalog

nonisolated enum ThemeCatalog {
    static let names = [
        "Mesh Default (Apple Music)", "Space Gray", "Midnight Indigo", "Sakura Blossom", "Sunset Glow",
        "Cyber Neon", "True Black", "Midnight Blue", "Y2K / Skeuomorphic (Frutiger Aero)", "Cyberpunk",
        "Vaporwave", "Warm Coffee"
    ]

    static func theme(named name: String) -> ThemeColor {
        switch name {
        case "Mesh Default (Apple Music)":
            return ThemeColor(
                background: Color(red: 0.075, green: 0.075, blue: 0.086),
                sidebarBackground: Color(red: 0.105, green: 0.105, blue: 0.118),
                textPrimary: Color(white: 0.96),
                textSecondary: Color.white.opacity(0.56),
                accent: Color(red: 0.99, green: 0.24, blue: 0.40),
                cardBackground: Color.white.opacity(0.065),
                isDark: true
            )
        case "Midnight Indigo":
            return ThemeColor(
                background: Color(red: 0.05, green: 0.04, blue: 0.10),
                sidebarBackground: Color(red: 0.08, green: 0.06, blue: 0.15),
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.58),
                accent: Color(red: 0.62, green: 0.45, blue: 1.0),
                cardBackground: Color.white.opacity(0.07),
                isDark: true
            )
        case "Sakura Blossom":
            return ThemeColor(
                background: Color(red: 1.00, green: 0.96, blue: 0.97),
                sidebarBackground: Color(red: 0.99, green: 0.91, blue: 0.93),
                textPrimary: Color(red: 0.30, green: 0.13, blue: 0.18),
                textSecondary: Color(red: 0.30, green: 0.13, blue: 0.18).opacity(0.6),
                accent: Color(red: 0.93, green: 0.30, blue: 0.47),
                cardBackground: Color(red: 0.30, green: 0.13, blue: 0.18).opacity(0.06),
                isDark: false
            )
        case "Sunset Glow":
            return ThemeColor(
                background: Color(red: 0.11, green: 0.06, blue: 0.05),
                sidebarBackground: Color(red: 0.16, green: 0.09, blue: 0.07),
                textPrimary: Color(red: 0.98, green: 0.92, blue: 0.88),
                textSecondary: Color(red: 0.98, green: 0.92, blue: 0.88).opacity(0.58),
                accent: Color(red: 1.0, green: 0.55, blue: 0.22),
                cardBackground: Color(red: 1.0, green: 0.75, blue: 0.6).opacity(0.07),
                isDark: true
            )
        case "Cyber Neon":
            return ThemeColor(
                background: Color(red: 0.02, green: 0.02, blue: 0.04),
                sidebarBackground: Color(red: 0.05, green: 0.03, blue: 0.09),
                textPrimary: Color(red: 0.88, green: 0.92, blue: 1.00),
                textSecondary: Color(red: 0.88, green: 0.92, blue: 1.00).opacity(0.58),
                accent: Color(red: 0.0, green: 0.92, blue: 1.0),
                cardBackground: Color(red: 0.5, green: 0.4, blue: 1.0).opacity(0.08),
                isDark: true
            )
        case "True Black":
            return ThemeColor(
                background: .black,
                sidebarBackground: Color(white: 0.04),
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.55),
                accent: .white,
                cardBackground: Color.white.opacity(0.06),
                isDark: true
            )
        case "Midnight Blue":
            return ThemeColor(
                background: Color(red: 0.02, green: 0.05, blue: 0.10),
                sidebarBackground: Color(red: 0.03, green: 0.08, blue: 0.15),
                textPrimary: Color(red: 0.90, green: 0.93, blue: 0.97),
                textSecondary: Color(red: 0.90, green: 0.93, blue: 0.97).opacity(0.58),
                accent: Color(red: 0.25, green: 0.72, blue: 1.0),
                cardBackground: Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.08),
                isDark: true
            )
        case "Y2K / Skeuomorphic (Frutiger Aero)":
            return ThemeColor(
                background: Color(red: 0.92, green: 0.97, blue: 0.99),
                sidebarBackground: Color(red: 0.85, green: 0.94, blue: 0.99),
                textPrimary: Color(red: 0.05, green: 0.23, blue: 0.40),
                textSecondary: Color(red: 0.05, green: 0.23, blue: 0.40).opacity(0.62),
                accent: Color(red: 0.10, green: 0.56, blue: 0.95),
                cardBackground: Color(red: 0.05, green: 0.35, blue: 0.65).opacity(0.07),
                isDark: false
            )
        case "Cyberpunk":
            return ThemeColor(
                background: Color(red: 0.06, green: 0.06, blue: 0.08),
                sidebarBackground: Color(red: 0.09, green: 0.09, blue: 0.12),
                textPrimary: Color(red: 1.0, green: 0.93, blue: 0.30),
                textSecondary: Color(red: 1.0, green: 0.93, blue: 0.30).opacity(0.58),
                accent: Color(red: 0.0, green: 0.90, blue: 1.0),
                cardBackground: Color.white.opacity(0.06),
                isDark: true
            )
        case "Vaporwave":
            return ThemeColor(
                background: Color(red: 0.95, green: 0.91, blue: 0.99),
                sidebarBackground: Color(red: 0.90, green: 0.84, blue: 0.98),
                textPrimary: Color(red: 0.29, green: 0.08, blue: 0.33),
                textSecondary: Color(red: 0.29, green: 0.08, blue: 0.33).opacity(0.6),
                accent: Color(red: 0.78, green: 0.20, blue: 0.95),
                cardBackground: Color(red: 0.45, green: 0.10, blue: 0.60).opacity(0.07),
                isDark: false
            )
        case "Warm Coffee":
            return ThemeColor(
                background: Color(red: 0.97, green: 0.94, blue: 0.90),
                sidebarBackground: Color(red: 0.93, green: 0.88, blue: 0.82),
                textPrimary: Color(red: 0.25, green: 0.18, blue: 0.14),
                textSecondary: Color(red: 0.25, green: 0.18, blue: 0.14).opacity(0.6),
                accent: Color(red: 0.62, green: 0.38, blue: 0.18),
                cardBackground: Color(red: 0.40, green: 0.25, blue: 0.12).opacity(0.07),
                isDark: false
            )
        default: // Space Gray
            return ThemeColor(
                background: Color(red: 0.11, green: 0.11, blue: 0.13),
                sidebarBackground: Color(red: 0.14, green: 0.14, blue: 0.16),
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.58),
                accent: Color(red: 0.55, green: 0.62, blue: 0.75),
                cardBackground: Color.white.opacity(0.07),
                isDark: true
            )
        }
    }
}
