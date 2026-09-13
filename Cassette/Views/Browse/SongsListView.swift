// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

/// Library-wide "All Songs" list. Pages the whole library (search3's empty-query wildcard) with a live
/// progress count, sorts off-main, and shows a Play/Shuffle-all header, a persisted sort control, and an
/// A–Z jump bar when sorted by title.
struct SongsListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: SongsListViewModel?
    /// Persisted sort — Title by default, plus Artist / Recently Added / Release Date.
    @AppStorage("cassette.songSort") private var songSort: SongSort = .title
    @State private var showDownloadWarning = false
    /// Count quoted by the warning — captured at tap time so the dialog can't show a stale number.
    @State private var downloadWarningCount = 0

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        #if os(iOS)
        .cassetteContentWidth()
        #endif
        .navigationTitle("Songs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SongSortMenu(sort: $songSort)
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard let container else { return }
            if viewModel == nil {
                viewModel = SongsListViewModel(
                    libraryService: container.libraryService,
                    downloadService: container.downloadService,
                    toastService: container.toastService,
                    serverState: container.serverState
                )
            }
            guard container.serverState.isOnline else { return }
            await viewModel?.load(sort: songSort)
        }
        .onChange(of: songSort) { _, newSort in
            Task { await viewModel?.changeSort(newSort) }
        }
    }

    @ViewBuilder
    private func content(_ vm: SongsListViewModel) -> some View {
        if vm.isLoading && vm.displaySongs.isEmpty {
            loadingProgress(vm)
        } else if container?.serverState.isOnline == false && vm.displaySongs.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "Connect to your server to browse all songs."
            )
        } else if let error = vm.error, vm.displaySongs.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Songs",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load(sort: songSort) } }
            )
        } else if vm.displaySongs.isEmpty {
            EmptyStateView(
                systemImage: "music.note",
                title: "No Songs",
                subtitle: "Your library appears to be empty."
            )
        } else {
            songList(vm)
        }
    }

    /// Live count while the library pages in — so a large library shows progress, not a frozen spinner.
    private func loadingProgress(_ vm: SongsListViewModel) -> some View {
        VStack(spacing: CassetteSpacing.m) {
            ProgressView()
            Text(vm.loadedCount == 0 ? "Loading songs…" : "\(vm.loadedCount.formatted()) songs loaded…")
                .font(.cassetteBody)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut, value: vm.loadedCount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func songList(_ vm: SongsListViewModel) -> some View {
        let songs = vm.displaySongs
        return ScrollViewReader { proxy in
            List {
                if vm.didTruncate {
                    Text("Showing the first \(songs.count.formatted()) songs.")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                playShuffleHeader(vm, songs)
                SongsListRows(
                    songs: songs,
                    serverId: container?.serverState.activeServer?.id ?? UUID(),
                    downloadingIds: vm.downloadingIds,
                    isFavorite: { isFavorite($0) },
                    onTap: { play(songs, at: $0) },
                    onDownload: { id in Task { await vm.downloadSong(id: id) } },
                    onRemoveDownload: { id in Task { await vm.removeDownload(id: id) } }
                )
            }
            .listStyle(.plain)
            .miniPlayerBottomMargin()
            .refreshable { await vm.load(sort: songSort) }
            .bulkDownloadConfirmation(trackCount: downloadWarningCount, isPresented: $showDownloadWarning) {
                Task { await vm.downloadAll() }
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                // The A–Z jump bar only makes sense when sorted by title.
                if songSort == .title && songs.count >= 20 {
                    AlphabetJumpBar(
                        availableLetters: songs.availableAlphabetLetters(keyPath: \.title),
                        onLetterTap: { letter in
                            if let id = firstAlphabetItemID(forLetter: letter, in: songs, keyPath: \.title) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    )
                    .padding(.trailing, 4)
                }
            }
        }
    }

    /// Shuffle / Play / Download, laid out and sized exactly as the album and playlist headers:
    /// 44pt Liquid Glass circles either side of the accent Play capsule. Those views take their
    /// glyph colour from the cover's dominant colour; this list has no cover, so the glyph is
    /// `.primary` and Play keeps its own accent defaults.
    @ViewBuilder
    private func playShuffleHeader(_ vm: SongsListViewModel, _ songs: [DisplayableSong]) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            Button {
                HapticFeedback.medium.trigger()
                Task {
                    guard !songs.isEmpty else { return }
                    let idx = Int.random(in: 0..<songs.count)
                    try? await container?.playerService.play(tracks: songs, startIndex: idx)
                    if container?.playerState.isShuffled != true {
                        await container?.playerService.toggleShuffle()
                    }
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 44)
            }
            .disabled(songs.isEmpty)
            .accessibilityLabel("Shuffle")

            PlayButton(action: {
                Task {
                    guard !songs.isEmpty else { return }
                    try? await container?.playerService.play(tracks: songs, startIndex: 0)
                }
            }, isDisabled: songs.isEmpty || vm.isDownloadingAll)
            .frame(maxWidth: 220)

            downloadAllButton(vm)
        }
        .buttonStyle(.borderless)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.vertical, 4)
    }

    /// Icon-only "download everything in this list", styled like the album/playlist download
    /// button: 44pt glass, `arrow.down.circle` when nothing is local and `.dotted` once some of
    /// the list is. Those views offer a third, destructive state (a trash button wiping the
    /// album's downloads); deleting the whole library from a list header is not the same
    /// affordance, so here a fully-downloaded list simply disables the button.
    /// Icon-only means the accessibility label is all VoiceOver has to go on.
    private func downloadAllButton(_ vm: SongsListViewModel) -> some View {
        Button {
            Task {
                // Re-count against disk on tap: the warning must quote what will actually be
                // fetched, not a number cached at load time.
                let remaining = await vm.refreshPendingDownloadCount()
                guard remaining > 0 else { return }
                if remaining > BulkDownload.confirmationThreshold {
                    downloadWarningCount = remaining
                    showDownloadWarning = true
                } else {
                    await vm.downloadAll()
                }
            }
        } label: {
            Image(systemName: vm.pendingDownloadCount < vm.displaySongs.count
                  ? "arrow.down.circle.dotted"
                  : "arrow.down.circle")
                .font(.cassetteCellTitle)
                .foregroundStyle(.primary)
                // Swapped for a spinner in place, so the row doesn't resize mid-batch.
                .opacity(vm.isDownloadingAll ? 0 : 1)
                .overlay { if vm.isDownloadingAll { ProgressView().controlSize(.small) } }
                .cassetteGlassButton(size: 44)
        }
        .disabled(vm.pendingDownloadCount == 0 || vm.isDownloadingAll)
        .accessibilityLabel(vm.isDownloadingAll ? Text("Downloading all songs") : Text("Download all songs"))
    }

    private func isFavorite(_ song: DisplayableSong) -> Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    private func play(_ songs: [DisplayableSong], at index: Int) {
        Task {
            do {
                try await container?.playerService.play(tracks: songs, startIndex: index)
            } catch {
                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - Live download indicator rows

/// The list's rows, split out so a single `@Query` on `DownloadedTrack` drives every row's
/// downloaded state live. This is the mechanism the album and playlist detail views use; like
/// the playlist one — and unlike the album's, which can key on an album id — a flat library
/// list has nothing to filter on but the server.
private struct SongsListRows: View {
    let songs: [DisplayableSong]
    let downloadingIds: Set<String>
    let isFavorite: (DisplayableSong) -> Bool
    let onTap: (Int) -> Void
    let onDownload: (String) -> Void
    let onRemoveDownload: (String) -> Void

    @Query private var downloadedTracks: [DownloadedTrack]

    init(
        songs: [DisplayableSong],
        serverId: UUID,
        downloadingIds: Set<String>,
        isFavorite: @escaping (DisplayableSong) -> Bool,
        onTap: @escaping (Int) -> Void,
        onDownload: @escaping (String) -> Void,
        onRemoveDownload: @escaping (String) -> Void
    ) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.isFavorite = isFavorite
        self.onTap = onTap
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
        let sid = serverId
        _downloadedTracks = Query(filter: #Predicate<DownloadedTrack> { $0.serverId == sid })
    }

    var body: some View {
        // Built once per body evaluation rather than inside the row closure: this list can hold
        // the whole library, and rebuilding the set per row would make it quadratic.
        let downloadedSongIds = Set(downloadedTracks.map(\.songId))
        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
            let liveDownloaded = downloadedSongIds.contains(song.id)
            let isDownloading = downloadingIds.contains(song.id)
            SongRow(
                song: song.withDownloaded(liveDownloaded),
                index: index + 1,
                showCoverArt: true,
                isFavorite: isFavorite(song),
                onDownload: (liveDownloaded || isDownloading) ? nil : { onDownload(song.id) },
                onRemoveDownload: liveDownloaded ? { onRemoveDownload(song.id) } : nil,
                isDownloading: isDownloading
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap(index) }
            // The A-Z jump bar scrolls to these ids; keep them on the row itself.
            .id(song.id)
        }
    }
}
