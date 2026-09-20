// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import UIKit

/// Restores the interactive pop gesture on screens that hide the system back button.
///
/// `navigationBarBackButtonHidden(true)` also disables `interactivePopGestureRecognizer`,
/// because UIKit's own delegate refuses to begin without a back button to drive. The usual
/// workaround is to clear that delegate outright, which re-enables the gesture but also
/// removes the only thing deciding whether a pop is legal: with no delegate at all,
/// `gestureRecognizerShouldBegin` defaults to true, so the gesture can begin on a
/// single-view-controller stack, or while a push or pop is still in flight, and UIKit is left
/// popping a controller that is already leaving.
///
/// This delegate answers that question rather than removing it: begin only when there is
/// something to pop back to, and never during a transition.
@MainActor
private final class SwipeBackGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    /// Set when the delegate is installed, so `shouldBegin` never has to guess which stack it
    /// belongs to by walking the responder chain.
    weak var navigationController: UINavigationController?
    /// The delegate UIKit installed, put back when this screen goes away.
    weak var originalDelegate: (any UIGestureRecognizerDelegate)?

    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let navigationController else { return false }
            // Nothing to go back to — popping the root is what corrupts the stack.
            guard navigationController.viewControllers.count > 1 else { return false }
            // A push or pop is still running; starting a second one on top of it is the other
            // way the stack ends up inconsistent.
            guard navigationController.transitionCoordinator == nil else { return false }
            return true
        }
    }
}

private struct SwipeBackEnablerRepresentable: UIViewControllerRepresentable {
    func makeCoordinator() -> SwipeBackGestureDelegate { SwipeBackGestureDelegate() }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Installed once and idempotent. `updateUIViewController` runs on every update, and
        // re-assigning on each one is how the delegate being replaced used to get lost.
        guard let navigationController = uiViewController.navigationController,
              let recognizer = navigationController.interactivePopGestureRecognizer,
              recognizer.delegate !== context.coordinator else { return }
        context.coordinator.navigationController = navigationController
        context.coordinator.originalDelegate = recognizer.delegate
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = true
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: SwipeBackGestureDelegate) {
        // Hand the gesture back exactly as it was found, so screens that do show the system back
        // button are not left running on this delegate after this one is gone.
        MainActor.assumeIsolated {
            guard let recognizer = coordinator.navigationController?.interactivePopGestureRecognizer,
                  recognizer.delegate === coordinator else { return }
            recognizer.delegate = coordinator.originalDelegate
        }
    }
}

extension View {
    func enableSwipeBack() -> some View {
        background(SwipeBackEnablerRepresentable())
    }
}
#endif
