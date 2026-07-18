// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Primary action button — accent capsule with play icon. Used in album and playlist headers.
struct PlayButton: View {
    let action: () -> Void
    var label: LocalizedStringKey = "Play"
    var isDisabled: Bool = false
    var accentColor: Color = CassetteColors.accent
    /// Label/glyph color. Default white (`cassetteAccentText`) preserves existing callers; the hero passes the
    /// contrast variant's foreground (the cover's dominant color on a dark cover).
    var labelColor: Color = Color.cassetteAccentText

    var body: some View {
        Button {
            HapticFeedback.medium.trigger()
            action()
        } label: {
            Label(label, systemImage: "play.fill")
                .font(.cassetteCellTitle)
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CassetteSpacing.m)
                .background(isDisabled ? accentColor.opacity(0.4) : accentColor)
                .clipShape(Capsule())
        }
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: CassetteSpacing.l) {
        PlayButton(action: {})
        PlayButton(action: {}, label: "Shuffle", isDisabled: true)
    }
    .padding()
}
