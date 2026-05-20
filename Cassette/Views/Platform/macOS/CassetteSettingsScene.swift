// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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

private enum SettingsTab: Int {
    case general, server, cache, integrations, about
}

struct MacOSSettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            ServerSettingsTab()
                .tabItem { Label("Server", systemImage: "server.rack") }
                .tag(SettingsTab.server)

            CacheSettingsTab()
                .tabItem { Label("Cache", systemImage: "externaldrive") }
                .tag(SettingsTab.cache)

            IntegrationsSettingsTab()
                .tabItem { Label("Integrations", systemImage: "link.circle") }
                .tag(SettingsTab.integrations)

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
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
    @State private var showEditServer = false

    var body: some View {
        Form {
            Section("Server") {
                if let server = container?.serverState.activeServer,
                   let serverService = container?.serverService {
                    Button {
                        showEditServer = true
                    } label: {
                        LabeledContent("Server Configuration") {
                            HStack(spacing: CassetteSpacing.xs) {
                                Text(server.displayName)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showEditServer) {
                        EditServerDestinationView(server: server, serverService: serverService)
                            .frame(minWidth: 480, minHeight: 400)
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
    @State private var showListenBrainz = false
    @State private var showProviders = false

    var body: some View {
        Form {
            Section {
                Button { showListenBrainz = true } label: {
                    HStack {
                        Label("ListenBrainz", systemImage: "link.circle")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { showProviders = true } label: {
                    HStack {
                        Label("Open Releases In", systemImage: "arrow.up.right.square")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
        .sheet(isPresented: $showListenBrainz) {
            ListenBrainzSettingsView()
                .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $showProviders) {
            ExternalProvidersSettingsView()
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}

// MARK: - About tab

private struct AboutSettingsTab: View {
    @Environment(\.openURL) private var openURL
    private let kofiURL = URL(string: "https://ko-fi.com/mathieudbrt")

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
                    Text("MPL-2.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Copyright") {
                    Text("© 2026 Mathieu Dubart")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                VStack(spacing: CassetteSpacing.xs) {
                    Text("Cassette is free, forever.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Button {
                        guard let url = kofiURL else { return }
                        openURL(url)
                    } label: {
                        Image("kofiButton")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, CassetteSpacing.m)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
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
