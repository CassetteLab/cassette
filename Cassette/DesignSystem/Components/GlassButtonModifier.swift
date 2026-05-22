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
            let glass: Glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
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
            let glass: Glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
            self.glassEffect(glass, in: .capsule)
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
        }
    }
}
