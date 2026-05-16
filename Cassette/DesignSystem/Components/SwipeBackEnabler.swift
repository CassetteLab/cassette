// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import UIKit

private struct SwipeBackEnablerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            uiViewController.navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

extension View {
    func enableSwipeBack() -> some View {
        background(SwipeBackEnablerRepresentable())
    }
}
#endif
