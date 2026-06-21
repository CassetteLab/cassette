// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// A tappable destination carried by a confirmation toast. Sendable (plain ids only — no
/// PersistentModel crosses actor boundaries), so it travels with the Toast payload freely.
/// The tap is resolved by ToastOverlay, which reuses the existing notification-nav pattern.
enum ToastAction: Equatable, Sendable {
    case navigateToPlaylist(id: String, name: String, coverArtId: String?)
}

@MainActor
@Observable
final class ToastService {

    enum Style {
        case info
        case success
        case error

        var systemImage: String {
            switch self {
            case .info:    "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .error:   "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info:    .blue
            case .success: .green
            case .error:   .red
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        /// Optional secondary line (e.g. the playlist name under "1 song added").
        var subtitle: String? = nil
        let style: Style
        let duration: TimeInterval
        /// Optional cover-art id rendered as the leading thumbnail (Apple-Music pill style).
        /// `nil` falls back to the style icon, so plain confirmations keep their look.
        var coverArtId: String? = nil
        /// Optional tap destination. When set, the pill shows a trailing chevron and a tap dismisses
        /// the toast and navigates (resolved in ToastOverlay). `nil` = non-tappable, no chevron.
        var action: ToastAction? = nil
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, subtitle: String? = nil, style: Style = .info, duration: TimeInterval = 3.0, coverArtId: String? = nil, action: ToastAction? = nil) {
        dismissTask?.cancel()
        current = Toast(message: message, subtitle: subtitle, style: style, duration: duration, coverArtId: coverArtId, action: action)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self?.current = nil
            }
        }
    }

    func showError(_ message: String) {
        show(message, style: .error, duration: 4.0)
    }

    func showSuccess(_ message: String) {
        show(message, style: .success, duration: 2.5)
    }

    /// Confirms that a user action succeeded (e.g. "Added to queue"). Uses the success style
    /// (brief duration). Optionally renders an Apple-Music-style pill: a leading cover thumbnail
    /// (`coverArtId`) and a secondary line (`subtitle`, e.g. the playlist name). Message is the only
    /// required input so existing call sites stay trivial.
    func showConfirmation(_ message: String, subtitle: String? = nil, coverArtId: String? = nil, action: ToastAction? = nil) {
        // Tappable toasts dwell a little longer so there is time to tap before auto-dismiss.
        show(message, subtitle: subtitle, style: .success, duration: action == nil ? 2.5 : 4.0, coverArtId: coverArtId, action: action)
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            current = nil
        }
    }
}
