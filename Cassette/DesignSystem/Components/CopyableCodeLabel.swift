// Cassette
// Copyright (C) 2026 Mathieu Dubart
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import SwiftUI

/// Displays a short code string that the user can tap to copy to the clipboard.
/// Shows a 1.5 s checkmark-and-accent feedback after a successful copy.
/// Uses SensoryFeedback for haptics — no platform conditionals needed in this file.
struct CopyableCodeLabel: View {
    let code: String

    @State private var isCopied = false
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: CassetteSpacing.xs) {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isCopied ? CassetteColors.accent : CassetteColors.textTertiary)

            if isCopied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(CassetteColors.accent)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
        .animation(.easeInOut(duration: 0.15), value: isCopied)
        .sensoryFeedback(.impact(intensity: 0.5), trigger: isCopied) { _, newValue in newValue }
        .accessibilityLabel("Error code \(code)")
        .accessibilityHint("Double tap to copy")
        .accessibilityAddTraits(.isButton)
        .onDisappear {
            feedbackTask?.cancel()
        }
    }

    private func copyCode() {
        PlatformPasteboard.copy(code)
        feedbackTask?.cancel()
        isCopied = true
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isCopied = false
        }
    }
}

// MARK: - Preview

#Preview("CopyableCodeLabel") {
    CopyableCodeLabel(code: "E-DNS")
        .padding()
}
