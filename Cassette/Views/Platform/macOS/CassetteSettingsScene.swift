// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftData

struct CassetteSettingsScene: Scene {
    let container: AppContainer?

    var body: some Scene {
        Settings {
            Group {
                if let container {
                    MacOSSettingsView()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                } else {
                    ProgressView()
                        .frame(width: 480, height: 300)
                }
            }
        }
    }
}

// MARK: - Tab container

struct MacOSSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            ServerSettingsTab()
                .tabItem { Label("Server", systemImage: "server.rack") }

            CacheSettingsTab()
                .tabItem { Label("Cache", systemImage: "externaldrive") }

            IntegrationsSettingsTab()
                .tabItem { Label("Integrations", systemImage: "link.circle") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Theme") {
                    Text("Follow System")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Cassette uses your system appearance setting. Per-app theme override is planned for a future release.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }
}

// MARK: - Server tab

private struct ServerSettingsTab: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        Form {
            Section("Server") {
                if let server = container?.serverState.activeServer {
                    LabeledContent("Connected to") {
                        Text(server.displayName)
                    }
                    LabeledContent("Address") {
                        Text(server.baseURL)
                    }
                    LabeledContent("Username") {
                        Text(server.username)
                    }
                    if let version = server.serverVersion {
                        LabeledContent("Server version") {
                            Text(version)
                        }
                    }
                } else {
                    Text("No server configured.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }
}

// MARK: - Cache tab

private struct CacheSettingsTab: View {
    @Environment(\.appContainer) private var container
    @State private var downloadsVM: DownloadsViewModel?

    var body: some View {
        Form {
            if let downloadsVM {
                DownloadsSectionView(vm: downloadsVM)
            }
            CacheSectionView()
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
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
}

// MARK: - Integrations tab

private struct IntegrationsSettingsTab: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ListenBrainzSettingsView()
                    } label: {
                        Label("ListenBrainz", systemImage: "link.circle")
                    }
                    NavigationLink {
                        ExternalProvidersSettingsView()
                    } label: {
                        Label("Open Releases In", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Integrations")
        }
        .frame(maxWidth: 480)
    }
}

// MARK: - About tab

private struct AboutSettingsTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("Cassette") {
                LabeledContent("Version") {
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                LabeledContent("License") {
                    Text("GPL-3.0-or-later")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Copyright") {
                    Text("© 2026 Mathieu Dubart")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Links") {
                Link(destination: URL(string: "https://github.com/MathieuDubart/cassette")!) {
                    Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            Section("Third-party") {
                LabeledContent("SwiftSonic") {
                    Text("MIT License")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }
}
#endif
