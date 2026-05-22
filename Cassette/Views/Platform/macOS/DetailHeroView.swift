// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct DetailHeroView: View {
    let coverArtId: String?
    let title: String
    let primaryLine: String?
    let secondaryLine: String?
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            coverSection
            metadataSection
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CassetteMacOSLayout.heroHeight)
    }

    private var coverSection: some View {
        Group {
            if let id = coverArtId {
                CoverArtView(id: id, size: Int(CassetteMacOSLayout.heroCoverArtSize))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: CassetteMacOSLayout.heroCoverArtSize, height: CassetteMacOSLayout.heroCoverArtSize)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)

                if let primaryLine {
                    Text(primaryLine)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.cassetteAccent)
                        .lineLimit(1)
                }

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: primaryAction) {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.cassetteAccent)

                Button(action: secondaryAction) {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: CassetteMacOSLayout.heroCoverArtSize)
    }
}
#endif
