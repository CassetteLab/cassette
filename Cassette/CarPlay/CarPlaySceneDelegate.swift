// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import OSLog

/// The CarPlay scene.
///
/// CarPlay can start the process with no window at all, so the container is obtained through
/// `AppContainer.launched()` — the same shared launch the iPhone window awaits — and never from
/// `CassetteApp`'s `@State`, which does not exist when no window ever connected.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Logger.carPlay.notice("CarPlay connected")

        Task { @MainActor in
            let container = await AppContainer.launched()
            Logger.carPlay.notice("Shared container ready: \(container != nil, privacy: .public)")

            let item = CPListItem(
                text: "Cassette",
                detailText: container == nil ? "Launch failed" : "Connected"
            )
            let section = CPListSection(items: [item])
            let template = CPListTemplate(title: "Cassette", sections: [section])
            interfaceController.setRootTemplate(template, animated: false, completion: nil)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        // Dropped so the controller — and the templates holding it — are released when the car
        // goes away. A retained controller here survives every connect/disconnect cycle.
        self.interfaceController = nil
        Logger.carPlay.notice("CarPlay disconnected")
    }
}
#endif
