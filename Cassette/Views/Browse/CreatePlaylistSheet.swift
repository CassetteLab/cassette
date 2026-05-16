// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import OSLog
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var viewModel: CreatePlaylistViewModel?
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
                                #if os(iOS)
                                if let image = pendingImage {
                                    await uploadCoverImage(image, playlistId: created.id, container: c)
                                }
                                #endif
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
            Button("Choose from Library") { showImagePicker = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a Photo") { showCamera = true }
            }
            Button("Browse Files") { showFilePicker = true }
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
            #if os(iOS)
            Section {
                coverPickerButton
            }
            #endif

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

    #if os(iOS)
    @ViewBuilder
    private var coverPickerButton: some View {
        Button {
            showImageOptions = true
        } label: {
            HStack(spacing: CassetteSpacing.m) {
                ZStack {
                    if let pending = pendingImage {
                        Image(uiImage: pending)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard))
                    } else {
                        RoundedRectangle(cornerRadius: CassetteCornerRadius.standard)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(pendingImage == nil ? "Add Cover Art" : "Change Cover Art")
                    .foregroundStyle(Color.cassetteAccent)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func uploadCoverImage(_ image: UIImage, playlistId: String, container: AppContainer) async {
        guard let jpegData = image.jpegData(compressionQuality: 0.85),
              let snapshot = container.serverState.activeServer,
              let baseURL = URL(string: snapshot.baseURL) else { return }
        do {
            let creds = try await container.serverService.activeCredentials()
            let api = NavidromeNativeAPI(transport: CustomHeadersTransport(headers: creds.customHeaders))
            Logger.playlist.debug("Navidrome auth: requesting JWT for user=\(snapshot.username, privacy: .private)")
            let token = try await api.authenticate(
                baseURL: baseURL,
                username: snapshot.username,
                password: creds.password
            )
            Logger.playlist.debug("Navidrome auth: JWT obtained")
            Logger.playlist.debug("Upload playlist cover: POST /api/playlist/\(playlistId, privacy: .public)/image, cf_headers=\(!creds.customHeaders.isEmpty)")
            try await api.uploadPlaylistCover(
                baseURL: baseURL,
                token: token,
                playlistId: playlistId,
                imageData: jpegData,
                mimeType: "image/jpeg"
            )
            Logger.playlist.debug("Upload playlist cover: success")
        } catch {
            Logger.playlist.warning("CreatePlaylistSheet: cover image upload failed: \(error)")
        }
    }
    #endif
}
