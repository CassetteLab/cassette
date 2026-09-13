// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// What produced a playlist, so the list can be filtered by nature rather than by name.
///
/// The four are genuinely different things, not variants of one: a user may want their own server
/// playlists without the generated noise, or the reverse. Only ``userCreated`` is something the
/// person actually made.
nonisolated enum PlaylistKind: String, CaseIterable, Sendable, Identifiable, Codable {
    /// The five weekly mood playlists maintained by ``MoodPlaylistService``.
    case moods
    /// The annual "Cassette Wrapped <year>" playlist.
    case wrapped
    /// The virtual per-artist best-of derived from the user's stars. See ``ArtistBestOf``.
    case artistBestOf
    /// Everything else: playlists the user made on the server.
    case userCreated

    var id: String { rawValue }

    /// Order shown in the filter menu: generated first, the user's own last, so the noisy ones are
    /// the ones the eye lands on when they go looking for the checkbox to clear.
    static let displayOrder: [PlaylistKind] = [.moods, .wrapped, .artistBestOf, .userCreated]

    var title: String.LocalizationValue {
        switch self {
        case .moods:        return "Mood Playlists"
        case .wrapped:      return "Cassette Wrapped"
        case .artistBestOf: return "Best Of Artists"
        case .userCreated:  return "My Playlists"
        }
    }
}

// MARK: - Persisted filter

// `nonisolated` explicitly: the project defaults to MainActor isolation, which an extension picks up
// even when the type itself is nonisolated, and these are read from the snapshot and the service.
nonisolated extension PlaylistKind {
    /// Decodes the per-server hidden set from its stored form.
    ///
    /// The *hidden* kinds are stored rather than the visible ones, so `nil` — what SwiftData's
    /// lightweight migration gives every existing server — means "nothing hidden", i.e. exactly the
    /// behaviour that shipped before this filter existed. It also means a kind added later is
    /// visible by default instead of silently absent from everyone's list.
    static func decodeHidden(_ raw: String?) -> Set<PlaylistKind> {
        guard let raw, !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").compactMap { PlaylistKind(rawValue: String($0)) })
    }

    /// Encodes a hidden set for storage; an empty set stores as `nil` so the default state stays
    /// indistinguishable from a server that never touched the filter.
    static func encodeHidden(_ kinds: Set<PlaylistKind>) -> String? {
        guard !kinds.isEmpty else { return nil }
        return displayOrder.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Classification

/// Decides which ``PlaylistKind`` a server playlist belongs to.
///
/// ``PlaylistKind/artistBestOf`` is deliberately not reachable here: best-of playlists are derived
/// locally from stars and never exist as a `Playlist` at all, so they are classified by
/// construction rather than by inspection.
nonisolated struct PlaylistClassifier: Sendable {
    /// Server ids of the mood playlists, as recorded by ``MoodPlaylistService`` after each sync.
    private let moodPlaylistIds: Set<String>

    init(moodPlaylistIds: Set<String>) {
        self.moodPlaylistIds = moodPlaylistIds
    }

    /// Reads the mood ids this server has cached. Empty before the first sync, and after a
    /// reinstall — which is why classification does not rely on them alone.
    init(serverId: String, moodPreferences: MoodPreferences = MoodPreferences()) {
        self.init(moodPlaylistIds: Set(
            Mood.allCases.compactMap { moodPreferences.playlistId(mood: $0, serverId: serverId) }
        ))
    }

    /// Ids first, then the name prefix.
    ///
    /// The prefix fallback is what survives a reinstall: UserDefaults is gone but the server
    /// playlists are not, and without it every generated playlist would read as the user's own
    /// until the next weekly sync. It is the same signal the two generators already use to find
    /// their own playlists again — a non-localised, brand-namespaced prefix the app writes itself —
    /// so the only false positive is a playlist the user named "Cassette · …" by hand.
    func kind(of playlist: Playlist) -> PlaylistKind {
        if moodPlaylistIds.contains(playlist.id) { return .moods }
        if playlist.name.hasPrefix(Mood.playlistPrefix) { return .moods }
        if isWrapped(playlist.name) { return .wrapped }
        return .userCreated
    }

    /// Requires a parseable year after the prefix, matching `fetchYearlyPlaylists` — so a playlist
    /// called "Cassette Wrapped Favourites" stays the user's.
    private func isWrapped(_ name: String) -> Bool {
        let prefix = WrappedPlaylistService.wrappedPlaylistNamePrefix
        guard name.hasPrefix(prefix) else { return false }
        return Int(name.dropFirst(prefix.count)) != nil
    }
}
