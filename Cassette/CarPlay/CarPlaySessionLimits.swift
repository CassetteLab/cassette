// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import OSLog

/// Tracks what the car currently forbids.
///
/// CarPlay cuts keyboard entry while the vehicle is moving — a system rule, not ours. Without this,
/// the Search row stays tappable and simply does nothing, which reads as a broken app rather than a
/// safety restriction.
@MainActor
final class CarPlaySessionLimits: NSObject, CPSessionConfigurationDelegate {
    private var configuration: CPSessionConfiguration?
    private let onChange: @MainActor () -> Void

    var isKeyboardAvailable: Bool {
        guard let configuration else { return true }
        return !configuration.limitedUserInterfaces.contains(.keyboard)
    }

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
        configuration = CPSessionConfiguration(delegate: self)
    }

    nonisolated func sessionConfiguration(
        _ sessionConfiguration: CPSessionConfiguration,
        limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface
    ) {
        Task { @MainActor in
            Logger.carPlay.notice("Limited interfaces changed: \(limitedUserInterfaces.rawValue, privacy: .public)")
            self.onChange()
        }
    }
}
#endif
