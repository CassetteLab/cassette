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
            // Wait for the originating menu to close before showing the sharing-service picker.
            DispatchQueue.main.async {
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
    private static var activePicker: NSSharingServicePicker?

    static func present(text: String) {
        guard let contentView = (NSApp.mainWindow ?? NSApp.keyWindow)?.contentView else { return }
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.maxY - 44,
            width: 1,
            height: 1
        )
        let picker = NSSharingServicePicker(items: [text])
        activePicker = picker
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
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
