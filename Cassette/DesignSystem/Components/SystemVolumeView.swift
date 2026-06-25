// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import AVFoundation
import MediaPlayer
#endif

/// Custom volume slider visually identical to the scrubber in FullPlayerView. The slider DISPLAYS the system
/// volume (`AVAudioSession.outputVolume`, observed via KVO). The system volume is WRITTEN — through a hidden
/// `MPVolumeView`, the only sanctioned iOS API — ONLY for a value the user posted via the slider's `set`
/// (`userTarget`), consumed once. A KVO/observation update and the cold-start read NEVER write back, so there
/// is no feedback loop and no clobber. The write value is never animated.
struct SystemVolumeView: View {
    var contentColor: Color = .white

    #if os(iOS)
    @State private var observer = SystemVolumeObserver()

    var body: some View {
        ProgressSlider(
            value: Binding(
                get: { TimeInterval(observer.displayVolume) },
                // Any user-posted value (drag OR the accessibility adjust, both go through this set) moves the
                // display immediately AND schedules the one-shot system write. The KVO never comes through here.
                set: { newValue in
                    let v = Float(max(0, min(1, newValue)))
                    observer.displayVolume = v
                    observer.userTarget = v
                }
            ),
            total: 1.0,
            onEditingChanged: { editing in observer.isEditing = editing },
            trackColor: contentColor.opacity(0.2),
            fillColor: contentColor.opacity(0.95)
        )
        .background {
            HiddenVolumeWriter(observer: observer)
                .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(observer.displayVolume * 100))%")
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}

#if os(iOS)
// MARK: - Volume observer

/// Mirrors `AVAudioSession.outputVolume` into `displayVolume` (KVO) so physical buttons / Control Center move
/// the slider. `displayVolume` drives the slider position; `userTarget` (set ONLY by the slider's `set`) is the
/// value to push to the system. The KVO/init never set `userTarget`, so observation and the cold-start read
/// never write back.
@Observable
@MainActor
private final class SystemVolumeObserver {
    /// Slider position. Updated by the user's input (immediate) and by the KVO (animated, when not dragging).
    var displayVolume: Float = AVAudioSession.sharedInstance().outputVolume
    /// A value the user posted via the slider that must be pushed to the system ONCE. nil = nothing to write.
    var userTarget: Float?
    /// True while the user is dragging — keeps the KVO from yanking the slider position out from under the finger.
    var isEditing = false
    private var observation: NSKeyValueObservation?

    init() {
        displayVolume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(
            \.outputVolume, options: [.new]
        ) { [weak self] _, change in
            guard let newVolume = change.newValue else { return }
            Task { @MainActor [weak self] in
                // The drag drives the value while editing — don't fight it with the observation.
                guard let self, !self.isEditing else { return }
                // Spring is cosmetic on the DISPLAY only; the write value (`userTarget`) is separate + un-animated.
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    self.displayVolume = newVolume
                }
            }
        }
    }

    // NSKeyValueObservation auto-invalidates on dealloc — no deinit needed.
}

// MARK: - Hidden MPVolumeView for writing system volume

/// Pushes a USER-posted `userTarget` to `MPVolumeView`'s internal `UISlider` (the only iOS API to set the
/// system volume) once, then signals it consumed. A KVO/init-driven display change is never routed here, so
/// there is no feedback loop and the cold-start read can't clobber the real volume. The write is never animated.
private struct HiddenVolumeWriter: UIViewRepresentable {
    let observer: SystemVolumeObserver

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        guard let target = observer.userTarget,
              let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        if abs(slider.value - target) > 0.001 {
            slider.setValue(target, animated: false)
        }
        // Consume once — deferred so we don't mutate observable state during the view update; cleared only if no
        // newer value arrived, so a fast drag never drops its last value and a stale target is never re-written.
        Task { @MainActor [observer] in
            if observer.userTarget == target { observer.userTarget = nil }
        }
    }
}
#endif
