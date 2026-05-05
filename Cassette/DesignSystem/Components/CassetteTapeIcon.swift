// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Cassette tape silhouette shape. Fill with `FillStyle(eoFill: true)` to punch through reel holes and tape window.
struct CassetteTapeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let corner = min(w, h) * 0.12

        // Outer body
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: corner, height: corner)
        )

        // Left reel hole
        let reelR = w * 0.165
        let reelY = h * 0.40
        path.addEllipse(in: CGRect(
            x: w * 0.285 - reelR, y: reelY - reelR,
            width: reelR * 2, height: reelR * 2
        ))

        // Right reel hole
        path.addEllipse(in: CGRect(
            x: w * 0.715 - reelR, y: reelY - reelR,
            width: reelR * 2, height: reelR * 2
        ))

        // Tape window (bottom centre)
        let winW = w * 0.50
        let winH = h * 0.185
        let winCorner = winH * 0.40
        path.addRoundedRect(
            in: CGRect(x: (w - winW) / 2, y: h * 0.64, width: winW, height: winH),
            cornerSize: CGSize(width: winCorner, height: winCorner)
        )

        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        CassetteTapeIcon()
            .fill(.orange, style: FillStyle(eoFill: true))
            .frame(width: 80, height: 52)

        CassetteTapeIcon()
            .fill(.white, style: FillStyle(eoFill: true))
            .frame(width: 48, height: 32)
            .padding(8)
            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
    }
    .padding()
}
