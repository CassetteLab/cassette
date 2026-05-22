// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct NowPlayingBarsIndicator: View {
    let isPlaying: Bool

    private let delays: [Double] = [0.0, 0.15, 0.30]
    @State private var heights: [CGFloat] = [4, 8, 4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.cassetteAccent)
                    .frame(width: 3, height: heights[i])
            }
        }
        .frame(width: 14, height: 14, alignment: .bottom)
        .onAppear { if isPlaying { startAnimating() } }
        .onChange(of: isPlaying) { _, playing in
            if playing { startAnimating() } else { stopAnimating() }
        }
    }

    private func startAnimating() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.45)
                .repeatForever(autoreverses: true)
                .delay(delays[i])
            ) {
                heights[i] = i == 1 ? 14 : 10
            }
        }
    }

    private func stopAnimating() {
        withAnimation(.easeInOut(duration: 0.2)) {
            heights = [3, 3, 3]
        }
    }
}
