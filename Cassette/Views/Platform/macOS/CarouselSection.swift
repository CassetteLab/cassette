// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct CarouselSection<Content: View>: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack {
                Text(title)
                    .font(.cassetteSectionTitle)
                    .padding(.leading, CassetteSpacing.m)
                Spacer()
                if let onSeeAll {
                    Button("See All", action: onSeeAll)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.cassetteAccent)
                        .buttonStyle(.plain)
                        .padding(.trailing, CassetteSpacing.m)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CassetteSpacing.m) {
                    content()
                }
                .scrollTargetLayout()
                .padding(.horizontal, CassetteSpacing.m)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}
#endif
