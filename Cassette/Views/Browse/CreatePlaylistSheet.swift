// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var viewModel: CreatePlaylistViewModel?
    @State private var selectedGradient: PlaylistGradientShape?
    @FocusState private var nameFieldFocused: Bool

    var onCreated: ((PlaylistWithSongs) -> Void)? = nil

    #if os(iOS)
    @State private var pendingImage: UIImage?
    @State private var showImageOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    #endif

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
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel?.isCreating == true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let vm = viewModel, let c = container else { return }
                        Task {
                            if let created = await vm.create() {
                                await applyCover(playlistId: created.id, container: c)
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
        #if os(iOS)
        .confirmationDialog("Add Cover Art", isPresented: $showImageOptions, titleVisibility: .visible) {
            Button("Choose from Library") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImagePicker = true }
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a Photo") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                }
            }
            Button("Browse Files") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showFilePicker = true }
            }
            if pendingImage != nil {
                Button("Remove Image", role: .destructive) { pendingImage = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showImagePicker) {
            ImagePickerController(sourceType: .photoLibrary, onPick: { pendingImage = $0 }, onCancel: {})
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePickerController(sourceType: .camera, onPick: { pendingImage = $0 }, onCancel: {})
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.jpeg, .png, .heic, .webP],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pendingImage = UIImage(data: data)
            }
        }
        #endif
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
            Section("Cover") {
                coverPicker
            }

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

    private var hasPhoto: Bool {
        #if os(iOS)
        return pendingImage != nil
        #else
        return false
        #endif
    }

    /// Cross-platform cover picker: "None" + (iOS) a photo option + the six gradient forms. The gradient
    /// previews show the neutral base color (an empty playlist has no first track to derive from yet — that
    /// derivation lands in Phase 2b); the forms are still distinguishable by geometry.
    private var coverPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CassetteSpacing.m) {
                coverSwatch(isSelected: selectedGradient == nil && !hasPhoto, label: "None", action: {
                    selectedGradient = nil
                    #if os(iOS)
                    pendingImage = nil
                    #endif
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CassetteCornerRadius.standard).fill(Color.secondary.opacity(0.15))
                        Image(systemName: "nosign").font(.title3).foregroundStyle(.secondary)
                    }
                }

                #if os(iOS)
                coverSwatch(isSelected: hasPhoto, label: "Photo", action: {
                    selectedGradient = nil
                    showImageOptions = true
                }) {
                    ZStack {
                        if let pending = pendingImage {
                            Image(uiImage: pending).resizable().aspectRatio(1, contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: CassetteCornerRadius.standard).fill(Color.secondary.opacity(0.15))
                            Image(systemName: "photo").font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }
                #endif

                ForEach(PlaylistGradientShape.allCases) { shape in
                    coverSwatch(isSelected: selectedGradient == shape, label: shape.displayName, action: {
                        selectedGradient = shape
                        #if os(iOS)
                        pendingImage = nil
                        #endif
                    }) {
                        PlaylistGradientView(spec: .neutral(shape: shape))
                    }
                }
            }
            .padding(.vertical, CassetteSpacing.xs)
        }
    }

    @ViewBuilder
    private func coverSwatch<Content: View>(
        isSelected: Bool,
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            VStack(spacing: CassetteSpacing.xs) {
                content()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard))
                    .overlay(
                        RoundedRectangle(cornerRadius: CassetteCornerRadius.standard)
                            .strokeBorder(Color.cassetteAccent, lineWidth: isSelected ? 3 : 0)
                    )
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.cassetteAccent : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Applies the chosen cover after the playlist is created: render+cache+upload via PlaylistCoverManager
    /// (cross-platform, supersedes the old iOS-only inline upload) and persist a gradient choice client-side.
    private func applyCover(playlistId: String, container c: AppContainer) async {
        let manager = PlaylistCoverManager(
            serverState: c.serverState,
            serverService: c.serverService,
            downloadService: c.downloadService,
            artworkImageCache: c.artworkImageCache
        )
        if let shape = selectedGradient {
            // Empty playlist at creation → neutral base color now; first-track derivation is Phase 2b.
            let spec = PlaylistGradientSpec.neutral(shape: shape)
            await manager.applyGradientCover(spec, playlistId: playlistId)
            if let serverId = c.serverState.activeServer?.id {
                PlaylistCoverStore(modelContainer: c.modelContainer)
                    .save(spec, playlistId: playlistId, serverId: serverId, isUserPicked: true)
            }
            return
        }
        #if os(iOS)
        if let image = pendingImage, let data = image.jpegData(compressionQuality: 0.85) {
            await manager.applyImageCover(data, playlistId: playlistId)
        }
        #endif
    }
}
