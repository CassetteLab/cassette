// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class TrackSwipeInteraction {
    enum Direction: Equatable { case previous, next }

    var offset: CGFloat = 0
    var pageWidth: CGFloat = 0
    var isHorizontalDragActive = false
    private(set) var keepsPauseIcon = false
    private var committing = false

    /// Where a swipe in `direction` would land, or `nil` when the swipe has nowhere to go.
    ///
    /// Pure on purpose: the swipe decides only whether a transition is *possible*. What the
    /// transition does is `skipToNext()` / `skipToPrevious()`, so the rules live in one place.
    static func destinationIndex(
        _ direction: Direction,
        currentIndex: Int,
        queueCount: Int,
        repeatMode: RepeatMode
    ) -> Int? {
        guard queueCount > 1, (0..<queueCount).contains(currentIndex) else { return nil }

        let target = direction == .previous ? currentIndex - 1 : currentIndex + 1
        if (0..<queueCount).contains(target) { return target }
        // Repeat-all wraps in both directions: stopping dead at index 0 reads as a broken
        // gesture, not as a boundary.
        guard repeatMode == .all else { return nil }
        return direction == .next ? 0 : queueCount - 1
    }

    /// The drag past the dead zone, or 0 inside it.
    static func activeTranslation(_ translation: CGFloat, deadZone: CGFloat) -> CGFloat {
        guard abs(translation) > deadZone else { return 0 }
        return translation > 0 ? translation - deadZone : translation + deadZone
    }

    func destination(_ direction: Direction, in playerState: PlayerState) -> (index: Int, song: DisplayableSong)? {
        let queue = playerState.queue
        guard let index = Self.destinationIndex(
            direction,
            currentIndex: playerState.currentIndex,
            queueCount: queue.count,
            repeatMode: playerState.repeatMode
        ) else { return nil }
        return (index, queue[index])
    }

    func changed(
        translation: CGSize,
        playerState: PlayerState,
        playerService: (any PlayerServiceProtocol)?,
        reduceMotion: Bool
    ) {
        guard !committing, pageWidth > 0, abs(translation.width) > abs(translation.height) else { return }
        isHorizontalDragActive = true
        let drag = activeTranslation(translation.width)
        guard drag != 0 else {
            offset = 0
            return
        }
        let direction = direction(for: drag)
        offset = destination(direction, in: playerState) == nil ? drag * 0.12 : drag
        if abs(offset) >= pageWidth * 0.92 {
            commit(direction, playerState: playerState, playerService: playerService, reduceMotion: reduceMotion)
        }
    }

    func ended(
        translation: CGSize,
        predictedTranslation: CGSize,
        playerState: PlayerState,
        playerService: (any PlayerServiceProtocol)?,
        reduceMotion: Bool
    ) {
        defer { isHorizontalDragActive = false }
        guard !committing else { return }
        guard abs(translation.width) > abs(translation.height) else {
            bounceBack(reduceMotion: reduceMotion)
            return
        }
        let drag = activeTranslation(translation.width)
        let direction = direction(for: drag)
        let shouldCommit = abs(drag) >= min(90, pageWidth * 0.30)
            || abs(activeTranslation(predictedTranslation.width)) >= pageWidth * 0.50
        if shouldCommit, destination(direction, in: playerState) != nil {
            commit(direction, playerState: playerState, playerService: playerService, reduceMotion: reduceMotion)
        } else {
            bounceBack(reduceMotion: reduceMotion)
        }
    }

    func skip(
        _ direction: Direction,
        playerState: PlayerState,
        playerService: (any PlayerServiceProtocol)?,
        reduceMotion: Bool
    ) {
        commit(direction, playerState: playerState, playerService: playerService, reduceMotion: reduceMotion)
    }

    func reset() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            offset = 0
            isHorizontalDragActive = false
            committing = false
        }
    }

    func cancel(reduceMotion: Bool) {
        isHorizontalDragActive = false
        bounceBack(reduceMotion: reduceMotion)
    }

    private func commit(
        _ direction: Direction,
        playerState: PlayerState,
        playerService: (any PlayerServiceProtocol)?,
        reduceMotion: Bool
    ) {
        guard !committing,
              destination(direction, in: playerState) != nil,
              let playerService else {
            bounceBack(reduceMotion: reduceMotion)
            return
        }

        committing = true
        keepsPauseIcon = playerState.playbackState == .playing
        HapticFeedback.medium.trigger()
        withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .snappy(duration: 0.22)) {
            offset = direction == .next ? -pageWidth : pageWidth
        }

        let indexBefore = playerState.currentIndex
        Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(150))
            }
            do {
                // The same entry points as the transport buttons, so skip semantics have a single
                // source of truth: end-of-queue handling, the "restart the current track after 3s"
                // rule on previous, and the [TRANSITION] logs all come for free.
                switch direction {
                case .next:     try await playerService.skipToNext()
                case .previous: try await playerService.skipToPrevious()
                }
                keepsPauseIcon = false
                // `skipToPrevious()` restarts the current track rather than moving when the user is
                // more than three seconds in. Nothing moved, so the page should not stay shifted.
                if playerState.currentIndex == indexBefore {
                    committing = false
                    bounceBack(reduceMotion: reduceMotion)
                }
            } catch {
                keepsPauseIcon = false
                guard playerState.currentIndex == indexBefore else { return }
                committing = false
                bounceBack(reduceMotion: reduceMotion)
            }
        }
    }

    private func direction(for translation: CGFloat) -> Direction {
        translation < 0 ? .next : .previous
    }

    private func activeTranslation(_ translation: CGFloat) -> CGFloat {
        Self.activeTranslation(translation, deadZone: CassetteSpacing.xl)
    }

    private func bounceBack(reduceMotion: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.30, dampingFraction: 0.78)) {
            offset = 0
        }
    }
}

#if os(iOS)
extension View {
    @ViewBuilder
    func trackSwipeGesture(
        interaction: TrackSwipeInteraction,
        playerState: PlayerState,
        playerService: (any PlayerServiceProtocol)?,
        reduceMotion: Bool,
        isEnabled: Bool,
        pageWidth: CGFloat? = nil
    ) -> some View {
        if isEnabled {
            gesture(HorizontalTrackPanGesture(
                interaction: interaction,
                playerState: playerState,
                playerService: playerService,
                reduceMotion: reduceMotion,
                pageWidth: pageWidth
            ))
        } else {
            self
        }
    }
}

struct HorizontalTrackPanGesture: UIGestureRecognizerRepresentable {
    let interaction: TrackSwipeInteraction
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    let reduceMotion: Bool
    let pageWidth: CGFloat?

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
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let point = context.converter.localTranslation ?? .zero
        let translation = CGSize(width: point.x, height: point.y)

        switch recognizer.state {
        case .began, .changed:
            if let pageWidth, pageWidth > 0 { interaction.pageWidth = pageWidth }
            interaction.isHorizontalDragActive = true
            interaction.changed(
                translation: translation,
                playerState: playerState,
                playerService: playerService,
                reduceMotion: reduceMotion
            )
        case .ended:
            let velocity = context.converter.localVelocity ?? .zero
            let predicted = CGSize(
                width: translation.width + velocity.x * 0.2,
                height: translation.height + velocity.y * 0.2
            )
            interaction.ended(
                translation: translation,
                predictedTranslation: predicted,
                playerState: playerState,
                playerService: playerService,
                reduceMotion: reduceMotion
            )
        case .cancelled, .failed:
            interaction.cancel(reduceMotion: reduceMotion)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalTrackPanGesture

        init(parent: HorizontalTrackPanGesture) {
            self.parent = parent
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

struct TrackTextEdgeMask: View {
    let blurred: Bool
    let leading: CGFloat
    let trailing: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            edge(strength: leading, isLeading: true)
            Rectangle().fill(blurred ? .clear : .black)
            edge(strength: trailing, isLeading: false)
        }
    }

    private func edge(strength: CGFloat, isLeading: Bool) -> some View {
        let colors: [Color]
        if blurred {
            colors = [.clear, .black.opacity(strength), .clear]
        } else {
            colors = isLeading
                ? [.black.opacity(1 - strength), .black]
                : [.black, .black.opacity(1 - strength)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .frame(width: CassetteSpacing.m)
    }
}

private func edgeMask(blurred: Bool, leading: CGFloat, trailing: CGFloat) -> some View {
    TrackTextEdgeMask(blurred: blurred, leading: leading, trailing: trailing)
}

struct SwipeableTrackMetadata<Title: View, Subtitle: View>: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    let interaction: TrackSwipeInteraction
    private let title: (DisplayableSong?, Bool) -> Title
    private let subtitle: (DisplayableSong?, Bool) -> Subtitle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleWidth: CGFloat = 0
    @State private var subtitleWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0

    private let marqueePointsPerSecond: CGFloat = 30

    init(
        playerState: PlayerState,
        playerService: (any PlayerServiceProtocol)?,
        interaction: TrackSwipeInteraction,
        @ViewBuilder title: @escaping (DisplayableSong?, Bool) -> Title,
        @ViewBuilder subtitle: @escaping (DisplayableSong?, Bool) -> Subtitle
    ) {
        self.playerState = playerState
        self.playerService = playerService
        self.interaction = interaction
        self.title = title
        self.subtitle = subtitle
    }

    private var currentSong: DisplayableSong? {
        guard playerState.queue.indices.contains(playerState.currentIndex) else {
            return playerState.currentTrack
        }
        return playerState.queue[playerState.currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            swipeableRow(
                previous: title(previousSong, false),
                current: title(currentSong, true),
                next: title(nextSong, false),
                contentWidth: $titleWidth,
                staysFixed: false
            )
            swipeableRow(
                previous: subtitle(previousSong, false),
                current: subtitle(currentSong, true),
                next: subtitle(nextSong, false),
                contentWidth: $subtitleWidth,
                staysFixed: subtitleStaysFixed
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .trackSwipeGesture(
            interaction: interaction,
            playerState: playerState,
            playerService: playerService,
            reduceMotion: reduceMotion,
            isEnabled: true,
            pageWidth: viewportWidth > 0 ? pageStride : nil
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            viewportWidth = width
            interaction.pageWidth = width + CassetteSpacing.xxxl
        }
        .task(id: MarqueeAnimationKey(
            songID: currentSong?.id,
            titleWidth: titleWidth,
            subtitleWidth: subtitleWidth,
            viewportWidth: viewportWidth,
            reduceMotion: reduceMotion
        )) {
            await animateMarquee()
        }
        .accessibilityAction(named: "Previous Track") {
            interaction.skip(.previous, playerState: playerState, playerService: playerService, reduceMotion: reduceMotion)
        }
        .accessibilityAction(named: "Next Track") {
            interaction.skip(.next, playerState: playerState, playerService: playerService, reduceMotion: reduceMotion)
        }
        .onChange(of: playerState.currentIndex) { _, _ in interaction.reset() }
        .onChange(of: playerState.currentTrack?.id) { _, _ in interaction.reset() }
    }

    private var previousSong: DisplayableSong? {
        interaction.destination(.previous, in: playerState)?.song
    }

    private var nextSong: DisplayableSong? {
        interaction.destination(.next, in: playerState)?.song
    }

    private var pageStride: CGFloat {
        viewportWidth + CassetteSpacing.xxxl
    }

    private var sharedMarqueeStride: CGFloat {
        max(titleWidth, subtitleWidth) + CassetteSpacing.xxxl
    }

    private var hasMarqueeOverflow: Bool {
        viewportWidth > 0 && (titleWidth > viewportWidth || subtitleWidth > viewportWidth)
    }

    private var subtitleStaysFixed: Bool {
        guard interaction.offset != 0, let currentSong else { return false }
        let destination = interaction.offset < 0 ? nextSong : previousSong
        guard let destination else { return false }
        return SubtitleIdentity(song: currentSong) == SubtitleIdentity(song: destination)
    }

    @ViewBuilder
    private func swipeableRow<Row: View>(
        previous: Row,
        current: Row,
        next: Row,
        contentWidth: Binding<CGFloat>,
        staysFixed: Bool
    ) -> some View {
        if staysFixed {
            marqueeContent(current, contentWidth: contentWidth)
        } else {
            current.hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let pages = HStack(spacing: CassetteSpacing.xxxl) {
                            page(fixed(previous), width: width)
                                .accessibilityHidden(true)
                            page(marqueeContent(current, contentWidth: contentWidth), width: width)
                            page(fixed(next), width: width)
                                .accessibilityHidden(true)
                        }
                        let carousel = pages
                            .offset(x: -(width + CassetteSpacing.xxxl) + interaction.offset)
                            .frame(width: width, height: geometry.size.height, alignment: .leading)
                            .clipped()
                        let effectStrength = min(abs(interaction.offset) / CassetteSpacing.s, 1)

                        ZStack {
                            carousel.mask(edgeMask(blurred: false, leading: effectStrength, trailing: 1))
                            carousel
                                .blur(radius: CassetteSpacing.xs)
                                .mask(edgeMask(blurred: true, leading: effectStrength, trailing: 1))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .clipped()
        }
    }

    private func marqueeContent<Row: View>(_ row: Row, contentWidth: Binding<CGFloat>) -> some View {
        row.hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let width = contentWidth.wrappedValue
                    let overflows = width > geometry.size.width
                    let rowOffset = overflows ? marqueeOffset : 0
                    let leadingStrength = overflows ? min(abs(marqueeOffset) / CassetteSpacing.m, 1) : 0
                    let movingContent = ZStack(alignment: .leading) {
                        fixed(row)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                                contentWidth.wrappedValue = $0
                            }
                            .offset(x: rowOffset)
                        if overflows {
                            fixed(row)
                                .offset(x: rowOffset + sharedMarqueeStride)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                    let viewport = movingContent.clipped()

                    ZStack(alignment: .leading) {
                        viewport.mask(edgeMask(blurred: false, leading: leadingStrength, trailing: 0))
                        viewport
                            .blur(radius: CassetteSpacing.xs)
                            .mask(edgeMask(blurred: true, leading: leadingStrength, trailing: 0))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                    .clipped()
                }
            }
    }

    private func page<Content: View>(_ content: Content, width: CGFloat) -> some View {
        let boundedContent = content
            .frame(width: width, alignment: .leading)
            .clipped()

        return ZStack(alignment: .leading) {
            boundedContent.mask(edgeMask(blurred: false, leading: 0, trailing: 1))
            boundedContent
                .blur(radius: CassetteSpacing.xs)
                .mask(edgeMask(blurred: true, leading: 0, trailing: 1))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: width, alignment: .leading)
    }

    private func fixed<Content: View>(_ content: Content) -> some View {
        content.fixedSize(horizontal: true, vertical: false)
    }

    private func animateMarquee() async {
        resetMarqueeOffset()
        guard hasMarqueeOverflow, !reduceMotion else { return }

        do {
            try await Task.sleep(for: .seconds(1.2))
            while !Task.isCancelled {
                let duration = Double(sharedMarqueeStride / marqueePointsPerSecond)
                withAnimation(.linear(duration: duration)) { marqueeOffset = -sharedMarqueeStride }
                try await Task.sleep(for: .seconds(duration))
                resetMarqueeOffset()
                try await Task.sleep(for: .seconds(1))
            }
        } catch { }
    }

    private func resetMarqueeOffset() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { marqueeOffset = 0 }
    }

    private struct SubtitleIdentity: Equatable {
        let artist: String?
        let audioFormat: String?

        init(song: DisplayableSong) {
            artist = song.artist
            audioFormat = song.audioFormat
        }
    }

    private struct MarqueeAnimationKey: Equatable {
        let songID: String?
        let titleWidth: CGFloat
        let subtitleWidth: CGFloat
        let viewportWidth: CGFloat
        let reduceMotion: Bool
    }
}
#endif
