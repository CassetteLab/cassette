// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

/// Connects the active server to its AudioMuse-AI instance, which is what powers the weekly mood
/// playlists.
///
/// Per server rather than global: AudioMuse returns the media server's own track ids, so an
/// instance analysing a different library would hand back ids that resolve to nothing here.
struct AudioMuseSettingsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput = ""
    @State private var tokenInput = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var lastRefresh: Date?
    @State private var lastSource: MoodSourceKind?
    @State private var showDisconnectAlert = false
    @State private var isRebuilding = false
    @State private var didLoad = false

    private enum TestResult: Equatable {
        case success(trackCount: Int)
        case failure(String)
    }

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }
    private var isConnected: Bool { activeServer?.audioMuseURL?.isEmpty == false }

    var body: some View {
        Form {
            aboutSection
            if activeServer == nil {
                Section { Text("No server configured.").foregroundStyle(.secondary) }
            } else {
                connectionSection
                statusSection
            }
        }
        .navigationTitle("AudioMuse")
        .navigationBarTitleDisplayModeInline()
        .task {
            guard !didLoad else { return }
            didLoad = true
            urlInput = activeServer?.audioMuseURL ?? ""
            tokenInput = (try? await container?.serverService.activeCredentials())??.audioMuseToken ?? ""
            await loadLastRefresh()
        }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        Section {
            Text("AudioMuse-AI analyses how your music actually sounds, which lets Cassette build a playlist for a mood rather than for a tag.")
                .font(.cassetteCaption)
                .foregroundStyle(.secondary)
            // Said up front, because the moods appear whether or not the user connects anything, and
            // somebody seeing them without AudioMuse deserves to know they are on the weaker path.
            Text("Without it, mood playlists still work, built from your library's genre, BPM and mood tags. The match is rougher.")
                .font(.cassetteCaption)
                .foregroundStyle(.secondary)
            Link("Learn about AudioMuse-AI →", destination: URL(string: "https://github.com/NeptuneHub/AudioMuse-AI")!)
                .font(.cassetteCaption)
        }
    }

    private var connectionSection: some View {
        Section {
            // `verbatim` so the sample address is not extracted as a translatable key — a URL reads
            // the same in every language.
            TextField("", text: $urlInput, prompt: Text(verbatim: "http://nas.local:8000"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            SecureField("API token (optional)", text: $tokenInput)
                .textContentType(.password)
                .autocorrectionDisabled()

            Button {
                Task { await testAndSave() }
            } label: {
                HStack {
                    Text(isConnected ? "Test and Update" : "Connect")
                    if isTesting {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)

            if let testResult {
                switch testResult {
                case .success(let count):
                    Label("Connected — \(count) tracks matched a test search.", systemImage: "checkmark.circle")
                        .font(.cassetteCaption)
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.cassetteCaption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Server")
        } footer: {
            // The token is genuinely optional: an instance started with AUTH_ENABLED=false accepts
            // unauthenticated requests, and saying so saves the user hunting for a token they have not got.
            Text("Leave the token empty if your AudioMuse instance runs without authentication.")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Matching") {
                switch lastSource {
                case .sonic: Text("Sonic analysis")
                case .tags:  Text("Library tags")
                case nil:    Text("Library tags").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Last refresh") {
                if isRebuilding {
                    ProgressView().controlSize(.small)
                } else if let lastRefresh {
                    Text(lastRefresh, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                        .foregroundStyle(.secondary)
                }
            }
            if isConnected {
                Button("Disconnect", role: .destructive) { showDisconnectAlert = true }
            }
        } footer: {
            // Not "every Wednesday": iOS decides when background work runs, so the honest promise is
            // the weekday it targets plus the fact that opening the app catches up.
            Text("Mood playlists refresh once a week, from Wednesday onwards, the next time you open Cassette.")
        }
        .alert("Disconnect AudioMuse?", isPresented: $showDisconnectAlert) {
            Button("Disconnect", role: .destructive) { Task { await disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The mood playlists already on your server are left untouched. They will keep updating from your library tags instead.")
        }
    }

    // MARK: - Actions

    /// Saves only after a successful round-trip, so a typo in the URL cannot silently disable the
    /// feature until the next Wednesday reveals it.
    private func testAndSave() async {
        guard let container, let server = activeServer else { return }
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = AudioMuseClient(urlString: url, token: token.isEmpty ? nil : token) else {
            testResult = .failure(String(localized: "That does not look like a valid address."))
            return
        }

        do {
            // A real search rather than a ping: it proves the URL, the token AND that the sonic
            // analysis has actually been run, which is the part users most often have not done.
            let tracks = try await client.search(query: Mood.chill.query, limit: 5)
            guard !tracks.isEmpty else {
                testResult = .failure(String(localized: "Connected, but the search returned nothing. Has the sonic analysis been run?"))
                return
            }
            try await container.serverService.setAudioMuseConfig(serverId: server.id, urlString: url, token: token)
            testResult = .success(trackCount: tracks.count)
            // Rebuild at once. The moods are already synced for this week, so without this the
            // playlists would keep their tag-built contents until Wednesday and the connection would
            // look like it had done nothing.
            await rebuildPlaylists()
        } catch let error as AudioMuseError {
            testResult = .failure(message(for: error))
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    private func disconnect() async {
        guard let container, let server = activeServer else { return }
        try? await container.serverService.setAudioMuseConfig(serverId: server.id, urlString: nil, token: nil)
        urlInput = ""
        tokenInput = ""
        testResult = nil
        // Rebuild from tags rather than forgetting everything: the playlists stay, they just go back
        // to the weaker source. Clearing local state would strand them and create duplicates later.
        await rebuildPlaylists()
    }

    /// Regenerates all five playlists from whichever source is now configured.
    private func rebuildPlaylists() async {
        guard let container, let server = activeServer else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        _ = await container.moodPlaylistService.rebuildNow(serverId: server.id.uuidString)
        await loadLastRefresh()
    }

    private func loadLastRefresh() async {
        guard let container, let server = activeServer else { return }
        lastRefresh = await container.moodPlaylistService.lastRefresh(serverId: server.id.uuidString)
        lastSource = await container.moodPlaylistService.lastSource(serverId: server.id.uuidString)
    }

    private func message(for error: AudioMuseError) -> String {
        switch error {
        case .searchDisabled(let serverMessage):
            return serverMessage ?? String(localized: "Sonic search is switched off on this AudioMuse instance.")
        case .notAnalysed:
            return String(localized: "AudioMuse has not analysed your library yet. Run an analysis, then try again.")
        case .unauthorized:
            return String(localized: "The API token was rejected.")
        case .internalIdsOnly:
            return String(localized: "AudioMuse returned its own internal track IDs, which your music server cannot match. Its library catalogue likely needs a re-scan.")
        case .badURL:
            return String(localized: "That does not look like a valid address.")
        case .transport(let detail), .decoding(let detail):
            return detail
        }
    }
}
