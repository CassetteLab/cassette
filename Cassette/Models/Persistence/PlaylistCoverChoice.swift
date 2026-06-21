// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

/// A client-side record of a playlist's chosen GENERATED cover (gradient form + frozen base color), keyed by
/// `(playlistId, serverId)` — playlist ids collide across servers. Stored per device: the uploaded JPEG is
/// the cross-device source of truth, this record is the local enrichment (re-render crisp, know the choice).
///
/// `isUserPicked` distinguishes an explicit user choice from a system default (e.g. the neutral gradient an
/// empty playlist gets), so a real choice is never silently overwritten.
@Model
final class PlaylistCoverChoice {
    var playlistId: String
    var serverId: UUID
    /// `PlaylistGradientShape.rawValue`.
    var shapeRawValue: String
    var red: Double
    var green: Double
    var blue: Double
    var isUserPicked: Bool
    var updatedAt: Date

    init(
        playlistId: String,
        serverId: UUID,
        spec: PlaylistGradientSpec,
        isUserPicked: Bool,
        updatedAt: Date = Date()
    ) {
        self.playlistId = playlistId
        self.serverId = serverId
        self.shapeRawValue = spec.shape.rawValue
        self.red = spec.red
        self.green = spec.green
        self.blue = spec.blue
        self.isUserPicked = isUserPicked
        self.updatedAt = updatedAt
    }

    /// Rebuilds the frozen spec, or `nil` if the stored form no longer exists (forward-compatible).
    var spec: PlaylistGradientSpec? {
        guard let shape = PlaylistGradientShape(rawValue: shapeRawValue) else { return nil }
        return PlaylistGradientSpec(shape: shape, red: red, green: green, blue: blue)
    }
}
