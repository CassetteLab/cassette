// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Visual affordance signalling that a list row can be drag-reordered.
///
/// Purely visual — the host view owns the actual reorder (SwiftUI `List.onMove`, or
/// `.onDrag`/`.onDrop` + a `DropDelegate`) and any haptics. Drop it at a row's trailing edge.
///
/// Pass `isActive` for the dragged/active state where the host tracks it (e.g. edit-pinned's
/// `draggedItem`); `List.onMove` has no clean per-row drag state, so queue rows use the default.
struct ReorderIndicator: View {
    /// When true, the grip tints with the playing accent (host-driven drag state).
    var isActive: Bool = false
    /// Idle (non-dragging) tint. Defaults to `.secondary`; a surface over an adaptive background (e.g. the
    /// full player's cover blur) can pass a luminance-matched color so the grip stays legible.
    var idleColor: Color = .secondary

    @Environment(\.cassettePlayingAccent) private var playingAccent

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.cassetteCaption)
            .foregroundStyle(isActive ? playingAccent : idleColor)
            .accessibilityLabel("Reorder")
    }
}

#Preview("Light") {
    HStack(spacing: CassetteSpacing.l) {
        ReorderIndicator()
        ReorderIndicator(isActive: true)
    }
    .padding()
}

#Preview("Dark") {
    HStack(spacing: CassetteSpacing.l) {
        ReorderIndicator()
        ReorderIndicator(isActive: true)
    }
    .padding()
    .preferredColorScheme(.dark)
}
