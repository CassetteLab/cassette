// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ThemePlaylistsView: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [ThemePlaylistType: ThemePlaylistDTO] = [:]
    @State private var isSyncing = false
    @State private var syncError: Error?

    var body: some View {
        List {
            ForEach(ThemePlaylistType.allCases, id: \.self) { type in
                Group {
                    if let dto = playlists[type] {
                        NavigationLink(destination: ThemePlaylistDetailView(dto: dto)) {
                            ThemePlaylistRow(type: type, dto: dto)
                        }
                    } else {
                        ThemePlaylistRow(type: type, dto: nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .cassetteContentWidth()
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button {
                        Task { await sync() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(container?.serverState.isOnline != true)
                }
            }
        }
        .task {
            await loadCached()
            guard container?.serverState.isOnline == true else { return }
            await sync()
        }
        .refreshable {
            await loadCached()
            await sync()
        }
    }

    private func loadCached() async {
        guard let service = container?.themePlaylistService,
              let serverId = container?.serverState.activeServer?.id.uuidString else { return }
        let dtos = await service.loadCached(serverId: serverId)
        playlists = Dictionary(uniqueKeysWithValues: dtos.map { ($0.type, $0) })
    }

    private func sync() async {
        guard let service = container?.themePlaylistService,
              let serverId = container?.serverState.activeServer?.id.uuidString else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await service.sync(serverId: serverId)
            await loadCached()
            syncError = nil
        } catch {
            syncError = error
        }
    }
}

// MARK: - Row

private struct ThemePlaylistRow: View {
    let type: ThemePlaylistType
    let dto: ThemePlaylistDTO?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous)
                    .fill(CassetteColors.accentBackground)
                    .frame(width: 52, height: 52)
                Image(systemName: type.systemImage)
                    .font(.title2)
                    .foregroundStyle(CassetteColors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let dto {
                    Text("\(dto.trackCount) tracks · \(Self.relativeFormatter.localizedString(for: dto.lastSyncedAt, relativeTo: Date()))")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Not yet generated")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .opacity(dto == nil ? 0.5 : 1)
    }
}
