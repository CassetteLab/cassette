// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import AVFoundation
import MediaPlayer
#endif

/// Custom volume slider visually identical to the scrubber in FullPlayerView.
/// Uses ProgressSlider bound to AVAudioSession.outputVolume via KVO.
/// A hidden MPVolumeView is kept off-screen to write the system volume —
/// it is the only officially-sanctioned iOS mechanism for doing so.
struct SystemVolumeView: View {
    var contentColor: Color = .white

    #if os(iOS)
    @State private var observer = SystemVolumeObserver()

    var body: some View {
        let vol = observer.volume
        ProgressSlider(
            value: Binding(
                get: { TimeInterval(vol) },
                set: { observer.volume = Float(max(0, min(1, $0))) }
            ),
            total: 1.0,
            onEditingChanged: { _ in },
            trackColor: contentColor.opacity(0.2),
            fillColor: contentColor.opacity(0.95)
        )
        .background {
            HiddenVolumeViewRepresentable(volume: vol)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(vol * 100))%")
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}

#if os(iOS)
// MARK: - Volume observer

/// Observes AVAudioSession.outputVolume via KVO so that physical volume buttons
/// and Control Center changes are reflected in the ProgressSlider in real time.
@Observable
@MainActor
private final class SystemVolumeObserver {
    var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var observation: NSKeyValueObservation?

    init() {
        volume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(
            \.outputVolume, options: [.new]
        ) { [weak self] _, change in
            guard let newVolume = change.newValue else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    self?.volume = newVolume
                }
            }
        }
    }

    // NSKeyValueObservation auto-invalidates on dealloc — no deinit needed.
}

// MARK: - Hidden MPVolumeView for writing system volume

/// Passes the current volume value to MPVolumeView's internal UISlider.
/// SwiftUI calls updateUIView whenever the volume Binding changes, which
/// propagates the value to the system via the only available private API.
private struct HiddenVolumeViewRepresentable: UIViewRepresentable {
    let volume: Float

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        guard let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first,
              abs(slider.value - volume) > 0.01 else { return }
        slider.setValue(volume, animated: false)
    }
}
#endif
