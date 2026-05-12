// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import UIKit

/// Cover art thumbnail shared between Small and Medium widget views.
/// Caller is responsible for applying `.frame()` before this view.
struct WidgetCoverArtView: View {
    let image: UIImage?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.15))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// "Lecture" play CTA shared between Small and Medium widget views.
struct WidgetPlayButton: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.caption)
            Text("Lecture")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.2), in: Capsule())
    }
}
