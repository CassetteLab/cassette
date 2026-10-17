// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import UIKit
import CarPlay
import OSLog

/// Routes incoming scenes to the right delegate.
///
/// SwiftUI has no equivalent of `CPTemplateApplicationSceneDelegate`, so CarPlay needs a UIKit
/// entry point. The window scene keeps no delegate of its own: SwiftUI installs its own and
/// naming one here would take the app's window away from it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            Logger.carPlay.notice("Configuring the CarPlay scene")
            let configuration = UISceneConfiguration(
                name: "CarPlay",
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}
#endif
