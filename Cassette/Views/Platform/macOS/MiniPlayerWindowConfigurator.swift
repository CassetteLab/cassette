// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import AppKit
import ObjectiveC

/// The mini-player runs as a non-activating floating panel: clicking its transport controls reaches them
/// without activating the app — so the main window is no longer yanked to the front. `canBecomeMain` is
/// false so it never becomes the app's main window; `canBecomeKey` stays true so controls receive events.
private final class NonactivatingMiniPlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct MiniPlayerWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            // Re-home SwiftUI's plain window onto a non-activating NSPanel. NSPanel is an NSWindow subclass,
            // so SwiftUI's open/dismiss/positioning keep working; the `.nonactivatingPanel` style is what
            // stops a click from activating the app and raising the main window.
            if !(window is NonactivatingMiniPlayerPanel) {
                object_setClass(window, NonactivatingMiniPlayerPanel.self)
            }
            window.styleMask.insert(.nonactivatingPanel)
            if let panel = window as? NSPanel {
                panel.isFloatingPanel = true
                panel.becomesKeyOnlyIfNeeded = true
                panel.hidesOnDeactivate = false
            }

            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
