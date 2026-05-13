import SwiftUI

// MARK: - Cassette Design Tokens v1.8.1
// Rebrand: Electric Violet (#6C47F5) — replaces orange (#FF7F3F)
// All colors are adaptive (light/dark) via Asset Catalog Color Sets.
// Asset Catalog entries must be created alongside this file (see spec below).

public enum CassetteColors {
    
    // MARK: — Accent
    /// Primary brand color. CTA, active icons, progress bars, play button.
    /// Light: #6C47F5 — Dark: #8060F7 (slightly lighter for contrast on dark bg)
    public static let accent = Color("CassetteAccent")
    
    /// Tinted background for badges, pills, active states.
    /// Light: #EDE9FE — Dark: #221E38
    public static let accentBackground = Color("CassetteAccentBackground")
    
    /// Text/icon color on top of accentBackground.
    /// Light: #4C28D4 — Dark: #9F86FA
    public static let accentForeground = Color("CassetteAccentForeground")
    
    // MARK: — Backgrounds
    /// App-level background. Subtly violet-tinted near-white / deep violet-black.
    /// Light: #F6F4FF — Dark: #0F0D1A
    public static let backgroundPrimary = Color("CassetteBackgroundPrimary")
    
    /// Cards, list rows, bottom sheets, grouped table backgrounds.
    /// Light: #EDEAFF — Dark: #1A1728
    public static let backgroundSecondary = Color("CassetteBackgroundSecondary")
    
    /// Elevated content: modals, popovers, context menus.
    /// Light: #FFFFFF — Dark: #231F35
    public static let backgroundTertiary = Color("CassetteBackgroundTertiary")
    
    // MARK: — Text
    /// Primary content: titles, song names, main body text.
    /// Light: #1A1520 — Dark: #F0EEF8
    public static let textPrimary = Color("CassetteTextPrimary")
    
    /// Supporting content: artist names, subtitles, descriptions.
    /// Light: #6B5F8A — Dark: #8C7DB8
    public static let textSecondary = Color("CassetteTextSecondary")
    
    /// De-emphasized content: durations, placeholders, hints, timestamps.
    /// Light: #9B8EBF — Dark: #5E5080
    public static let textTertiary = Color("CassetteTextTertiary")
    
    // MARK: — Structure
    /// List separators, dividers.
    /// Light: violet @ 12% opacity — Dark: violet @ 15% opacity
    public static let separator = Color("CassetteSeparator")
    
    /// Card borders, input outlines.
    /// Light: violet @ 18% opacity — Dark: violet @ 22% opacity
    public static let border = Color("CassetteBorder")
    
    // MARK: — Violet Ramp (raw stops, light-mode only — use for gradients, artwork tints, etc.)
    public enum Violet {
        public static let v50  = Color(hex: "#F0ECFF")
        public static let v100 = Color(hex: "#DDD5FE")
        public static let v200 = Color(hex: "#C0B0FC")
        public static let v300 = Color(hex: "#9F86FA")
        public static let v400 = Color(hex: "#8060F7")
        public static let v500 = Color(hex: "#6C47F5") // base accent
        public static let v600 = Color(hex: "#5530D4")
        public static let v700 = Color(hex: "#3F1FAF")
        public static let v800 = Color(hex: "#2D1480")
        public static let v900 = Color(hex: "#1B0A52")
    }
}

// MARK: - Color(hex:) helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/*
 ┌─────────────────────────────────────────────────────────────────────────┐
 │  ASSET CATALOG SPEC — Colors.xcassets                                   │
 │  Create one Color Set per token. Set "Appearances" to "Any, Dark".      │
 ├──────────────────────────────────┬──────────────────┬───────────────────┤
 │  Color Set Name                  │  Light (Any)     │  Dark             │
 ├──────────────────────────────────┼──────────────────┼───────────────────┤
 │  CassetteAccent                  │  #6C47F5         │  #8060F7          │
 │  CassetteAccentBackground        │  #EDE9FE         │  #221E38          │
 │  CassetteAccentForeground        │  #4C28D4         │  #9F86FA          │
 │  CassetteBackgroundPrimary       │  #F6F4FF         │  #0F0D1A          │
 │  CassetteBackgroundSecondary     │  #EDEAFF         │  #1A1728          │
 │  CassetteBackgroundTertiary      │  #FFFFFF         │  #231F35          │
 │  CassetteTextPrimary             │  #1A1520         │  #F0EEF8          │
 │  CassetteTextSecondary           │  #6B5F8A         │  #8C7DB8          │
 │  CassetteTextTertiary            │  #9B8EBF         │  #5E5080          │
 │  CassetteSeparator               │  #6C47F5 @ 12%   │  #8060F7 @ 15%    │
 │  CassetteBorder                  │  #6C47F5 @ 18%   │  #8060F7 @ 22%    │
 └──────────────────────────────────┴──────────────────┴───────────────────┘
 
 NOTE — CassetteAccent (Asset Catalog) must also be set as the app's
 global tint / accentColor in the root App or WindowGroup, and declared
 in Assets.xcassets as the "AccentColor" entry so system components
 (toggles, sliders, links) inherit the brand color automatically:
 
 WindowGroup { ... }
 .tint(CassetteColors.accent)
 
 Replace all references to the old orange token (previously #FF7F3F) with
 the new tokens. Search codebase for:
 — Color("CassetteOrange") or similar legacy names
 — Color(hex: "#FF7F3F") or hardcoded orange literals
 — Any gradient stops referencing the old orange
 */
