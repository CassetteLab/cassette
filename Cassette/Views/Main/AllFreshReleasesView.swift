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

    @ViewBuilder
    private var scrollContent: some View {
        let sv = ScrollView {
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
        #if os(macOS)
        // .hiddenTitleBar + fullSizeContentView gives the detail column a top safe-area
        // equal to the toolbar height. With titlebarAppearsTransparent = true the toolbar
        // is invisible, but pinned section headers still stick at the safe-area boundary
        // (bottom of the invisible toolbar) rather than at the true window top.
        // ignoresSafeArea(.container, edges: .top) extends the scroll view frame to y = 0
        // so pinned headers pin at the actual visible top of the detail column.
        if #available(macOS 26.0, *) {
            sv
                .ignoresSafeArea(.container, edges: .top)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            sv.ignoresSafeArea(.container, edges: .top)
        }
        #else
        if #available(iOS 26.0, *) {
            sv.scrollEdgeEffectHidden(true, for: .top)
        } else {
            sv
        }
        #endif
    }
}
