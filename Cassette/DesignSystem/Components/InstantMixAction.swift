// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// The SF Symbol used everywhere an Instant Mix can be started, so the action reads the same across menus.
let instantMixSymbol = "sparkles"

/// Builds and starts an Instant Mix from a seed, surfacing the outcome, so every entry point (song / album /
/// artist menus, detail headers, the player) behaves identically. `instantMixEmpty` is shown as a gentle info
/// toast (the server simply has no similarity data yet), other failures as an error toast. Returns only once
/// playback has started (or failed) — callers with a persistent button await it to drive a loading spinner.
@MainActor
func runInstantMix(from seed: InstantMixSeed, using container: AppContainer?, startingWith seedTrack: DisplayableSong? = nil) async {
    guard let container else { return }
    do {
        try await container.playerService.playInstantMix(from: seed, startingWith: seedTrack)
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

/// Fire-and-forget Instant Mix for menu items (the menu dismisses on tap, so there is no spam risk and no
/// need for a spinner). Persistent buttons should instead `await runInstantMix` behind their own loading state.
@MainActor
func startInstantMix(from seed: InstantMixSeed, using container: AppContainer?, startingWith seedTrack: DisplayableSong? = nil) {
    Task { await runInstantMix(from: seed, using: container, startingWith: seedTrack) }
}
