// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct LoadingStateView: View {
    var message: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: CassetteSpacing.m) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.cassetteAccent)

            if let message {
                Text(message)
                    .font(.cassetteBody)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CassetteSpacing.xl)
    }
}

// MARK: - Skeleton components

struct SkeletonAlbumCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            RoundedRectangle(cornerRadius: CassetteCornerRadius.standard)
                .fill(Color.primary.opacity(0.08))
                .aspectRatio(1, contentMode: .fit)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.08))
                .frame(height: 12)
                .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
                .frame(height: 10)
                .frame(maxWidth: 80)
        }
        .shimmer()
    }
}

struct SkeletonSongRow: View {
    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            RoundedRectangle(cornerRadius: CassetteCornerRadius.xs)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 13)
                    .frame(maxWidth: 180)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 11)
                    .frame(maxWidth: 120)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .shimmer()
    }
}

// MARK: - Shimmer modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.25), location: 0.4),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 2)
                    .offset(x: phase * width * 2)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview("Spinner") {
    LoadingStateView(message: "Loading albums…")
}

#Preview("Skeleton cards") {
    let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)]
    ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<8, id: \.self) { _ in SkeletonAlbumCard() }
        }
        .padding()
    }
}

#Preview("Skeleton rows") {
    List {
        ForEach(0..<8, id: \.self) { _ in SkeletonSongRow() }
    }
    .listStyle(.plain)
}
