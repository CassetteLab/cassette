// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Applies a circular Liquid Glass effect to a button label.
    /// Apply this to the *label* of a Button (not the Button itself)
    /// so that the parent .buttonStyle(.borderless) gesture fix is preserved.
    @ViewBuilder
    func cassetteGlassButton(size: CGFloat = 44, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // .interactive() removed — causes infinite StyleModifier recursion during
            // NavigationStack transitions on macOS 26.5 (54k-frame stack overflow).
            // Re-evaluate when Apple fixes Glass StyleModifier composition (rdar://TODO).
            let glass: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self
                .frame(width: size, height: size)
                .glassEffect(glass, in: .circle)
        } else {
            self
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
        }
    }

    /// Applies a capsule Liquid Glass effect (for wider controls).
    @ViewBuilder
    func cassetteGlassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // .interactive() removed — same crash risk as cassetteGlassButton.
            let glass: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self.glassEffect(glass, in: .capsule)
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
        }
    }

    /// Over-cover HERO round button: TRANSPARENT — no surface/fill. Just the tap area + a soft shadow so the
    /// glyph stays legible on a busy cover without a backing (the Apple-Music trick). The caller colors the
    /// glyph for direct contrast on the cover (the over-cover title color). Pair with `.buttonStyle(.plain)`
    /// to drop the native iOS 26 toolbar glass.
    func cassetteHeroButton(size: CGFloat = 44) -> some View {
        self
            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
            .frame(width: size, height: size)
            .contentShape(Circle())
    }
}
