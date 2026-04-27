// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct EditPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container

    let playlist: PlaylistWithSongs
    /// Called when the playlist is deleted so the presenting view can pop back.
    var onDeleted: () -> Void = {}

    @State private var viewModel: EditPlaylistViewModel?
    @State private var showCancelConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showAddTracksComingSoon = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel?.hasFormChanges == true {
                            showCancelConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(viewModel?.isSavingForm == true || viewModel?.isDeletingPlaylist == true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            guard let vm = viewModel else { return }
                            if vm.hasFormChanges {
                                if await vm.saveForm() { dismiss() }
                            } else {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel?.isSavingForm == true {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Done").fontWeight(.semibold)
                        }
                    }
                    .disabled(
                        viewModel?.isSavingForm == true
                        || (viewModel?.hasFormChanges == true && viewModel?.canSaveForm == false)
                    )
                }
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Your changes to the playlist details will be lost.")
            }
            .alert("Delete Playlist", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        guard let vm = viewModel else { return }
                        if await vm.deletePlaylist() {
                            onDeleted()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("This will permanently delete the playlist. This action cannot be undone.")
            }
            .alert("Coming Soon", isPresented: $showAddTracksComingSoon) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Adding tracks from this screen will be available in the next update. For now, use \"Add to Playlist\" from any song's context menu.")
            }
        }
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = EditPlaylistViewModel(
                    playlist: playlist,
                    playlistService: c.playlistService,
                    toastService: c.toastService
                )
            }
        }
        .interactiveDismissDisabled(
            viewModel?.hasFormChanges == true
            || viewModel?.isSavingForm == true
            || viewModel?.isDeletingPlaylist == true
        )
    }

    @ViewBuilder
    private func content(_ vm: EditPlaylistViewModel) -> some View {
        Form {
            Section("Name") {
                TextField("Playlist name", text: Bindable(vm).name)
                    .submitLabel(.next)
            }

            Section("Description") {
                TextField(
                    "What's this playlist about?",
                    text: Bindable(vm).description,
                    axis: .vertical
                )
                .lineLimit(3...6)
            }

            Section {
                Button {
                    showAddTracksComingSoon = true
                } label: {
                    Label("Add Tracks", systemImage: "plus.circle")
                        .foregroundStyle(Color.cassetteAccent)
                }
            }

            Section("Tracks (\(vm.songs.count))") {
                ForEach(Array(vm.songs.enumerated()), id: \.offset) { index, song in
                    EditPlaylistTrackRow(song: song, index: index + 1)
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet.sorted(by: >) {
                            await vm.removeTrack(at: index)
                        }
                    }
                }
                .onMove { source, destination in
                    Task { await vm.moveTracks(from: source, to: destination) }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if vm.isDeletingPlaylist {
                            ProgressView()
                        } else {
                            Text("Delete Playlist")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(vm.isDeletingPlaylist || vm.isSavingForm)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Track row

private struct EditPlaylistTrackRow: View {
    let song: Song
    let index: Int

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            Text("\(index)")
                .font(.cassetteCaption)
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text(song.artist ?? "Unknown Artist")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let duration = song.duration {
                Text(Duration.seconds(TimeInterval(duration)).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, CassetteSpacing.xs)
    }
}
