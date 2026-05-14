// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Mock provider

private struct AFRMockProvider: RecommendationProvider {
    let releases: [AlbumRecommendation]
    let shouldThrow: Bool

    init(releases: [AlbumRecommendation] = [], shouldThrow: Bool = false) {
        self.releases = releases
        self.shouldThrow = shouldThrow
    }

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return Array(releases.prefix(limit))
    }
}

// MARK: - Helpers

@MainActor
private func makeVM(releases: [AlbumRecommendation] = [], shouldThrow: Bool = false) -> AllFreshReleasesViewModel {
    let provider = AFRMockProvider(releases: releases, shouldThrow: shouldThrow)
    let service = RecommendationService(providers: [provider])
    return AllFreshReleasesViewModel(recommendationService: service)
}

private func makeRelease(id: String, date: Date?) -> AlbumRecommendation {
    AlbumRecommendation(id: id, title: "Album \(id)", artistName: "Artist",
                        releaseDate: date, coverArtURL: nil, inLibrary: false)
}

private func date(year: Int, month: Int, day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
}

// MARK: - Tests

@Suite("AllFreshReleasesViewModel — grouping")
@MainActor
struct AllFreshReleasesViewModelTests {

    @Test("empty provider: groupedReleases is empty")
    func emptyGrouped() async {
        let vm = makeVM(releases: [])
        await vm.loadReleases()
        #expect(vm.groupedReleases.isEmpty)
    }

    @Test("releases without releaseDate are filtered out")
    func nilDatesFilteredOut() async {
        let releases = [
            makeRelease(id: "1", date: date(year: 2026, month: 5, day: 1)),
            makeRelease(id: "2", date: nil),
            makeRelease(id: "3", date: date(year: 2026, month: 5, day: 15))
        ]
        let vm = makeVM(releases: releases)
        await vm.loadReleases()
        let allItems = vm.groupedReleases.flatMap { $0.items }
        #expect(allItems.count == 2)
        #expect(!allItems.contains(where: { $0.id == "2" }))
    }

    @Test("releases across 3 months produce 3 sections in descending month order")
    func threeMonthsSectioned() async {
        let releases = [
            makeRelease(id: "may1", date: date(year: 2026, month: 5, day: 10)),
            makeRelease(id: "apr1", date: date(year: 2026, month: 4, day: 5)),
            makeRelease(id: "mar1", date: date(year: 2026, month: 3, day: 20)),
            makeRelease(id: "may2", date: date(year: 2026, month: 5, day: 1)),
            makeRelease(id: "apr2", date: date(year: 2026, month: 4, day: 25)),
        ]
        let vm = makeVM(releases: releases)
        await vm.loadReleases()

        #expect(vm.groupedReleases.count == 3)
        let cal = Calendar.current
        let months = vm.groupedReleases.map { cal.component(.month, from: $0.month) }
        #expect(months == [5, 4, 3], "Sections must be May, April, March in descending order")
    }

    @Test("items within a section are sorted by releaseDate descending")
    func itemsWithinSectionSortedDesc() async {
        let releases = [
            makeRelease(id: "early", date: date(year: 2026, month: 5, day: 1)),
            makeRelease(id: "late",  date: date(year: 2026, month: 5, day: 20)),
            makeRelease(id: "mid",   date: date(year: 2026, month: 5, day: 10)),
        ]
        let vm = makeVM(releases: releases)
        await vm.loadReleases()

        #expect(vm.groupedReleases.count == 1)
        let ids = vm.groupedReleases[0].items.compactMap { $0.id }
        #expect(ids == ["late", "mid", "early"], "Items within section must be newest first")
    }

    @Test("only releases with nil date produces empty groupedReleases")
    func allNilDatesYieldsEmpty() async {
        let releases = [
            makeRelease(id: "a", date: nil),
            makeRelease(id: "b", date: nil),
        ]
        let vm = makeVM(releases: releases)
        await vm.loadReleases()
        #expect(vm.groupedReleases.isEmpty)
    }

    @Test("throwing provider: no rethrow, groupedReleases stays empty")
    func throwingProviderGraceful() async {
        let vm = makeVM(shouldThrow: true)
        await vm.loadReleases()
        #expect(vm.groupedReleases.isEmpty)
    }

    @Test("isLoading resets to false after loadReleases completes")
    func loadingFlagResets() async {
        let vm = makeVM()
        #expect(!vm.isLoading)
        await vm.loadReleases()
        #expect(!vm.isLoading)
    }

    @Test("stable ordering: two releases on same date preserve fetch order within tie")
    func stableSameDateOrder() async {
        let sameDate = date(year: 2026, month: 5, day: 15)
        let releases = [
            makeRelease(id: "first",  date: sameDate),
            makeRelease(id: "second", date: sameDate),
        ]
        let vm = makeVM(releases: releases)
        await vm.loadReleases()

        #expect(vm.groupedReleases.count == 1)
        let ids = vm.groupedReleases[0].items.compactMap { $0.id }
        // Swift's sort is stable — equal elements keep their relative order from the fetch
        #expect(ids == ["first", "second"])
    }
}
