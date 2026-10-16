// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The consistent native share actions used by player menus and song context menus.
///
/// There are two, deliberately. Sharing the title and artist as text works everywhere, offline
/// included. A public link only means something when the server is reachable by whoever receives
/// it — many libraries live on a LAN or behind a VPN — and it exposes the track to anyone holding
/// the URL. That is a choice someone makes on purpose, not a side effect of tapping "Share".
struct SongShareButton: View {
    let song: DisplayableSong
    var showsIcon: Bool = true

    @Environment(\.appContainer) private var container

    var body: some View {
        Group {
            shareDetailsButton
            if canCreatePublicLink {
                Button {
                    createPublicLink()
                } label: {
                    if showsIcon {
                        Label("Copy Public Link", systemImage: "link")
                    } else {
                        Text("Copy Public Link")
                    }
                }
            }
        }
    }

    /// Hidden rather than disabled when it cannot work: with no server or no network there is
    /// nothing to create a link against, and a greyed-out row in a context menu explains nothing.
    private var canCreatePublicLink: Bool {
        guard let container else { return false }
        return container.serverState.activeServer != nil && container.serverState.isOnline
    }

    private func createPublicLink() {
        guard let container else { return }
        let songId = song.id
        let description = song.title
        container.toastService.show(String(localized: "Creating public link\u{2026}"), style: .info, duration: 1.5)
        // Not a `.task`: the menu holding this button is torn down the moment it is tapped, and
        // the request has to outlive it.
        Task { @MainActor in
            do {
                let url = try await container.shareService.createPublicLink(
                    songIds: [songId],
                    description: description
                )
                SongSharePasteboard.copy(url)
                container.toastService.showSuccess(String(localized: "Public link copied"))
            } catch {
                container.toastService.showError(ShareLinkError(error).userMessage)
            }
        }
    }

    @ViewBuilder
    private var shareDetailsButton: some View {
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

/// Writes the link where every other app can reach it.
///
/// A share sheet would be nicer, but these buttons live inside menus that are already dismissing
/// by the time the request comes back, and presenting from a view on its way out is not reliable
/// on either platform. Copying always works, and the toast says so.
@MainActor
private enum SongSharePasteboard {
    static func copy(_ url: URL) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #else
        UIPasteboard.general.url = url
        #endif
    }
}

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
