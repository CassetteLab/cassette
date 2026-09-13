// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// The Smart Shuffle control, shared by the home card, the Discover card and the player's menu.
///
/// Those three carried byte-identical copies of this logic. There is one mode, so there is one
/// way to toggle it and one way to report it failing — which also means a surface cannot drift
/// into starting the mode without being able to leave it, the bug this replaces.
@MainActor
enum SmartShuffleControl {
    /// Enters Smart Shuffle, or leaves it and restores the queue it replaced.
    static func toggle(_ container: AppContainer?) async {
        guard let container else { return }
        do {
            try await container.playerService.toggleSmartShuffle()
        } catch {
            container.toastService.showError(errorMessage(from: error))
        }
    }

    /// Kept as plain strings, exactly as the three copies had them: these were never localized,
    /// and wrapping them now would add catalog keys this change has no reason to introduce.
    static func errorMessage(from error: Error) -> String {
        if case CassetteError.smartShuffleEmpty = error {
            return "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."
        }
        return "Smart Shuffle failed. Please try again."
    }
}
