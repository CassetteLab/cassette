// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct SimilarArtistCell: View {
    let recommendation: SimilarArtistRecommendation
    let externalImageURL: URL?
    let onOutOfLibraryTap: () -> Void

    var body: some View {
        if recommendation.inLibrary {
            cellContent
        } else {
            Button(action: onOutOfLibraryTap) {
                cellContent
            }
            .buttonStyle(.plain)
        }
    }

    private var cellContent: some View {
        VStack(spacing: CassetteSpacing.xs) {
            if recommendation.inLibrary, let coverArt = recommendation.coverArt {
                CoverArtView(id: coverArt, size: 128, placeholderSystemImage: "person.fill")
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else {
                ExternalCoverView(url: externalImageURL) {
                    ArtistPlaceholderView(name: recommendation.name, size: 64)
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            }

            Text(recommendation.name)
                .font(.cassetteCaption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
