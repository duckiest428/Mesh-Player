//
//  DesignSystem.swift
//  Mesh Player
//
//  Shared visual language: theme-derived colors, cached formatters, and the small set of
//  reusable controls (pills, icon buttons, headers, cards) every screen is built from.
//

import AppKit
import SwiftUI

// MARK: - Theme helpers

extension ThemeColor {
    var colorScheme: ColorScheme { isDark ? .dark : .light }
    var hairline: Color { textPrimary.opacity(isDark ? 0.08 : 0.10) }
    var hover: Color { textPrimary.opacity(isDark ? 0.07 : 0.06) }
    var pressed: Color { textPrimary.opacity(isDark ? 0.12 : 0.10) }
    var textTertiary: Color { textPrimary.opacity(isDark ? 0.34 : 0.38) }
    var elevated: Color { isDark ? Color.white.opacity(0.085) : Color.white.opacity(0.8) }
    var barBackground: Color { sidebarBackground.opacity(isDark ? 0.82 : 0.86) }
    /// Text/icon color that stays legible on top of the accent color.
    var onAccent: Color {
        let ns = NSColor(accent).usingColorSpace(.sRGB)
        let luminance = (ns?.redComponent ?? 0) * 0.299 + (ns?.greenComponent ?? 0) * 0.587 + (ns?.blueComponent ?? 0) * 0.114
        return luminance > 0.7 ? .black : .white
    }
    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Formatting (formatters are expensive to create, so they are shared)

enum Fmt {
    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func longDuration(_ seconds: TimeInterval) -> String {
        // Rounded like Apple Music, so a 2:50 song reads "3 min" here and in the album footer.
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(max(m, seconds > 0 ? 1 : 0)) min"
    }

    static func listening(_ seconds: TimeInterval) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 360_000 { return String(format: "%.1f hrs", seconds / 3600) }
        return "\(Int(seconds / 3600)) hrs"
    }

    static func date(_ date: Date) -> String { shortDate.string(from: date) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// "3 days ago", "2 months ago", "today".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDateInToday(date) { return "today" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    static func count(_ n: Int) -> String { number.string(from: NSNumber(value: n)) ?? "\(n)" }

    static func songs(_ n: Int) -> String { "\(count(n)) song\(n == 1 ? "" : "s")" }

    static func greeting(for date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night listening"
        }
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary
    let theme: ThemeColor
    var compact = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, theme: theme, compact: compact, large: large)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let kind: Kind
        let theme: ThemeColor
        let compact: Bool
        let large: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: large ? 15 : (compact ? 12 : 13), weight: .semibold))
                .labelStyle(PillLabelStyle())
                .padding(.horizontal, large ? 24 : (compact ? 12 : 18))
                .frame(height: large ? 40 : (compact ? 28 : 34))
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(kind == .ghost ? theme.hairline : .clear, lineWidth: 1))
                .brightness(kind == .primary && hovering ? 0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }

        private var foreground: Color {
            switch kind {
            case .primary: return theme.onAccent
            case .secondary: return theme.accent
            case .ghost: return theme.textPrimary
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return theme.accent
            case .secondary: return hovering ? theme.pressed : theme.hover
            case .ghost: return hovering ? theme.hover : .clear
            }
        }
    }
}

private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Circular, hover-highlighted icon button used in bars and headers.
struct IconButtonStyle: ButtonStyle {
    let theme: ThemeColor
    var isActive = false
    var size: CGFloat = 30
    var activeColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, theme: theme, isActive: isActive, size: size, activeColor: activeColor)
    }

    private struct IconBody: View {
        let configuration: Configuration
        let theme: ThemeColor
        let isActive: Bool
        let size: CGFloat
        let activeColor: Color?
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isActive ? (activeColor ?? theme.accent) : (hovering ? theme.textPrimary : theme.textSecondary))
                .frame(width: size, height: size)
                .background(Circle().fill(configuration.isPressed ? theme.pressed : (hovering ? theme.hover : .clear)))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(Circle())
        }
    }
}

// MARK: - Headers

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let theme: ThemeColor
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.top, 48)
        .padding(.bottom, 14)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, theme: ThemeColor) {
        self.init(title: title, subtitle: subtitle, theme: theme, trailing: { EmptyView() })
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    let theme: ThemeColor
    var action: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text("See All")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hovering ? theme.accent : theme.textSecondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
            }
        }
        .padding(.horizontal, 28)
    }
}

/// Small uppercase caption used for metadata labels.
struct Eyebrow: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

// MARK: - Cards & hover

struct HoverLift: ViewModifier {
    var scale: CGFloat = 1.025
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(_ scale: CGFloat = 1.025) -> some View { modifier(HoverLift(scale: scale)) }

    func card(_ theme: ThemeColor, radius: CGFloat = 12) -> some View {
        self
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }
}

/// Artwork tile with a hover play button, shared by album / track cards.
struct ArtworkTile: View {
    let track: LocalTrack
    let theme: ThemeColor
    var pixelSize: CGFloat = 400
    var cornerRadius: CGFloat = 10
    var circular = false
    var onPlay: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        ArtworkView(track: track, pixelSize: pixelSize, cornerRadius: circular ? 1000 : cornerRadius)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if hovering {
                    (circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
                        .fill(Color.black.opacity(0.22))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hovering, let onPlay {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .offset(x: 1)
                            .frame(width: 38, height: 38)
                            .background(theme.accent, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.14), radius: hovering ? 14 : 8, y: hovering ? 8 : 4)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Import feedback

struct ImportStatusCard: View {
    @ObservedObject var importer: LibraryImporter
    let theme: ThemeColor

    var body: some View {
        if importer.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(importer.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        importer.cancel()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(IconButtonStyle(theme: theme, size: 20))
                    .help("Stop importing")
                }
                if let progress = importer.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                }
                Text(importer.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(12)
            .card(theme, radius: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ImportToast: View {
    @ObservedObject var importer: LibraryImporter
    let theme: ThemeColor

    var body: some View {
        if let summary = importer.summary {
            HStack(spacing: 12) {
                Image(systemName: summary.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(summary.isError ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(summary.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 380, alignment: .leading)
                Button {
                    withAnimation { importer.summary = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(IconButtonStyle(theme: theme, size: 24))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .id(summary.id)
            .task(id: summary.id) {
                try? await Task.sleep(for: .seconds(summary.isError ? 12 : 7))
                if importer.summary?.id == summary.id {
                    withAnimation(.easeInOut) { importer.summary = nil }
                }
            }
        }
    }
}

/// Shown when the library is empty: a friendly, obvious way in.
struct EmptyLibraryView: View {
    let theme: ThemeColor
    let onImportAppleMusic: () -> Void
    let onImportFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(theme.accentGradient)
            }
            VStack(spacing: 6) {
                Text("Bring your music in")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Import the songs you've downloaded in Apple Music, or point Mesh at any folder of audio files. You can also drag files straight into this window.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 10) {
                Button(action: onImportAppleMusic) {
                    Label("Import Apple Music Library", systemImage: "music.note")
                }
                .buttonStyle(PillButtonStyle(kind: .primary, theme: theme))
                Button(action: onImportFolder) {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle(kind: .ghost, theme: theme))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Color {
    /// White or black, whichever reads better on this colour (for text on an accent fill).
    var contrastingInk: Color {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        // Contrast with white beats contrast with black below about 0.18 luminance; lean white.
        return luminance > 0.4 ? .black : .white
    }
}
