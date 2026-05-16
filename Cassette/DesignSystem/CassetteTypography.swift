// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Typography tokens
//
// Design rules:
//   • SF Pro Rounded is used only for headings that need emphasis (player title, detail headers).
//     Body, cells, and captions stay in SF Pro Default to avoid a "kids app" feel.
//   • All sizes come from Dynamic Type styles — no hardcoded points — so they scale
//     with the user's accessibility text size setting.
//   • Font.weight is always set explicitly; never rely on the Dynamic Type default weight.

extension Font {
    // MARK: Headings (SF Pro Rounded)

    /// Full-player track title. ~28pt. Rounded, bold.
    static let cassettePlayerTitle = Font.system(.title, design: .rounded, weight: .bold)

    /// Album or artist name in detail-screen headers. ~22pt. Rounded, semibold.
    static let cassetteDetailTitle = Font.system(.title2, design: .rounded, weight: .semibold)

    /// Section header labels (e.g. "Albums", "Tracks"). ~17pt. Rounded, semibold.
    static let cassetteSectionTitle = Font.system(.headline, design: .rounded, weight: .semibold)

    // MARK: Body & cells (SF Pro Default)

    /// Standard readable body. ~17pt. Regular.
    static let cassetteBody = Font.system(.body, design: .default, weight: .regular)

    /// Primary label in list cells (track title, album name). ~16pt. Semibold.
    static let cassetteCellTitle = Font.system(.callout, design: .default, weight: .semibold)

    /// Secondary label in cells (artist name below track title). ~15pt. Regular.
    static let cassetteCellSubtitle = Font.system(.subheadline, design: .default, weight: .regular)

    /// Tertiary metadata (duration, year, genre). ~12pt. Regular.
    static let cassetteCaption = Font.system(.caption, design: .default, weight: .regular)

    /// Very small labels (track count badge, etc.). ~11pt. Regular.
    static let cassetteCaption2 = Font.system(.caption2, design: .default, weight: .regular)

    // MARK: Lyrics

    /// Lyric line text in the full-player lyrics view. ~28pt. Rounded, semibold.
    static let cassetteLyricsLine = Font.system(.title, design: .rounded, weight: .semibold)
}
