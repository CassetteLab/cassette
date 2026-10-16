// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(macOS)
import AppKit
#endif

/// The consistent native share action used by player menus and song context menus.
/// It shares local metadata only and never performs a network request.
struct SongShareButton: View {
    let song: DisplayableSong
    var showsIcon: Bool = true

    var body: some View {
        #if os(macOS)
        Button {
            let text = SongShareContent(song: song).text
            // Let the originating menu finish closing before the sharing-service picker appears.
            Task { @MainActor in
                MacOSSongSharePresenter.present(text: text)
            }
        } label: {
            if showsIcon {
                Label("Share", systemImage: "square.and.arrow.up")
            } else {
                Text("Share")
            }
        }
        #else
        ShareLink(item: SongShareContent(song: song).text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        #endif
    }
}

#if os(macOS)
@MainActor
private enum MacOSSongSharePresenter {
    /// Holds the picker only while it is on screen: `show(relativeTo:…)` does not retain it, and
    /// the delegate callback is what tells us it is gone.
    private static let keeper = PickerKeeper()

    static func present(text: String) {
        guard let contentView = (NSApp.mainWindow ?? NSApp.keyWindow)?.contentView else { return }
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.maxY - 44,
            width: 1,
            height: 1
        )
        let picker = NSSharingServicePicker(items: [text])
        keeper.hold(picker)
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }

    @MainActor
    private final class PickerKeeper: NSObject, NSSharingServicePickerDelegate {
        private var picker: NSSharingServicePicker?

        func hold(_ picker: NSSharingServicePicker) {
            picker.delegate = self
            self.picker = picker
        }

        /// Called with a service when the user picks one, and with `nil` when they dismiss.
        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            self.picker = nil
        }
    }
}
#endif

/// Plain-value share content, kept separate from presentation so formatting is deterministic and testable.
nonisolated struct SongShareContent: Sendable {
    let text: String

    init(song: DisplayableSong) {
        let subtitle = [song.artist, song.albumName]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { return nil }
                return trimmed
            }
            .joined(separator: " · ")

        text = subtitle.isEmpty
            ? "♫ \(song.title)"
            : "♫ \(song.title)\n\(subtitle)"
    }
}
