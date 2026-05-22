// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct AllFreshReleasesView: View {
    @Environment(\.appContainer) private var container
    let vm: AllFreshReleasesViewModel

    @State private var selectedRelease: AlbumRecommendation?

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private var gridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 130))]
        #else
        [GridItem(.adaptive(minimum: 110))]
        #endif
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.groupedReleases.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Releases", systemImage: "sparkles")
                } description: {
                    Text("Nothing in the past 3 months from artists you listen to.")
                }
            } else {
                scrollContent
            }
        }
        .navigationTitle("Fresh Releases")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.loadReleases() }
        .sheet(isPresented: Binding(
            get: { selectedRelease != nil },
            set: { if !$0 { selectedRelease = nil } }
        )) {
            if let release = selectedRelease {
                NavigationStack {
                    FreshReleaseDetailSheet(
                        release: release,
                        providers: container?.externalProvidersStore.load() ?? []
                    )
                }
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(vm.groupedReleases, id: \.month) { section in
                    Section {
                        LazyVGrid(columns: gridColumns, spacing: CassetteSpacing.m) {
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, release in
                                FreshReleaseAlbumCell(release: release) {
                                    selectedRelease = release
                                }
                            }
                        }
                        .padding(.horizontal, CassetteSpacing.m)
                        .padding(.bottom, CassetteSpacing.l)
                    } header: {
                        Text(Self.monthFormatter.string(from: section.month))
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, CassetteSpacing.m)
                            .padding(.vertical, CassetteSpacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial)
                    }
                }
            }
        }
    }
}
