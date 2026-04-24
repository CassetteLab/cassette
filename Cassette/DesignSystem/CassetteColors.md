# Cassette Color System

## Palette overview

| Token | Light | Dark | WCAG | Permitted uses |
|-------|-------|------|------|----------------|
| `cassetteAccent` | `#D96B1F` | `#FF8C4B` | ~3.5:1 on white (large text AA) | Play button, scrubber progress, active shuffle/repeat toggle, tappable artist name |
| `cassetteAccentSecondary` | `#F5A06B` | `#FFB980` | decorative only | Gradient stop alongside `cassetteAccent`, tinted backgrounds |
| `cassetteAccentText` | white | white | — | Text/icons placed on an accent-filled surface |
| `cassetteCoverShadow` | rgba(0,0,0,0.15) | transparent | — | Shadow on cover art in light mode |
| `cassetteCoverBorder` | — | white 8% | — | Thin border on cover art in dark mode (replaces invisible shadow) |

## Rules

1. **`cassetteAccent` is strictly for primary interactive elements.** It must never appear on body copy, captions, metadata labels, section headers, or timestamps.
2. **Accent contrast is AA for large text only** (~3.5:1 against white). All text using the accent color must be ≥ 18pt regular or ≥ 14pt bold.
3. **Text and backgrounds use SwiftUI semantic colors** (`Color.primary`, `Color.secondary`, `Color(.systemBackground)`, etc.). Do not add custom colors for text or backgrounds unless there is a concrete, justified need.
4. **Do not add new custom colors without updating this document.**

## Dark mode behavior

- Shadows on cover art are invisible against dark backgrounds. Use `.cassetteCoverStyle()` on all cover art views — it automatically switches to a 1pt border in dark mode.
- `cassetteAccentSecondary` is slightly warmer in dark mode to maintain perceived brightness.

## Adding a new color

1. Add the color set to `Assets.xcassets` with both Any and Dark Appearance variants.
2. Add a usage rule to this table.
3. Do not add a manual `Color` extension — Xcode generates `Color.<assetName>` automatically.
