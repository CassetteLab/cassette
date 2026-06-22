// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Apple-Music-style cover carousel for the create + edit playlist sheets: wide square cards that snap and
/// peek (real paging, not enlarged swatches), the live playlist title rendered INTO the gradient card (the
/// `WrappedCoverRenderer` look — title over the gradient), a leading None/Current card, a Photo card, and the
/// six gradient forms. A pagination-dot row + a camera shortcut sit below. Pure render + callbacks — the caller
/// owns selection state. Cross-platform; the snap/scroll-position APIs are iOS 17 / macOS 14+ (the app targets
/// well beyond that).
struct PlaylistCoverCarousel: View {
    /// Live title rendered over the gradient cards (empty → a muted placeholder).
    let title: String
    let selectedGradient: PlaylistGradientShape?
    let isPhotoSelected: Bool
    var photoPreview: PlatformImage? = nil
    var showsPhotoOption: Bool = true
    /// "None" (create) or "Current" (edit).
    var leadingLabel: String = "None"
    /// Edit flow: the leading card shows the current cover instead of the empty glyph.
    var leadingCoverArtId: String? = nil
    let onSelectLeading: () -> Void
    var onSelectPhoto: () -> Void = {}
    let onSelectGradient: (PlaylistGradientShape) -> Void

    @State private var scrolledOption: CoverOption?

    enum CoverOption: Hashable {
        case leading
        case photo
        case gradient(PlaylistGradientShape)
    }

    private var options: [CoverOption] {
        var opts: [CoverOption] = [.leading]
        if showsPhotoOption { opts.append(.photo) }
        opts += PlaylistGradientShape.allCases.map { .gradient($0) }
        return opts
    }

    private var selectedOption: CoverOption {
        if let selectedGradient { return .gradient(selectedGradient) }
        if isPhotoSelected { return .photo }
        return .leading
    }

    var body: some View {
        VStack(spacing: CassetteSpacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CassetteSpacing.m) {
                    ForEach(options, id: \.self) { option in
                        card(option)
                            .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: CassetteSpacing.m)
                            .id(option)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, CassetteSpacing.l, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledOption)
            .frame(height: 240)

            dotRow
        }
        .onAppear { scrolledOption = selectedOption }
        .onChange(of: scrolledOption) { _, option in
            // Only act when the user actually settled on a DIFFERENT option than what's selected — so the
            // initial onAppear set (and a re-settle on the current card) never re-fires (notably never
            // re-opens the photo picker).
            guard let option, option != selectedOption else { return }
            commitSelection(option)
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func card(_ option: CoverOption) -> some View {
        ZStack {
            switch option {
            case .leading:
                if let leadingCoverArtId {
                    CoverArtView(id: leadingCoverArtId, size: 600)
                } else {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "nosign")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            case .photo:
                if let photoPreview {
                    platformImage(photoPreview).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.12)
                    Circle()
                        .fill(Color.cassetteAccent)
                        .frame(width: 72, height: 72)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
            case .gradient(let shape):
                PlaylistGradientView(spec: .neutral(shape: shape))
                titleOverlay
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
    }

    /// The live title rendered over the gradient — the WrappedCoverRenderer pattern (white, bold, rounded,
    /// top-leading). Empty title shows a muted placeholder so the card never looks broken.
    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.isEmpty ? "Playlist Title" : title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(title.isEmpty ? 0.6 : 1))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CassetteSpacing.l)
    }

    // MARK: - Dots + camera

    private var dotRow: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    Circle()
                        .fill(option == selectedOption ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            HStack {
                Button(action: onSelectPhoto) {
                    Image(systemName: "camera.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.leading, CassetteSpacing.l)
        }
    }

    // MARK: - Selection

    private func commitSelection(_ option: CoverOption) {
        switch option {
        case .leading: onSelectLeading()
        case .photo: onSelectPhoto()
        case .gradient(let shape): onSelectGradient(shape)
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}
