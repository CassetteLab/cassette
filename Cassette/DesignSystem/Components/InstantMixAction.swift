// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// The SF Symbol used everywhere an Instant Mix can be started, so the action reads the same across menus.
let instantMixSymbol = "sparkles"

/// Starts an Instant Mix from a seed and surfaces the outcome, so every entry point (song / album / artist
/// menus, detail headers, the player) behaves identically. `instantMixEmpty` is shown as a gentle info toast
/// (the server simply has no similarity data yet), other failures as an error toast.
@MainActor
func startInstantMix(from seed: InstantMixSeed, using container: AppContainer?) {
    guard let container else { return }
    Task {
        do {
            try await container.playerService.playInstantMix(from: seed)
        } catch CassetteError.instantMixEmpty {
            container.toastService.show(
                "No similar tracks found for an Instant Mix yet.",
                style: .info,
                duration: 4.0
            )
        } catch {
            Logger.player.error("[INSTANT-MIX] failed: \(error, privacy: .public)")
            container.toastService.showError("Couldn't start Instant Mix.")
        }
    }
}
