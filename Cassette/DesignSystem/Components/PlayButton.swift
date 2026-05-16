// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Primary action button — accent capsule with play icon. Used in album and playlist headers.
struct PlayButton: View {
    let action: () -> Void
    var label: String = "Play"
    var isDisabled: Bool = false

    var body: some View {
        Button {
            HapticFeedback.medium.trigger()
            action()
        } label: {
            Label(label, systemImage: "play.fill")
                .font(.cassetteCellTitle)
                .foregroundStyle(Color.cassetteAccentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CassetteSpacing.m)
                .background(isDisabled ? Color.cassetteAccent.opacity(0.4) : Color.cassetteAccent)
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
