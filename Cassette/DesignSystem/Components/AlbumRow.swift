// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Flat list cell for an album — cover 60pt, name, artist, year.
/// Used in search results and any flat album list (not grids; see ArtistDetailView).
struct AlbumRow: View {
    let albumId: String
    let name: String
    let artist: String?
    let year: Int?
    let coverArtId: String?

    @Environment(\.appContainer) private var container
    @State private var showLimitAlert = false

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: coverArtId ?? albumId, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let artist {
                    Text(artist)
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let year {
                    Text(String(year))
                        .font(.cassetteCaption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
        .contextMenu { pinContextMenu(itemType: .album, itemId: albumId, displayName: name, subtitle: artist ?? "") }
        .alert("Pin Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(PinError.limitReached.errorDescription ?? "")
        }
    }

    @ViewBuilder
    private func pinContextMenu(itemType: PinnedItemType, itemId: String, displayName: String, subtitle: String) -> some View {
        if container?.pinService.isPinned(itemType: itemType, itemId: itemId) == true {
            Button {
                container?.pinService.unpin(itemType: itemType, itemId: itemId)
            } label: {
                Label("Unpin from Home", systemImage: "pin.slash")
            }
        } else {
            Button {
                guard let serverId = container?.serverState.activeServer?.id,
                      let pin = container?.pinService else { return }
                do {
                    try pin.pin(itemType: itemType, itemId: itemId, displayName: displayName,
                                displaySubtitle: subtitle, coverArtId: coverArtId, serverId: serverId)
                } catch PinError.limitReached {
                    showLimitAlert = true
                } catch {}
            } label: {
                Label("Pin to Home", systemImage: "pin")
            }
        }
    }
}

#Preview {
    List {
        AlbumRow(albumId: "1", name: "Golden Hour", artist: "JVKE", year: 2022, coverArtId: nil)
        AlbumRow(albumId: "2", name: "Short n' Sweet", artist: "Sabrina Carpenter", year: 2024, coverArtId: nil)
        AlbumRow(albumId: "3", name: "Radical Optimism", artist: nil, year: nil, coverArtId: nil)
    }
    .listStyle(.plain)
}
