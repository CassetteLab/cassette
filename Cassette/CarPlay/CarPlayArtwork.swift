// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import CarPlay
import UIKit

/// Cover art for CarPlay rows.
///
/// Goes through `ArtworkImageCache` rather than fetching URLs directly: the cache already carries
/// the custom headers a reverse-proxied server needs, caps concurrent downloads, and remembers what
/// it has. A plain URLSession here would break every Cloudflare Access user.
@MainActor
enum CarPlayArtwork {
    /// Fills in a row's image once it arrives. The row is already on screen by then, and CarPlay
    /// redraws it — so nothing waits on the network before the driver sees the list.
    static func attach(
        to item: CPListItem,
        coverArtId: String?,
        cache: ArtworkImageCache,
        size: CGSize
    ) {
        guard let coverArtId else { return }
        Task { @MainActor in
            guard let image = await cache.load(coverArtId: coverArtId) else { return }
            item.setImage(fitted(image, to: size))
        }
    }

    static func load(
        coverArtIds: [String],
        cache: ArtworkImageCache,
        size: CGSize
    ) async -> [UIImage] {
        var images: [UIImage] = []
        for id in coverArtIds {
            guard let image = await cache.load(coverArtId: id) else { continue }
            images.append(fitted(image, to: size))
        }
        return images
    }

    /// CarPlay sizes its rows from `maximumImageSize`; handing it anything larger wastes memory in
    /// a process that also plays audio, and anything smaller renders soft on a car screen.
    static func fitted(_ image: UIImage, to size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
