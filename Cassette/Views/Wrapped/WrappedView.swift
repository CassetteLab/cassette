// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CassetteSpacing.xl) {
                WrappedStatHero(data: nil)
                WrappedTopArtistsSection(artists: [])
                WrappedTopTracksSection(tracks: [])
                WrappedTopAlbumsSection(albums: [])
                WrappedRewardsSection(data: nil)
                WrappedYearCard(year: Calendar.current.component(.year, from: Date()))
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.m)
            .padding(.bottom, CassetteSpacing.xl)
        }
        .cassetteContentWidth()
        .navigationTitle("Wrapped")
    }
}
