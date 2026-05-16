// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

struct FreshReleaseDetailSheet: View {
    let release: AlbumRecommendation
    let providers: [ExternalReleaseProvider]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CassetteSpacing.l) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ExternalCoverView(url: release.coverArtURL) {
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.large)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                    Text(release.title)
                        .font(.title2.bold())

                    Text(release.artistName)
                        .font(.cassetteCellTitle)
                        .foregroundStyle(.secondary)

                    if let date = release.releaseDate {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                externalLinksSection
            }
            .padding(CassetteSpacing.l)
        }
        .navigationTitle(release.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            for provider in providers {
                if provider.buildURL(artistName: release.artistName, albumTitle: release.title) == nil {
                    Logger.integrations.warning("buildURL returned nil for provider '\(provider.name, privacy: .public)'")
                }
            }
        }
    }

    @ViewBuilder
    private var externalLinksSection: some View {
        if providers.isEmpty {
            if let id = release.id,
               let lbURL = URL(string: "https://listenbrainz.org/release-group/\(id)") {
                externalLinkButton(title: "View on ListenBrainz", url: lbURL)
            }
        } else {
            VStack(spacing: CassetteSpacing.s) {
                ForEach(providers) { provider in
                    if let url = provider.buildURL(artistName: release.artistName, albumTitle: release.title) {
                        externalLinkButton(title: "View on \(provider.name)", url: url)
                    }
                }
            }
        }
    }

    private func externalLinkButton(title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
            }
            .font(.cassetteCellTitle)
            .padding(CassetteSpacing.m)
            .frame(maxWidth: .infinity)
            .background(Color.cassetteAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
            .foregroundStyle(Color.cassetteAccent)
        }
        .buttonStyle(.plain)
    }
}
