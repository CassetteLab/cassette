// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

/// Asks iOS to keep the app running while a long piece of work finishes after the user leaves.
///
/// Cassette declares the `audio` background mode, so ANY work runs freely while music plays — which
/// covers Instant Mix, since the seed track starts before the mix is built. The gap is work started
/// with nothing playing: browsing, then backgrounding. Without an assertion the app is suspended
/// within a few seconds and the work simply freezes mid-flight.
///
/// What this buys is a grace period, roughly half a minute — not unlimited time. Anything longer
/// still has to survive being interrupted, which is why the mood sync records its progress per mood
/// rather than per run.
nonisolated enum BackgroundActivity {

    #if os(iOS)
    /// Holds the assertion id so the expiration handler can end the task without mutating a
    /// captured `var` — which Swift 6 forbids inside a `@Sendable` closure. Access is main-thread
    /// only: both `beginBackgroundTask` and its handler are invoked on the main thread.
    private final class TaskBox: @unchecked Sendable {
        var id: UIBackgroundTaskIdentifier = .invalid
    }
    #endif

    /// Runs `operation` inside a background task assertion. A no-op on macOS, where apps are not
    /// suspended on losing focus.
    static func run<T: Sendable>(_ name: String, operation: @Sendable () async -> T) async -> T {
        #if os(iOS)
        let identifier = await MainActor.run { () -> UIBackgroundTaskIdentifier in
            // The expiration handler must end the assertion: iOS terminates the app outright if the
            // time runs out with the task still open. The work itself is left to be suspended, which
            // is exactly what would have happened without the assertion at all.
            let box = TaskBox()
            box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
                Logger.boot.warning("[BACKGROUND] '\(name, privacy: .public)' ran out of time — suspending")
                if box.id != .invalid {
                    UIApplication.shared.endBackgroundTask(box.id)
                    box.id = .invalid
                }
            }
            return box.id
        }
        defer {
            if identifier != .invalid {
                Task { @MainActor in UIApplication.shared.endBackgroundTask(identifier) }
            }
        }
        return await operation()
        #else
        return await operation()
        #endif
    }
}
