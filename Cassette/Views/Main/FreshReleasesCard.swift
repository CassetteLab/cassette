// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Horizontal scroll card showing personalized fresh releases from ListenBrainz.
/// Self-hides entirely when releases are empty and not loading.
struct FreshReleasesCard: View {
    let releases: [AlbumRecommendation]
    let isLoading: Bool
    let onTap: (AlbumRecommendation) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        if isLoading || !releases.isEmpty {
            VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                HStack {
                    Text("Fresh Releases")
                        .font(.cassetteSectionTitle)
                    Spacer(minLength: 0)
                    if !releases.isEmpty {
                        Button(action: onSeeAll) {
                            Text("See all")
                                .font(.cassetteCaption)
                                .foregroundStyle(Color.cassetteAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CassetteSpacing.m)

                if isLoading {
                    skeletonScroll
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: CassetteSpacing.s) {
                            ForEach(Array(releases.enumerated()), id: \.offset) { _, release in
                                FreshReleaseAlbumCell(release: release) {
                                    onTap(release)
                                }
                                .frame(width: 140)
                            }
                            seeAllCell
                        }
                        .padding(.horizontal, CassetteSpacing.m)
                    }
                }
            }
        }
    }

    private var seeAllCell: some View {
        Button(action: onSeeAll) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous)
                                .fill(Color.cassetteAccent.opacity(0.08))
                            VStack(spacing: CassetteSpacing.xs) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.cassetteAccent)
                                Text("See all")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(Color.cassetteAccent)
                            }
                        }
                    }
                Text("Past 90 days")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
    }

    private var skeletonScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CassetteSpacing.s) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                        SkeletonBlock(width: 140, height: 140, cornerRadius: CassetteCornerRadius.standard)
                        SkeletonBlock(width: 110, height: 12)
                        SkeletonBlock(width: 80, height: 10)
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, CassetteSpacing.m)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cell

struct FreshReleaseAlbumCell: View {
    let release: AlbumRecommendation
    let onTap: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ExternalCoverView(url: release.coverArtURL) {
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .cassetteCoverStyle()

                Text(release.title)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)

                Text(release.artistName)
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let date = release.releaseDate {
                    Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .font(.cassetteCaption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
