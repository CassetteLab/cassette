// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var cacheVM: CacheSettingsViewModel?
    @State private var downloadsVM: DownloadsViewModel?

    var body: some View {
        Group {
            if let cacheVM, let downloadsVM, let settings = container?.cacheSettings {
                form(cacheVM: cacheVM, downloadsVM: downloadsVM, settings: settings)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Settings")
        .task {
            guard let container else { return }
            if cacheVM == nil {
                cacheVM = CacheSettingsViewModel(cacheService: container.cacheService)
            }
            if downloadsVM == nil {
                downloadsVM = DownloadsViewModel(
                    modelContainer: container.modelContainer,
                    downloadService: container.downloadService,
                    serverState: container.serverState
                )
            }
            await cacheVM?.loadUsedBytes()
            await downloadsVM?.loadData()
        }
    }

    private func form(cacheVM: CacheSettingsViewModel, downloadsVM: DownloadsViewModel, settings: CacheSettings) -> some View {
        Form {
            CacheSectionView(vm: cacheVM, settings: settings)
            DownloadsSectionView(vm: downloadsVM)
            serverSection()
            aboutSection()
        }
        .refreshable {
            await cacheVM.loadUsedBytes()
            await downloadsVM.loadData()
        }
    }

    // MARK: - Sections

    private func serverSection() -> some View {
        Section("Server") {
            if let server = container?.serverState.activeServer {
                LabeledContent("Connected to", value: server.displayName)
                LabeledContent("Address", value: server.baseURL)
                LabeledContent("Username", value: server.username)
            } else {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
            // TODO(v1.x): multi-server management (add / remove / switch servers)
        }
    }

    private func aboutSection() -> some View {
        Section("About") {
            LabeledContent("App", value: "Cassette")
            // TODO(v1.0): display Bundle version, add GPL license note, SwiftSonic MIT attribution
        }
    }
}

// MARK: - Cache section

/// Isolated sub-view so @Bindable on the @Observable CacheSettings works without friction.
private struct CacheSectionView: View {
    let vm: CacheSettingsViewModel
    @Bindable var settings: CacheSettings

    var body: some View {
        Section {
            LabeledContent("Used") {
                Text(vm.usedBytesFormatted)
                    .foregroundStyle(.secondary)
            }

            Picker("Quota", selection: $settings.quotaBytes) {
                Text("250 MB").tag(262_144_000.0)
                Text("500 MB").tag(524_288_000.0)
                Text("1 GB").tag(1_073_741_824.0)
                Text("2 GB").tag(2_147_483_648.0)
                Text("5 GB").tag(5_368_709_120.0)
                Text("No limit").tag(Double.greatestFiniteMagnitude)
            }

            Picker("Keep tracks for", selection: $settings.ttlSeconds) {
                Text("1 hour").tag(3_600.0)
                Text("1 day").tag(86_400.0)
                Text("3 days").tag(259_200.0)
                Text("7 days").tag(604_800.0)
                Text("30 days").tag(2_592_000.0)
                Text("Until cache is full").tag(Double.greatestFiniteMagnitude)
            }

            Button(role: .destructive) {
                Task { await vm.clearCache() }
            } label: {
                if vm.isClearing {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Clearing…")
                    }
                } else {
                    Text("Clear cache now")
                }
            }
            .disabled(vm.isClearing)

        } header: {
            Text("Cache")
        } footer: {
            // Decision B2: cache writes come from manual downloads (Étape 6); streaming
            // will populate the cache automatically in a future update via AVAssetResourceLoaderDelegate.
            Text("The cache is populated by manual downloads. Automatic caching while streaming is coming in a future update.")
        }
    }
}

// MARK: - Downloads section

private struct DownloadsSectionView: View {
    let vm: DownloadsViewModel

    var body: some View {
        Section {
            LabeledContent("Used") {
                Text(vm.usedBytesFormatted)
                    .foregroundStyle(.secondary)
            }

            if !vm.downloadedAlbums.isEmpty {
                DisclosureGroup("Albums (\(vm.downloadedAlbums.count))") {
                    ForEach(vm.downloadedAlbums) { album in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.subheadline)
                                Text("\(album.tracksCount)/\(album.totalTracksCount) tracks\(album.isComplete ? "" : " (incomplete)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await vm.removeAlbum(album) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if !vm.downloadedPlaylists.isEmpty {
                DisclosureGroup("Playlists (\(vm.downloadedPlaylists.count))") {
                    ForEach(vm.downloadedPlaylists) { playlist in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.subheadline)
                                Text("\(playlist.tracksCount)/\(playlist.totalTracksCount) tracks\(playlist.isComplete ? "" : " (incomplete)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await vm.removePlaylist(playlist) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if vm.downloadedAlbums.isEmpty && vm.downloadedPlaylists.isEmpty {
                Text("No downloaded content.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            Button(role: .destructive) {
                Task { await vm.clearAll() }
            } label: {
                if vm.isClearingAll {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Clearing…")
                    }
                } else {
                    Text("Clear all downloads")
                }
            }
            .disabled(vm.isClearingAll || (vm.downloadedAlbums.isEmpty && vm.downloadedPlaylists.isEmpty))

        } header: {
            Text("Downloads")
        } footer: {
            Text("Downloaded tracks are stored permanently and available offline.")
        }
    }
}
