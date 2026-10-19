// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(iOS)
import UIKit

/// Keeps at most one row of a list open, as the system list does. Optional: rows work without
/// it, they just don't close each other.
@Observable
@MainActor
final class SwipeRevealGroup {
    var openRowID: UUID?
}

/// Swipe-to-reveal for rows that are not in a `List` — `.swipeActions` only works in one.
///
/// Built to read as the system's: the row slides, buttons fill the gap it leaves at full height,
/// the first action of each edge sits outermost, nothing fires on a full swipe, a tap on an open
/// row closes it. The drag is a UIKit pan that only begins when the movement is horizontal, so a
/// vertical drag stays a scroll; and it never begins from the screen's leading edge while the
/// row is closed, where the interactive back swipe lives.
///
/// The actions are also exposed as accessibility actions: a custom gesture is invisible to
/// VoiceOver otherwise.
struct SwipeRevealModifier: ViewModifier {
    let leading: [SongSwipeAction]
    let trailing: [SongSwipeAction]

    @Environment(SwipeRevealGroup.self) private var group: SwipeRevealGroup?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowID = UUID()
    /// Where the row is drawn now, following the finger.
    @State private var offset: CGFloat = 0
    /// Where the row rests between drags: 0, `leadingWidth` or `-trailingWidth`.
    @State private var restingOffset: CGFloat = 0

    static let actionWidth: CGFloat = 74

    private var leadingWidth: CGFloat { CGFloat(leading.count) * Self.actionWidth }
    private var trailingWidth: CGFloat { CGFloat(trailing.count) * Self.actionWidth }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            // While open, a tap on the row closes it instead of reaching the row (which would play).
            .overlay {
                if restingOffset != 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { settle(at: 0) }
                }
            }
            // The buttons fill exactly the gap the row leaves, so a transparent row never shows
            // them through itself.
            .overlay(alignment: .leading) {
                if offset > 0 {
                    actionStrip(leading)
                        .frame(width: offset)
                        .clipped()
                }
            }
            .overlay(alignment: .trailing) {
                if offset < 0 {
                    actionStrip(Array(trailing.reversed()))
                        .frame(width: -offset)
                        .clipped()
                }
            }
            .gesture(SwipeRevealPan(
                isEnabled: !leading.isEmpty || !trailing.isEmpty,
                isOpen: restingOffset != 0,
                onBegan: { group?.openRowID = rowID },
                onChanged: { translation in offset = clampedOffset(restingOffset + translation) },
                onEnded: { translation, velocity in
                    let predicted = restingOffset + translation + velocity * 0.2
                    if predicted > leadingWidth / 2, !leading.isEmpty {
                        settle(at: leadingWidth)
                    } else if predicted < -trailingWidth / 2, !trailing.isEmpty {
                        settle(at: -trailingWidth)
                    } else {
                        settle(at: 0)
                    }
                },
                onCancelled: { settle(at: restingOffset) }
            ))
            .accessibilityActions {
                ForEach(leading + trailing) { action in
                    Button(action.title, action: action.perform)
                }
            }
            .onChange(of: group?.openRowID) { _, openID in
                if openID != rowID, restingOffset != 0 { settle(at: 0) }
            }
            // An action that changes the row (Download disappears once it is tapped) must not
            // leave the row resting on a width that no longer exists.
            .onChange(of: leading.count + trailing.count) {
                if restingOffset != 0 { settle(at: 0) }
            }
    }

    /// Follows the finger up to the open width, then resists, as the system does past the last
    /// button. An edge with no actions does not move at all.
    private func clampedOffset(_ raw: CGFloat) -> CGFloat {
        if raw > 0 {
            guard !leading.isEmpty else { return 0 }
            return raw <= leadingWidth ? raw : leadingWidth + (raw - leadingWidth) * 0.25
        } else {
            guard !trailing.isEmpty else { return 0 }
            return raw >= -trailingWidth ? raw : -trailingWidth + (raw + trailingWidth) * 0.25
        }
    }

    private func settle(at target: CGFloat) {
        restingOffset = target
        if target != 0 { group?.openRowID = rowID }
        if reduceMotion {
            offset = target
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = target }
        }
    }

    private func actionStrip(_ actions: [SongSwipeAction]) -> some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    HapticFeedback.light.trigger()
                    action.perform()
                    settle(at: 0)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(action.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(action.tint)
                }
                .buttonStyle(.plain)
            }
        }
        // The strip is reached by sight and touch; VoiceOver gets the same actions on the row.
        .accessibilityHidden(true)
    }
}

/// Horizontal pan that leaves vertical drags to the scroll view around it.
private struct SwipeRevealPan: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let isOpen: Bool
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    let onCancelled: () -> Void

    /// Width of the strip along the screen's leading edge kept for the back swipe.
    private static let backSwipeEdge: CGFloat = 28

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.parent = self
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation?.x ?? 0
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, context.converter.localVelocity?.x ?? 0)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SwipeRevealPan

        init(parent: SwipeRevealPan) {
            self.parent = parent
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            // A closed row dragged rightwards from the screen edge is a back swipe, not ours.
            // (The app ships no right-to-left language, so leading is left.)
            if !parent.isOpen, velocity.x > 0 {
                let start = pan.location(in: nil).x - pan.translation(in: nil).x
                if start < SwipeRevealPan.backSwipeEdge { return false }
            }
            return true
        }

        /// The enclosing scroll view waits for a horizontal swipe to fail before it scrolls —
        /// the arrangement a table view uses for its own swipe actions. A vertical drag fails
        /// `gestureRecognizerShouldBegin` at once, so scrolling is not held up.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView && otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
#endif
