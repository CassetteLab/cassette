// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Applies a zoom navigation transition (iOS 18+). No-op on macOS where the API is unavailable.
    @ViewBuilder
    func cassetteZoomTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        #if os(iOS)
        if let sourceID, let namespace {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Marks this view as the matched transition source for a zoom navigation (iOS 18+).
    /// No-op when either parameter is nil or on macOS.
    @ViewBuilder
    func cassetteMatchedTransitionSource(id: String?, in namespace: Namespace.ID?) -> some View {
        #if os(iOS)
        if let id, let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
