//
//  QualityLogos.swift
//  Mesh Player (shared by the Mac and iPhone apps)
//
//  The Dolby Atmos and Lossless marks, drawn from template images so they take the
//  surrounding text colour, like Apple Music's quality badges.
//

import SwiftUI

/// Which mark to draw.
enum QualityLogo: String {
    /// The double-D Dolby icon on its own, for song rows.
    case dolbyIcon = "DolbyIcon"
    /// "Dolby Atmos" on one line, for album headers and the player.
    case dolbyAtmos = "DolbyAtmosWide"
    /// "Dolby / ATMOS" stacked, for large spots like the audio quality popover.
    case dolbyAtmosStacked = "DolbyAtmosStacked"
    /// Apple Lossless' wave mark.
    case lossless = "LosslessIcon"
}

struct QualityLogoImage: View {
    let logo: QualityLogo
    /// Height in points; the width follows the logo's proportions.
    var height: CGFloat

    var body: some View {
        Image(logo.rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(logo == .lossless ? "Lossless" : "Dolby Atmos")
    }
}

/// A compact quality badge: the Dolby Atmos wordmark, or the Lossless mark with its label.
/// Returns nothing for lossy formats.
struct QualityMark: View {
    let isAtmos: Bool
    /// "Lossless", "Hi-Res Lossless", or any other format string.
    let format: String
    var height: CGFloat = 10

    var body: some View {
        if isAtmos {
            QualityLogoImage(logo: .dolbyAtmos, height: height)
        } else if format.localizedCaseInsensitiveContains("lossless") {
            HStack(spacing: height * 0.3) {
                QualityLogoImage(logo: .lossless, height: height * 0.85)
                Text(format.localizedCaseInsensitiveContains("hi-res") ? "Hi-Res Lossless" : "Lossless")
                    .font(.system(size: height * 1.05, weight: .semibold))
            }
        }
    }
}
