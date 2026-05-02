// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
#if os(iOS)
import UIKit
#endif

/// Centralized haptic feedback catalog.
///
/// Usage: `HapticFeedback.medium.trigger()`
///
/// Catalog:
/// - `.light`     — navigation, skip prev/next, toggle shuffle/repeat, secondary toggles
/// - `.medium`    — play/pause, swipe MiniPlayer, play album/playlist, QueueView skip
/// - `.heavy`     — destructive confirmations (trash download, remove all)
/// - `.selection` — continuous selection change (alphabet jump bar drag, pickers)
/// - `.success`   — download complete, pin to home
/// - `.warning`   — limit reached (max pinned, offline action)
/// - `.error`     — download failed, sync failed, playback failed
@MainActor
enum HapticFeedback {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error

    func trigger() {
        #if os(iOS)
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}
