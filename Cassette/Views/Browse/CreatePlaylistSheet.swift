// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var viewModel: CreatePlaylistViewModel?
    @FocusState private var nameFieldFocused: Bool

    var onCreated: ((PlaylistWithSongs) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel?.isCreating == true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let vm = viewModel else { return }
                        Task {
                            if let created = await vm.create() {
                                onCreated?(created)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel?.isCreating == true {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!(viewModel?.canCreate ?? false))
                }
            }
        }
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = CreatePlaylistViewModel(
                    playlistService: c.playlistService,
                    toastService: c.toastService
                )
            }
            nameFieldFocused = true
        }
    }

    @ViewBuilder
    private func content(_ vm: CreatePlaylistViewModel) -> some View {
        Form {
            Section("Name") {
                TextField("My Awesome Playlist", text: Bindable(vm).name)
                    .focused($nameFieldFocused)
                    .submitLabel(.next)
            }
            Section("Description (optional)") {
                TextField(
                    "What's this playlist about?",
                    text: Bindable(vm).description,
                    axis: .vertical
                )
                .lineLimit(3...6)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
