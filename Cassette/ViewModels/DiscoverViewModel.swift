// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

@Observable
@MainActor
final class DiscoverViewModel {
    private let libraryService: any LibraryServiceProtocol
    private let recommendationService: RecommendationService

    // MARK: - State

    private(set) var recentlyPlayed: [AlbumID3] = []
    private(set) var mostPlayed: [AlbumID3] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?
    private(set) var freshReleases: [AlbumRecommendation] = []
    private(set) var isLoadingFreshReleases: Bool = false

    init(libraryService: any LibraryServiceProtocol, recommendationService: RecommendationService) {
        self.libraryService = libraryService
        self.recommendationService = recommendationService
    }

    // MARK: - Derived state

    /// True when the initial fetch is in progress and we have nothing to show yet.
    var isInitialLoading: Bool {
        isLoading && recentlyPlayed.isEmpty && mostPlayed.isEmpty
    }

    /// True when load failed and we have nothing to show.
    var isErrorState: Bool {
        loadError != nil && recentlyPlayed.isEmpty && mostPlayed.isEmpty
    }

    // MARK: - Loading

    func load(forceRefresh: Bool = false) async {
        if !forceRefresh, !recentlyPlayed.isEmpty, !mostPlayed.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let recent = libraryService.recentlyPlayedAlbums(size: 35)
            async let frequent = libraryService.mostPlayedAlbums(size: 35)
            let (recentResult, frequentResult) = try await (recent, frequent)
            self.recentlyPlayed = recentResult
            self.mostPlayed = frequentResult
            self.loadError = nil
        } catch {
            self.loadError = error
            Logger.discover.error("Failed to load Discover sections: \(error, privacy: .public)")
        }
    }

    func loadFreshReleases() async {
        isLoadingFreshReleases = true
        defer { isLoadingFreshReleases = false }
        do {
            let fetched = try await recommendationService.freshReleases(limit: 10, daysWindow: 7)
            freshReleases = fetched.sorted {
                ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
            }
        } catch {
            Logger.discover.error("Failed to load fresh releases: \(error, privacy: .public)")
        }
    }
}
