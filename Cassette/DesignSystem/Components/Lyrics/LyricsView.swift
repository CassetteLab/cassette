// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// Full-player lyrics panel. Displays all five ViewModel states with tiered blur on lines.
struct LyricsView: View {
    @Bindable var viewModel: LyricsViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let structured):
                loadedContent(structured)

            case .empty:
                emptyState

            case .unsupported:
                unsupportedState

            case .error(let message):
                errorState(message)
            }
        }
        .onAppear { viewModel.startTracking() }
        .onDisappear { viewModel.stopTracking() }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ structured: StructuredLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                        LyricsLineView(
                            value: line.value,
                            index: index,
                            currentIndex: viewModel.currentLineIndex,
                            isSynced: structured.synced,
                            isTappable: structured.synced && line.start != nil,
                            onTap: { viewModel.userTapped(lineIndex: index) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 200)
            }
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard viewModel.autoScrollEnabled,
                      !viewModel.isUserScrolling,
                      let newIndex else { return }
                withAnimation(.smooth(duration: 0.4)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting {
                    viewModel.userStartedScrolling()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 16) {
            if viewModel.availableLanguages.count > 1 {
                Menu {
                    ForEach(viewModel.availableLanguages, id: \.self) { lang in
                        Button(displayName(for: lang)) {
                            viewModel.selectLanguage(lang)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(displayName(for: viewModel.selectedLanguage ?? "und"))
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer()

            Button {
                viewModel.autoScrollEnabled.toggle()
            } label: {
                Image(systemName: viewModel.autoScrollEnabled
                    ? "arrow.up.arrow.down.circle.fill"
                    : "arrow.up.arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No lyrics available")
                .font(.cassetteDetailTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Lyrics not supported")
                .font(.cassetteDetailTitle)
                .foregroundStyle(.secondary)
            Text("Update your Navidrome server to enable the songLyrics extension")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Failed to load lyrics")
                .font(.cassetteDetailTitle)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func displayName(for lang: String) -> String {
        guard lang != "und", lang != "xxx" else { return "—" }
        return Locale.current.localizedString(forLanguageCode: lang)?.capitalized ?? lang.uppercased()
    }
}
