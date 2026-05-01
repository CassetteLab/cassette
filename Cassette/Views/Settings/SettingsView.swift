// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

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
            serverSection()
            aboutSection()
        }
        .formStyle(.grouped)
        .refreshable {
            await downloadsVM.loadData()
        }
    }

    // MARK: - Sections

    private func serverSection() -> some View {
        Section("Server") {
            if let server = container?.serverState.activeServer {
                LabeledContent {
                    Text(server.displayName)
                } label: {
                    Label {
                        Text("Connected to")
                    } icon: {
                        SettingsIcon(systemImage: "server.rack", color: Color.cassetteAccent)
                    }
                }
                LabeledContent {
                    Text(server.baseURL)
                } label: {
                    Label {
                        Text("Address")
                    } icon: {
                        SettingsIcon(systemImage: "link", color: .blue)
                    }
                }
                LabeledContent {
                    Text(server.username)
                } label: {
                    Label {
                        Text("Username")
                    } icon: {
                        SettingsIcon(systemImage: "person.fill", color: .purple)
                    }
                }
            } else {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
            // TODO(v1.x): multi-server management (add / remove / switch servers)
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
            Link(destination: URL(string: "https://github.com/MathieuDubart/cassette")!) {
                Label {
                    Text("GitHub Repository")
                } icon: {
                    SettingsIcon(systemImage: "chevron.left.forwardslash.chevron.right", color: .gray)
                }
            }
            // TODO(v1.0): display Bundle version, add GPL license note, SwiftSonic MIT attribution
        }
    }
}

// MARK: - Shared icon component

private struct SettingsIcon: View {
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

// MARK: - Downloads section

private struct DownloadsSectionView: View {
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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.subheadline)
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
