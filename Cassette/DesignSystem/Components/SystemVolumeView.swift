// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import MediaPlayer
#endif

/// Wraps MPVolumeView to bind the slider directly to the iOS system volume.
/// MPVolumeView is self-contained — it observes and controls system volume without
/// any SwiftUI state binding.
/// On macOS, renders EmptyView (system volume is managed via menu bar / keyboard).
struct SystemVolumeView: View {
    var body: some View {
        #if os(iOS)
        SystemVolumeViewIOS()
            .frame(height: 24)
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
private struct SystemVolumeViewIOS: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        // Hide the built-in route picker — AVRoutePickerView in the bottom toolbar already handles this
        volumeView.showsRouteButton = false
        volumeView.tintColor = UIColor.white.withAlphaComponent(0.9)
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#endif
