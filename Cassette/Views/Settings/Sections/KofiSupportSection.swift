// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftUI

/// "Cassette is free, forever." over the Ko-fi button, free-standing rather than on a card.
/// Closes Settings on iOS and the About tab on macOS, just above `SupportersSection`.
struct KofiSupportSection: View {
    var body: some View {
        #if os(macOS)
        // Grouped forms on macOS ignore `listRowBackground`, so a row would sit on a card.
        // A footer has no background, which keeps the button free-standing as on iOS.
        Section {} footer: {
            content
        }
        #else
        Section {
            content
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        #endif
    }

    private var content: some View {
        VStack(spacing: 2) {
            Text("Cassette is free, forever.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button {
                Logger.settings.debug("Ko-fi support button tapped")
                ExternalLinkOpener.open(CassetteURLs.kofi)
            } label: {
                Image("kofiButton")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 140)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            #if os(macOS)
            // The default macOS style would draw a push-button bezel around the artwork.
            .buttonStyle(.plain)
            #endif
        }
    }
}
