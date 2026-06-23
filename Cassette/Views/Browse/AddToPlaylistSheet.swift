// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct AddToPlaylistSheet: View {
    let song: DisplayableSong

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AddToPlaylistViewModel?
    @State private var showCreateSheet = false
    @State private var pendingDuplicate: DuplicateConfirmation?

    var body: some View {
        Group {
            #if os(macOS)
            macOSContent
            #else
            NavigationStack {
                Group {
                    if let vm {
                        content(vm)
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle("Add to Playlist")
                .navigationBarTitleDisplayModeInline()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            #endif
        }
        .onAppear {
            guard vm == nil,
                  let svc = container?.playlistService,
                  let toast = container?.toastService else { return }
            let newVM = AddToPlaylistViewModel(
                song: song,
                playlistService: svc,
                toastService: toast
            )
            vm = newVM
            Task { @MainActor in
                await newVM.load()
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet { playlist in
                Task {
                    if await vm?.handleNewPlaylistCreated(playlist) == true {
                        dismiss()
                    }
                }
            }
        }
        .alert(
            "Already in Playlist",
            isPresented: Binding(
                get: { pendingDuplicate != nil },
                set: { if !$0 { pendingDuplicate = nil } }
            ),
            presenting: pendingDuplicate
        ) { dup in
            Button("Cancel", role: .cancel) {
                pendingDuplicate = nil
            }
            Button("Add Anyway") {
                guard let vm else { return }
                let playlist = dup.playlist
                pendingDuplicate = nil
                Task {
                    if await vm.forceAdd(to: playlist) {
                        dismiss()
                    }
                }
            }
        } message: { dup in
            Text("\"\(dup.songName)\" is already in \"\(dup.playlistName)\". Add it again?")
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Playlist")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Divider()
            Group {
                if let vm {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 380)
    }
    #endif

    @ViewBuilder
    private func content(_ vm: AddToPlaylistViewModel) -> some View {
        if vm.isLoading && vm.playlists.isEmpty {
            ProgressView()
        } else {
            List {
                Section {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("New Playlist", systemImage: "plus.circle")
                            .foregroundStyle(Color.cassetteAccent)
                    }
                }

                if vm.playlists.isEmpty {
                    Section {
                        Text("No playlists yet. Create one above.")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(vm.playlists) { playlist in
                            Button {
                                HapticFeedback.light.trigger()
                                Task {
                                    let result = await vm.checkAndAdd(to: playlist)
                                    switch result {
                                    case .added:
                                        dismiss()
                                    case .duplicate:
                                        pendingDuplicate = DuplicateConfirmation(
                                            playlist: playlist,
                                            songName: song.title
                                        )
                                    case .failed:
                                        break
                                    }
                                }
                            } label: {
                                AddToPlaylistRow(playlist: playlist, vm: vm)
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.addingToPlaylistIds.contains(playlist.id))
                        }
                    }
                }
            }
            .cassetteSheetListStyle()
        }
    }
}

// MARK: - Duplicate alert data

private struct DuplicateConfirmation {
    let playlist: Playlist
    let songName: String
    var playlistName: String { playlist.name }
}

// MARK: - Row (label-only, no tap logic)

private struct AddToPlaylistRow: View {
    let playlist: Playlist
    let vm: AddToPlaylistViewModel

    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    private var isAdding: Bool { vm.addingToPlaylistIds.contains(playlist.id) }

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            PlaylistCoverThumbnail(playlistId: playlist.id, serverId: nil, coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(playlist.songCount) track\(playlist.songCount == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isAdding {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
        .task(id: playlist.id) {
            coverImage = await artworkImageCache.load(coverArtId: playlist.coverArt ?? playlist.id)
        }
    }
}
