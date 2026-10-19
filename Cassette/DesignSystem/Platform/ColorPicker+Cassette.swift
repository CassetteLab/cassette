// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Presents the system colour picker for `selection`, leaving the screen behind it visible as-is.
    ///
    /// The point of the picker here is the eyedropper: matching a colour taken from the cover on the
    /// screen. SwiftUI's `ColorPicker` is a control that has to live in a view, so it used to sit in
    /// a sheet — and the sheet's dimming layer stayed over the cover while the eyedropper sampled it,
    /// so every sampled colour came out darker than the artwork.
    ///
    /// - iOS: `UIColorPickerViewController` presented directly, at a medium detent that leaves the
    ///   screen undimmed (`largestUndimmedDetentIdentifier`). It can still be pulled to large.
    /// - macOS: a small sheet hosting `ColorPicker`, whose `NSColorPanel` is its own window and
    ///   samples the real screen — there is no dimming to avoid.
    @ViewBuilder
    func cassetteColorPicker(
        isPresented: Binding<Bool>,
        selection: Binding<Color>,
        title: String
    ) -> some View {
        #if os(iOS)
        background(
            UndimmedColorPickerPresenter(isPresented: isPresented, selection: selection, title: title)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        #else
        sheet(isPresented: isPresented) {
            MacColorPickerSheet(selection: selection, title: title)
        }
        #endif
    }
}

#if os(iOS)
/// Zero-size anchor that presents a `UIColorPickerViewController` while `isPresented` is true.
private struct UndimmedColorPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selection: Color
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if isPresented {
            guard coordinator.picker == nil else { return }
            // Not in a window yet, or already presenting something: nothing to present from.
            // Hand the flag back rather than leave it stuck on true with no picker showing.
            guard host.view.window != nil, host.presentedViewController == nil else {
                Task { @MainActor in isPresented = false }
                return
            }
            let picker = UIColorPickerViewController()
            picker.title = title
            picker.supportsAlpha = false
            picker.selectedColor = UIColor(selection)
            picker.delegate = coordinator
            if let sheet = picker.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.largestUndimmedDetentIdentifier = .medium
                sheet.prefersGrabberVisible = true
            }
            coordinator.picker = picker
            host.present(picker, animated: true)
        } else if let picker = coordinator.picker {
            coordinator.picker = nil
            picker.dismiss(animated: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: UndimmedColorPickerPresenter
        var picker: UIColorPickerViewController?

        init(parent: UndimmedColorPickerPresenter) {
            self.parent = parent
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            parent.selection = Color(uiColor: color)
        }

        /// Called however the picker goes away — its close button or a swipe down.
        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            picker = nil
            if parent.isPresented { parent.isPresented = false }
        }
    }
}
#else
private struct MacColorPickerSheet: View {
    @Binding var selection: Color
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.l) {
            ColorPicker(title, selection: $selection, supportsOpacity: false)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(CassetteSpacing.l)
        .frame(minWidth: 280)
    }
}
#endif
