// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// The Apple-Music-style cover-picker carousel shared by the create and edit flows: a leading option
/// (None / Current) + (where available) a Photo option + the six gradient forms, as tappable swatches.
/// Pure render + callbacks — the caller owns all selection state. Cross-platform.
struct PlaylistCoverPicker: View {
    let selectedGradient: PlaylistGradientShape?
    let isPhotoSelected: Bool
    var photoPreview: PlatformImage? = nil
    var showsPhotoOption: Bool = true
    var leadingLabel: String = "None"
    /// When set (edit flow), the leading swatch shows the current cover instead of the "none" glyph.
    var leadingCoverArtId: String? = nil
    let onSelectLeading: () -> Void
    var onSelectPhoto: () -> Void = {}
    let onSelectGradient: (PlaylistGradientShape) -> Void

    private var isLeadingSelected: Bool { selectedGradient == nil && !isPhotoSelected }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CassetteSpacing.m) {
                PlaylistCoverSwatch(isSelected: isLeadingSelected, label: leadingLabel, action: onSelectLeading) {
                    if let leadingCoverArtId {
                        CoverArtView(id: leadingCoverArtId, size: 120)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: CassetteCornerRadius.standard).fill(Color.secondary.opacity(0.15))
                            Image(systemName: "nosign").font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }

                if showsPhotoOption {
                    PlaylistCoverSwatch(isSelected: isPhotoSelected, label: "Photo", action: onSelectPhoto) {
                        ZStack {
                            if let photoPreview {
                                platformImage(photoPreview).resizable().aspectRatio(1, contentMode: .fill)
                            } else {
                                RoundedRectangle(cornerRadius: CassetteCornerRadius.standard).fill(Color.secondary.opacity(0.15))
                                Image(systemName: "photo").font(.title3).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                ForEach(PlaylistGradientShape.allCases) { shape in
                    PlaylistCoverSwatch(
                        isSelected: selectedGradient == shape,
                        label: shape.displayName,
                        action: { onSelectGradient(shape) }
                    ) {
                        PlaylistGradientView(spec: .neutral(shape: shape))
                    }
                }
            }
            .padding(.vertical, CassetteSpacing.xs)
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

/// A single 60pt cover-picker swatch — rounded tile + caption, ringed when selected.
struct PlaylistCoverSwatch<Content: View>: View {
    let isSelected: Bool
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(isSelected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.label = label
        self.action = action
        self.content = content
    }

    var body: some View {
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
}
