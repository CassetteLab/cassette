// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftUI

struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var downloadsVM: DownloadsViewModel?

    var body: some View {
        Group {
            if let downloadsVM {
                form(downloadsVM: downloadsVM)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Settings")
        .task {
            guard let container else { return }
            if downloadsVM == nil {
                downloadsVM = DownloadsViewModel(
                    modelContainer: container.modelContainer,
                    downloadService: container.downloadService,
                    serverState: container.serverState
                )
            }
            await downloadsVM?.loadData()
        }
    }

    private func form(downloadsVM: DownloadsViewModel) -> some View {
        Form {
            DownloadsSectionView(vm: downloadsVM)
            CacheSectionView()
            playbackSection()
            serverSection()
            integrationsSection()
            aboutSection()
            supportSection()
        }
        .formStyle(.grouped)
        .refreshable {
            await downloadsVM.loadData()
        }
    }

    // MARK: - Sections

    private func playbackSection() -> some View {
        Section("Playback") {
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "cassette.replayGainEnabled") },
                set: { newVal in
                    UserDefaults.standard.set(newVal, forKey: "cassette.replayGainEnabled")
                    Task {
                        await container?.replayGainService.setEnabled(
                            newVal,
                            currentTrack: container?.playerState.currentTrack
                        )
                    }
                }
            )) {
                Label {
                    Text("ReplayGain")
                } icon: {
                    SettingsIcon(systemImage: "speaker.wave.3", color: .purple)
                }
            }
        }
    }

    private func serverSection() -> some View {
        Section("Server") {
            if let server = container?.serverState.activeServer,
               let serverService = container?.serverService {
                NavigationLink {
                    EditServerDestinationView(server: server, serverService: serverService)
                } label: {
                    Label {
                        Text("Server Configuration")
                    } icon: {
                        SettingsIcon(systemImage: "server.rack", color: Color.cassetteAccent)
                    }
                }
            } else {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
            // TODO(v1.x): multi-server management (add / remove / switch servers)
        }
    }

    private func integrationsSection() -> some View {
        Section("Integrations") {
            NavigationLink {
                ListenBrainzSettingsView()
            } label: {
                Label {
                    Text("ListenBrainz")
                } icon: {
                    SettingsIcon(systemImage: "link.circle", color: .indigo)
                }
            }
            NavigationLink {
                ExternalProvidersSettingsView()
            } label: {
                Label {
                    Text("Open Releases In")
                } icon: {
                    SettingsIcon(systemImage: "arrow.up.right.square", color: .orange)
                }
            }
        }
    }

    private func supportSection() -> some View {
        Section {
            VStack(spacing: 4) {
                Text("Cassette is free, forever.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Button {
                    Logger.settings.debug("Ko-fi support button tapped")
                    ExternalLinkOpener.open(CassetteURLs.kofi)
                } label: {
                    Image("kofiButton")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func aboutSection() -> some View {
        Section("About") {
            LabeledContent {
                Text("Cassette")
            } label: {
                Label {
                    Text("App")
                } icon: {
                    SettingsIcon(systemImage: "info.circle.fill", color: .blue)
                }
            }
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }
            LabeledContent("License") {
                Text("Mozilla Public License 2.0")
            }
            LabeledContent("SwiftSonic") {
                Text("MIT License — MathieuDubart")
            }
            LabeledContent("AudioStreaming") {
                Button("MIT License — dimitris-c") {
                    ExternalLinkOpener.open(CassetteURLs.audioStreaming)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Button("View on GitHub") {
                ExternalLinkOpener.open(CassetteURLs.cassette)
            }
            Link("Send Feedback / Report a Bug", destination: URL(string: "mailto:support@getcassette.app?subject=Feedback%20%2F%20Bug%20Report")!)
        }
    }
}

// MARK: - Shared icon component

struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Cache section

struct CacheSectionView: View {
    @Environment(\.appContainer) private var container
    @State private var usedBytes: Int64 = 0
    @State private var trackCount: Int = 0
    @State private var isClearing: Bool = false

    private var cacheSettings: CacheSettings? { container?.cacheSettings }

    var body: some View {
        let maxTracks = cacheSettings?.maxTracks ?? 10

        return Section {
            LabeledContent {
                Text(usageDescription(maxTracks: maxTracks))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } label: {
                Label {
                    Text("Used")
                } icon: {
                    SettingsIcon(systemImage: "externaldrive.fill", color: .green)
                }
            }

            if let cacheSettings {
                Stepper(
                    value: Binding(
                        get: { cacheSettings.maxTracks },
                        set: { cacheSettings.maxTracks = max(1, min(10, $0)) }
                    ),
                    in: 1...10
                ) {
                    HStack {
                        Label {
                            Text("Max tracks")
                        } icon: {
                            SettingsIcon(systemImage: "tray.full.fill", color: Color.cassetteAccent)
                        }
                        Spacer()
                        Text("\(maxTracks)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .font(.body.weight(.medium))
                    }
                }
            }

            if let cacheSettings {
                Picker(selection: Binding<CacheFormat>(
                    get: { cacheSettings.cacheFormat },
                    set: { newValue in cacheSettings.cacheFormat = newValue }
                )) {
                    ForEach(CacheFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                } label: {
                    Label {
                        Text("Format")
                    } icon: {
                        SettingsIcon(systemImage: "waveform", color: .purple)
                    }
                }
                .pickerStyle(.menu)
            }

            if let cacheSettings {
                Toggle(isOn: Binding(
                    get: { cacheSettings.cacheOverCellular },
                    set: { cacheSettings.cacheOverCellular = $0 }
                )) {
                    Label {
                        Text("Use cellular data")
                    } icon: {
                        SettingsIcon(systemImage: "antenna.radiowaves.left.and.right", color: .blue)
                    }
                }
            }

            Button(role: .destructive) {
                Task { await clearCache() }
            } label: {
                if isClearing {
                    HStack(spacing: CassetteSpacing.s) {
                        ProgressView().scaleEffect(0.8)
                        Text("Clearing…")
                    }
                } else {
                    Label("Clear cache", systemImage: "trash.fill")
                }
            }
            .disabled(isClearing || (usedBytes == 0 && trackCount == 0))

        } header: {
            Text("Cache")
        } footer: {
            Text("Cached tracks let recently-played music load instantly without re-fetching from the server. Cache is automatic, sliding window — the oldest track is replaced when the limit is reached.")
        }
        .task {
            await refreshUsage()
        }
        .onChange(of: cacheSettings?.maxTracks) { _, newValue in
            guard let newValue else { return }
            Task {
                await container?.cacheService.setMaxTracks(newValue)
                await refreshUsage()
            }
        }
    }

    // MARK: - Helpers

    private func usageDescription(maxTracks: Int) -> String {
        let bytesString = ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
        return "\(bytesString) · \(trackCount)/\(maxTracks) tracks"
    }

    private func refreshUsage() async {
        guard let container else { return }
        let bytes = await container.cacheService.usedBytes
        let count = await container.cacheService.trackCount
        usedBytes = bytes
        trackCount = count
    }

    private func clearCache() async {
        guard let container else { return }
        isClearing = true
        defer { isClearing = false }
        await container.cacheService.clearAll()
        container.dominantColorExtractor.clearCache()
        await refreshUsage()
    }
}

// MARK: - Downloads section

struct DownloadsSectionView: View {
    let vm: DownloadsViewModel

    var body: some View {
        Section {
            LabeledContent {
                Text(vm.usedBytesFormatted)
                    .foregroundStyle(.secondary)
            } label: {
                Label {
                    Text("Used")
                } icon: {
                    SettingsIcon(systemImage: "arrow.down.circle.fill", color: .green)
                }
            }

            if !vm.displayAlbums.isEmpty {
                DisclosureGroup {
                    ForEach(vm.displayAlbums) { album in
                        HStack(spacing: CassetteSpacing.m) {
                            CoverArtCard(id: album.coverArtId ?? album.albumId, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let total = album.totalTracksCount {
                                    Text("\(album.downloadedTracksCount)/\(total) tracks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(album.downloadedTracksCount) track\(album.downloadedTracksCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                } label: {
                    Label {
                        Text("Albums (\(vm.displayAlbums.count))")
                    } icon: {
                        SettingsIcon(systemImage: "music.note.list", color: Color.cassetteAccent)
                    }
                }
            }

            if !vm.downloadedPlaylists.isEmpty {
                DisclosureGroup {
                    ForEach(vm.downloadedPlaylists) { playlist in
                        HStack(spacing: CassetteSpacing.m) {
                            CoverArtCard(id: playlist.playlistId, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(playlist.tracksCount)/\(playlist.totalTracksCount) tracks")
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
                } label: {
                    Label {
                        Text("Playlists (\(vm.downloadedPlaylists.count))")
                    } icon: {
                        SettingsIcon(systemImage: "list.bullet", color: .indigo)
                    }
                }
            }

            if vm.displayAlbums.isEmpty && vm.downloadedPlaylists.isEmpty {
                Text("No downloaded content.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            Button(role: .destructive) {
                Task { await vm.clearAll() }
            } label: {
                if vm.isClearingAll {
                    HStack(spacing: CassetteSpacing.s) {
                        ProgressView().scaleEffect(0.8)
                        Text("Clearing…")
                    }
                } else {
                    Label("Clear all downloads", systemImage: "trash.fill")
                }
            }
            .disabled(vm.isClearingAll || (vm.displayAlbums.isEmpty && vm.downloadedPlaylists.isEmpty))

        } header: {
            Text("Downloads")
        } footer: {
            Text("Downloaded tracks are stored permanently and available offline.")
        }
    }
}
