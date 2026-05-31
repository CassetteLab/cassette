// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation

/// Sendable snapshot of crossfade settings for crossing actor boundaries.
/// Captured from CrossfadeSettings on the MainActor before passing into PlayerService.
nonisolated struct CrossfadeConfig: Sendable {
    let duration: Double
}

/// User-configurable crossfade preferences persisted in UserDefaults.
/// @Observable so SettingsView updates live when the user changes settings.
/// Injected into AppContainer; services capture a CrossfadeConfig snapshot via MainActor.run.
@Observable
@MainActor
final class CrossfadeSettings {
    // MARK: - Storage (observation ignored)

    @ObservationIgnored private var _duration: Double

    // MARK: - Visible properties (manual observation hooks)

    var duration: Double {
        get {
            access(keyPath: \.duration)
            return _duration
        }
        set {
            let clamped = max(Self.minDuration, min(Self.maxDuration, newValue))
            withMutation(keyPath: \.duration) {
                _duration = clamped
            }
            UserDefaults.standard.set(clamped, forKey: Self.durationKey)
        }
    }

    // MARK: - Defaults, bounds & keys

    static let defaultDuration: Double = 0
    static let minDuration: Double = 0
    static let maxDuration: Double = 12

    private static let durationKey = "cassette.crossfade.duration"

    // MARK: - Derived

    /// Captures a sendable snapshot for crossing into actor-isolated code.
    var config: CrossfadeConfig {
        CrossfadeConfig(duration: _duration)
    }

    // MARK: - Init

    init() {
        if UserDefaults.standard.object(forKey: Self.durationKey) != nil {
            let stored = UserDefaults.standard.double(forKey: Self.durationKey)
            _duration = max(Self.minDuration, min(Self.maxDuration, stored))
        } else {
            _duration = Self.defaultDuration
        }
    }
}
