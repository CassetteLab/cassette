// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftUI

struct WrappedYearCard: View {
    let year: Int
    let firstTrack: TopTrackEntry?
    let lastTrack: TopTrackEntry?
    let playlistId: String?
    var parallaxOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var yearString: String { String(year) }

    var body: some View {
        Group {
            if let pid = playlistId {
                NavigationLink {
                    PlaylistDetailView(playlistId: pid, name: "Cassette Wrapped \(yearString)")
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    Logger.wrapped.debug("[WRAPPED-YEAR-CARD] tapped year=\(year, privacy: .public) playlistId=\(pid, privacy: .public)")
                })
            } else {
                cardContent
                    .grayscale(0.5)
                    .opacity(0.7)
            }
        }
    }

    private var cardContent: some View {
        let palette = WrappedYearPalette.colors(for: year)
        return Color.clear
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .overlay {
                MeshGradientBackground(palette: palette, animated: !reduceMotion)
                    .frame(height: 380 + 80)
                    .frame(maxWidth: .infinity)
                    .offset(y: parallaxOffset)
            }
            .overlay { overlayContent }
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.hero, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cassette Wrapped")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                Spacer()
                if playlistId != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Text(yearString)
                .font(.system(size: 140, weight: .black, design: .rounded))
                .kerning(-4)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .frame(maxWidth: .infinity, alignment: .trailing)

            subtitleView
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .lineLimit(2)
                .padding(.top, CassetteSpacing.xs)
        }
        .padding(CassetteSpacing.l)
    }

    @ViewBuilder
    private var subtitleView: some View {
        if playlistId == nil {
            Text("Aucune playlist générée pour le moment")
        } else if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            Text("Started with \(first.title) · Ended with \(last.title)")
        } else if let first = firstTrack {
            Text("Your year started with \(first.title)")
        } else {
            Text("Cassette Wrapped \(yearString)")
        }
    }

    private var accessibilityLabel: String {
        var label = "Cassette Wrapped \(yearString)"
        if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            label += ". Started with \(first.title), ended with \(last.title)"
        } else if let first = firstTrack {
            label += ". Your year started with \(first.title)"
        }
        label += playlistId != nil ? ". Tap to open playlist." : "."
        return label
    }
}
