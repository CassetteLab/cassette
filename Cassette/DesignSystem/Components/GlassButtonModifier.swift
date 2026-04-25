// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Applies a circular Liquid Glass effect to a button label.
    /// Apply this to the *label* of a Button (not the Button itself)
    /// so that the parent .buttonStyle(.borderless) gesture fix is preserved.
    func cassetteGlassButton(size: CGFloat = 44, tint: Color? = nil) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
        return self
            .frame(width: size, height: size)
            .glassEffect(glass, in: .circle)
    }

    /// Applies a capsule Liquid Glass effect (for wider controls).
    func cassetteGlassCapsule(tint: Color? = nil) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
        return self.glassEffect(glass, in: .capsule)
    }
}
