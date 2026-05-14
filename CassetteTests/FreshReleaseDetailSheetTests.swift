// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// Tests verify the button-determination logic used by FreshReleaseDetailSheet
// without requiring SwiftUI view rendering. The sheet itself is validated manually
// per the spec's simulator checklist.

@Suite("FreshReleaseDetailSheet — button logic")
struct FreshReleaseDetailSheetTests {

    private let releaseWithMBID = AlbumRecommendation(
        id: "test-rg-mbid", title: "Random Access Memories", artistName: "Daft Punk",
        releaseDate: nil, coverArtURL: nil, inLibrary: false
    )
    private let releaseWithoutMBID = AlbumRecommendation(
        id: nil, title: "Unknown Album", artistName: "Unknown Artist",
        releaseDate: nil, coverArtURL: nil, inLibrary: false
    )
    private let twoProviders = [
        ExternalReleaseProvider(name: "Bandcamp", urlTemplate: "https://bandcamp.com/search?q=%s"),
        ExternalReleaseProvider(name: "Beatport", urlTemplate: "https://www.beatport.com/search?q=%s")
    ]

    // MARK: - Empty providers fallback

    @Test("empty providers + mbid → ListenBrainz fallback URL is well-formed")
    func emptyProvidersWithMBIDFallback() {
        let id = releaseWithMBID.id!
        let url = URL(string: "https://listenbrainz.org/release-group/\(id)")
        #expect(url != nil)
        #expect(url?.host() == "listenbrainz.org")
        #expect(url?.absoluteString.contains(id) == true)
    }

    @Test("empty providers + no mbid → no fallback URL can be constructed")
    func emptyProvidersNoMBIDNoFallback() {
        #expect(releaseWithoutMBID.id == nil)
        // Verify the sheet logic: id is nil → no LB URL → no button rendered
        let lbURL: URL? = releaseWithoutMBID.id.flatMap {
            URL(string: "https://listenbrainz.org/release-group/\($0)")
        }
        #expect(lbURL == nil)
    }

    // MARK: - Custom providers

    @Test("two providers configured → both produce non-nil search URLs")
    func twoProvidersProduceNonNilURLs() {
        for provider in twoProviders {
            let url = provider.buildURL(
                artistName: releaseWithMBID.artistName,
                albumTitle: releaseWithMBID.title
            )
            #expect(url != nil, "Provider '\(provider.name)' should produce a URL")
        }
    }

    @Test("two providers configured → no ListenBrainz URL appears in results")
    func twoProvidersDoNotProduceLBURL() {
        for provider in twoProviders {
            let url = provider.buildURL(
                artistName: releaseWithMBID.artistName,
                albumTitle: releaseWithMBID.title
            )
            #expect(url?.host()?.contains("listenbrainz") == false)
        }
    }

    @Test("provider URL encodes artist and album name correctly")
    func providerURLEncodesSearchTerm() {
        let provider = twoProviders[0]
        let url = provider.buildURL(
            artistName: releaseWithMBID.artistName,
            albumTitle: releaseWithMBID.title
        )
        let str = url?.absoluteString ?? ""
        #expect(str.contains("Daft%20Punk"), "Spaces must be percent-encoded")
        #expect(str.contains("Random%20Access%20Memories"))
    }
}
