// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

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
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, subtitle: String? = nil, style: Style = .info, duration: TimeInterval = 3.0, coverArtId: String? = nil) {
        dismissTask?.cancel()
        current = Toast(message: message, subtitle: subtitle, style: style, duration: duration, coverArtId: coverArtId)
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
    func showConfirmation(_ message: String, subtitle: String? = nil, coverArtId: String? = nil) {
        show(message, subtitle: subtitle, style: .success, duration: 2.5, coverArtId: coverArtId)
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            current = nil
        }
    }
}
