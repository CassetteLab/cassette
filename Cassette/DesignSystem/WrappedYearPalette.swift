// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

nonisolated enum WrappedYearPalette {
    /// Returns 3 deterministic colors derived from the given year, cycling every 8 years.
    /// Used as source palette for mesh gradient backgrounds in Wrapped hero, year card,
    /// and cover generation.
    static func colors(for year: Int) -> [Color] {
        switch year % 8 {
        case 0: // 2024 — warm sunset
            return [
                Color(red: 1.000, green: 0.549, blue: 0.259), // #FF8C42 warm orange
                Color(red: 0.776, green: 0.157, blue: 0.157), // #C62828 deep red
                Color(red: 0.976, green: 0.659, blue: 0.145), // #F9A825 golden yellow
            ]
        case 1: // 2025 — electric dusk
            return [
                Color(red: 0.671, green: 0.278, blue: 0.737), // #AB47BC magenta purple
                Color(red: 0.925, green: 0.251, blue: 0.478), // #EC407A hot pink
                Color(red: 0.157, green: 0.208, blue: 0.576), // #283593 deep indigo
            ]
        case 2: // 2026 — Cassette identity
            return [
                Color(red: 1.000, green: 0.498, blue: 0.247), // #FF7F3F cassetteAccent
                Color(red: 0.824, green: 0.184, blue: 0.184), // #D22F2F vermillion
                Color(red: 1.000, green: 0.420, blue: 0.616), // #FF6B9D warm pink
            ]
        case 3: // 2027 — oceanic
            return [
                Color(red: 0.000, green: 0.737, blue: 0.831), // #00BCD4 cyan
                Color(red: 0.000, green: 0.588, blue: 0.533), // #009688 teal
                Color(red: 0.161, green: 0.475, blue: 1.000), // #2979FF electric blue
            ]
        case 4: // 2028 — botanical
            return [
                Color(red: 0.180, green: 0.490, blue: 0.196), // #2E7D32 forest green
                Color(red: 0.976, green: 0.659, blue: 0.145), // #F9A825 sunny yellow
                Color(red: 0.502, green: 0.796, blue: 0.769), // #80CBC4 mint
            ]
        case 5: // 2029 — midnight
            return [
                Color(red: 0.102, green: 0.137, blue: 0.494), // #1A237E midnight indigo
                Color(red: 0.416, green: 0.106, blue: 0.604), // #6A1BA9 royal purple
                Color(red: 0.051, green: 0.278, blue: 0.631), // #0D47A1 deep blue
            ]
        case 6: // 2030 — flamingo
            return [
                Color(red: 1.000, green: 0.420, blue: 0.420), // #FF6B6B coral pink
                Color(red: 0.914, green: 0.118, blue: 0.388), // #E91E63 rose red
                Color(red: 1.000, green: 0.439, blue: 0.263), // #FF7043 sunset orange
            ]
        case 7: // 2031 — storm
            return [
                Color(red: 0.376, green: 0.490, blue: 0.545), // #607D8B stone gray
                Color(red: 0.361, green: 0.420, blue: 0.753), // #5C6BC0 slate blue
                Color(red: 0.157, green: 0.208, blue: 0.576), // #283593 deep indigo
            ]
        default:
            return [
                Color(red: 1.000, green: 0.498, blue: 0.247),
                Color(red: 0.824, green: 0.184, blue: 0.184),
                Color(red: 1.000, green: 0.420, blue: 0.616),
            ]
        }
    }
}
