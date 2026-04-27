// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
        let style: Style
        let duration: TimeInterval
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .info, duration: TimeInterval = 3.0) {
        dismissTask?.cancel()
        current = Toast(message: message, style: style, duration: duration)
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

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            current = nil
        }
    }
}
