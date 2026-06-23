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
    /// Whether the PHOTO is the chosen cover. Separate from "a photo is picked" (pendingImage) so a picked
    /// photo's preview survives switching to another cover and back.
    @State private var photoIsCover = false
    @FocusState private var nameFieldFocused: Bool

    var onCreated: ((PlaylistWithSongs) -> Void)? = nil

    #if os(iOS)
    @State private var pendingImage: UIImage?
    @State private var showImageOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var imageToCrop: CroppableImage?
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
        .tint(Color.cassetteAccent)
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
            ImagePickerController(sourceType: .photoLibrary, allowsEditing: false, onPick: { presentCrop($0) }, onCancel: {})
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePickerController(sourceType: .camera, allowsEditing: false, onPick: { presentCrop($0) }, onCancel: {})
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $imageToCrop) { croppable in
            SquareCropView(
                image: croppable.image,
                onCrop: { pendingImage = $0; imageToCrop = nil },
                onCancel: { imageToCrop = nil }
            )
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.jpeg, .png, .heic, .webP],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                presentCrop(img)
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
        ScrollView {
            VStack(spacing: CassetteSpacing.xl) {
                coverCarousel(vm)
                    .padding(.top, CassetteSpacing.s)

                VStack(spacing: CassetteSpacing.s) {
                    // Editorial centered title + discreet description, no field chrome, no separators (AM style).
                    TextField("Playlist Title", text: Bindable(vm).name)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .padding(.vertical, CassetteSpacing.s)

                    TextField("Description", text: Bindable(vm).description, axis: .vertical)
                        .multilineTextAlignment(.center)
                        .lineLimit(1...4)
                }
                .padding(.horizontal, CassetteSpacing.l)
            }
            .padding(.top, CassetteSpacing.m)
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

    private var showsPhotoOption: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    private var photoPreviewImage: PlatformImage? {
        #if os(iOS)
        return pendingImage
        #else
        return nil
        #endif
    }

    #if os(iOS)
    /// Defer presenting the crop screen so the picker fully dismisses first (sequential full-screen covers).
    private func presentCrop(_ image: UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            imageToCrop = CroppableImage(image: image)
        }
    }
    #endif

    /// Create-flow cover carousel (Apple-Music direction). The gradient previews show the neutral base color
    /// (an empty playlist has no first track to derive from yet — that derivation is the edit flow's job);
    /// forms differ by geometry. The live title renders into the gradient cards.
    private func coverCarousel(_ vm: CreatePlaylistViewModel) -> some View {
        PlaylistCoverCarousel(
            title: vm.name,
            selectedGradient: selectedGradient,
            isPhotoSelected: photoIsCover,
            photoPreview: photoPreviewImage,
            showsPhotoOption: showsPhotoOption,
            leadingLabel: "None",
            onSelectLeading: {
                selectedGradient = nil
                photoIsCover = false        // keep pendingImage so the photo card preview survives
            },
            onSelectPhoto: {
                // Swipe settled on the photo card → focus the photo as cover, NO modal.
                selectedGradient = nil
                photoIsCover = true
            },
            onRequestPhotoPicker: {
                selectedGradient = nil
                photoIsCover = true
                #if os(iOS)
                showImageOptions = true
                #endif
            },
            onSelectGradient: { shape in
                selectedGradient = shape
                photoIsCover = false        // keep pendingImage so the photo card preview survives
            }
        )
    }

    /// Applies the chosen cover after the playlist is created: render+cache+upload via PlaylistCoverManager
    /// (cross-platform, supersedes the old iOS-only inline upload) and persist a gradient choice client-side.
    private func applyCover(playlistId: String, container c: AppContainer) async {
        let manager = PlaylistCoverManager(
            serverState: c.serverState,
            serverService: c.serverService,
            downloadService: c.downloadService,
            artworkImageCache: c.artworkImageCache,
            coverVersionRegistry: c.coverVersionRegistry
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
        if photoIsCover, let image = pendingImage, let data = image.jpegData(compressionQuality: 0.85) {
            await manager.applyImageCover(data, playlistId: playlistId)
        }
        #endif
    }
}
