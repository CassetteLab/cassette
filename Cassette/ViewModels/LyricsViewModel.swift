// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

@Observable
@MainActor
final class LyricsViewModel {
    private let lyricsService: LyricsService
    private let playerService: any PlayerServiceProtocol
    private let playerState: PlayerState
    private let songId: String
    private let serverId: UUID

    private(set) var state: State = .loading
    private(set) var currentLineIndex: Int?
    private(set) var availableLanguages: [String] = []
    var selectedLanguage: String?
    var autoScrollEnabled: Bool = true
    private(set) var isUserScrolling: Bool = false

    private var lyricsList: LyricsList?
    private var trackingTimer: Timer?
    private var resumeTask: Task<Void, Never>?

    nonisolated enum State: Equatable {
        case loading
        case loaded(StructuredLyrics)
        case empty
        case unsupported
        case error(String)
    }

    init(
        songId: String,
        serverId: UUID,
        lyricsService: LyricsService,
        playerService: any PlayerServiceProtocol,
        playerState: PlayerState
    ) {
        self.songId = songId
        self.serverId = serverId
        self.lyricsService = lyricsService
        self.playerService = playerService
        self.playerState = playerState
    }

    // MARK: - Load

    func load() async {
        state = .loading
        do {
            let list = try await lyricsService.fetchLyrics(forSongId: songId, serverId: serverId)
            lyricsList = list
            applyCurrentLanguage()
        } catch LyricsError.notSupportedByServer {
            state = .unsupported
        } catch LyricsError.notFound {
            state = .empty
        } catch let error as LyricsError {
            state = .error(networkErrorMessage(from: error))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Line tracking

    func update(elapsedMs: Int) {
        guard case .loaded(let structured) = state, structured.synced else {
            currentLineIndex = nil
            return
        }
        let adjustedMs = elapsedMs - structured.offset
        var newIndex: Int? = nil
        for (index, line) in structured.line.enumerated() {
            guard let start = line.start else { continue }
            if start <= adjustedMs {
                newIndex = index
            } else {
                break
            }
        }
        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
        }
    }

    // MARK: - Seek

    func userTapped(lineIndex: Int) {
        guard case .loaded(let structured) = state, structured.synced else { return }
        guard lineIndex < structured.line.count else { return }
        guard let startMs = structured.line[lineIndex].start else { return }
        let targetSeconds = TimeInterval(startMs + structured.offset) / 1000.0
        Task { [weak self] in
            await self?.playerService.seek(to: targetSeconds)
        }
    }

    // MARK: - Auto-scroll

    func userStartedScrolling() {
        isUserScrolling = true
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.isUserScrolling = false }
        }
    }

    func userStoppedScrolling() {
        userStartedScrolling()
    }

    // MARK: - Language selection

    func selectLanguage(_ lang: String) {
        guard selectedLanguage != lang else { return }
        selectedLanguage = lang
        currentLineIndex = nil
        applyCurrentLanguage()
    }

    // MARK: - Timer lifecycle

    func startTracking() {
        stopTracking()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.update(elapsedMs: Int(self.playerState.position * 1000))
            }
        }
    }

    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        resumeTask?.cancel()
        resumeTask = nil
    }

    // MARK: - Private helpers

    private func applyCurrentLanguage() {
        guard let list = lyricsList else { return }
        var seen = Set<String>()
        availableLanguages = list.structuredLyrics
            .compactMap { $0.lang }
            .filter { seen.insert($0).inserted }
        let best = lyricsService.selectBestLanguage(from: list, preferred: selectedLanguage)
        currentLineIndex = nil
        state = best.map { .loaded($0) } ?? .empty
    }

    private func networkErrorMessage(from error: LyricsError) -> String {
        if case .networkError(let msg) = error { return msg }
        return error.localizedDescription
    }
}
