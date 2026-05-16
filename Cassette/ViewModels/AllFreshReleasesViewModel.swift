// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

@Observable
@MainActor
final class AllFreshReleasesViewModel {
    private let recommendationService: RecommendationService

    private(set) var groupedReleases: [(month: Date, items: [AlbumRecommendation])] = []
    private(set) var isLoading: Bool = false

    init(recommendationService: RecommendationService) {
        self.recommendationService = recommendationService
    }

    func loadReleases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await recommendationService.freshReleases(limit: 100, daysWindow: 90)
            let sorted = fetched
                .filter { $0.releaseDate != nil }
                .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
            groupedReleases = group(sorted)
        } catch {
            Logger.discover.warning("AllFreshReleasesViewModel: failed to load releases — \(error, privacy: .public)")
        }
    }

    private func group(_ sorted: [AlbumRecommendation]) -> [(month: Date, items: [AlbumRecommendation])] {
        let cal = Calendar.current
        var groups: [Date: [AlbumRecommendation]] = [:]
        for release in sorted {
            guard let date = release.releaseDate else { continue }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let monthStart = cal.date(from: comps) else { continue }
            groups[monthStart, default: []].append(release)
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { (month: $0.key, items: $0.value) }
    }
}
