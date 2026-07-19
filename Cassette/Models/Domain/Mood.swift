// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// A mood the app can build a weekly playlist for.
///
/// `query` is deliberately English regardless of the app's language: it is fed to AudioMuse's CLAP
/// model, which embeds audio against English text. Translating it would degrade the match. The
/// user-facing `title` is localised; the query is not.
nonisolated enum Mood: String, CaseIterable, Sendable, Identifiable {
    case night
    case energetic
    case workout
    case chill
    case focus

    var id: String { rawValue }

    /// Free-text prompt sent to `POST /api/clap/search`.
    var query: String {
        switch self {
        case .night:     return "late night calm atmospheric"
        case .energetic: return "energetic upbeat high energy"
        case .workout:   return "intense driving workout rhythm"
        case .chill:     return "relaxed mellow laid back"
        case .focus:     return "focus instrumental background"
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .night:     return "Night"
        case .energetic: return "Energetic"
        case .workout:   return "Workout"
        case .chill:     return "Chill"
        case .focus:     return "Focus"
        }
    }

    var symbolName: String {
        switch self {
        case .night:     return "moon.stars"
        case .energetic: return "bolt"
        case .workout:   return "figure.run"
        case .chill:     return "leaf"
        case .focus:     return "headphones"
        }
    }

    /// Name of the server-side playlist backing this mood. Prefixed so the five are recognisable
    /// among the user's own playlists, and so `fetchMoodPlaylists` can find them again by name.
    var playlistName: String { "\(Self.playlistPrefix)\(rawValue.capitalized)" }

    static let playlistPrefix = "Cassette · "

    /// Tracks requested per mood. Above the 50 a listener plausibly gets through in a week, below
    /// the point where CLAP's tail stops resembling the prompt.
    static let trackCount = 75
}
