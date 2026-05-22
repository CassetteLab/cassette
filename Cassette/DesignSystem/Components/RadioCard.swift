// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import OSLog

struct RadioCard: View {
    let station: InternetRadioStation

    @Environment(\.appContainer) private var container

    var body: some View {
        Button {
            Task { await play() }
        } label: {
            ZStack(alignment: .bottomLeading) {
                cardBackground
                bottomOverlay
            }
            .frame(width: 140, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(station.name)")
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let coverArt = station.coverArt, !coverArt.isEmpty {
            ZStack {
                Color.black
                CoverArtCard(id: coverArt, size: 160)
            }
            .frame(width: 140, height: 160)
            .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.161, green: 0.475, blue: 1.0),
                    Color(red: 0.000, green: 0.588, blue: 0.533)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }

    private var bottomOverlay: some View {
        Text(station.name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CassetteSpacing.s)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func play() async {
        guard let container else { return }
        HapticFeedback.medium.trigger()
        do {
            try await container.playerService.playRadio(station)
        } catch {
            Logger.radio.error("RadioCard: playRadio failed — \(error)")
        }
    }
}
