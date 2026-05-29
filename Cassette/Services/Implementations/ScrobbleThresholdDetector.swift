// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// Pure value type that tracks whether the scrobble threshold has been crossed for one track.
/// Threshold: duration ≥ 30 s AND accumulated play time ≥ min(240 s, 0.5 × duration).
/// One-shot per track: `check` returns true exactly once; call `reset()` on every track change.
struct ScrobbleThresholdDetector {
    private(set) var fired: Bool = false

    /// Evaluates the threshold. Returns true the first time it is crossed, false thereafter.
    mutating func check(duration: TimeInterval, accumulated: TimeInterval) -> Bool {
        guard !fired else { return false }
        guard duration >= 30 else { return false }
        guard accumulated >= min(240, duration * 0.5) else { return false }
        fired = true
        return true
    }

    mutating func reset() {
        fired = false
    }
}
