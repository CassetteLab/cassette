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
    /// Focus the photo option (swipe settled on the photo card) — selects it as the cover, NO modal.
    var onSelectPhoto: () -> Void = {}
    /// Explicit request to open the system photo picker (tap the photo card or the camera button) — distinct
    /// from onSelectPhoto so swiping past/onto the photo card never auto-opens the picker.
    var onRequestPhotoPicker: () -> Void = {}
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

    /// Card width as a fraction of the carousel width — the rest is the peek of the neighbouring cards.
    private let cardFraction: CGFloat = 0.74

    var body: some View {
        VStack(spacing: CassetteSpacing.m) {
            GeometryReader { geo in
                let cardSize = geo.size.width * cardFraction
                let sidePeek = max(0, (geo.size.width - cardSize) / 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: CassetteSpacing.m) {
                        ForEach(options, id: \.self) { option in
                            card(option)
                                .frame(width: cardSize, height: cardSize)   // SQUARE
                                .id(option)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, sidePeek, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledOption)
            }
            // Container height == card height (square) so the geometry resolves: width × cardFraction·width.
            .aspectRatio(1 / cardFraction, contentMode: .fit)

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
                    platformImage(photoPreview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
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
        .contentShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        .onTapGesture { handleTap(option) }
    }

    /// Tap centers the card; tapping the photo card ALSO opens the picker (the only path that opens the modal).
    private func handleTap(_ option: CoverOption) {
        withAnimation(.snappy) { scrolledOption = option }
        if case .photo = option { onRequestPhotoPicker() }
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
                Button(action: onRequestPhotoPicker) {
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
