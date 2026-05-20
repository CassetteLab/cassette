// Cassette
// Copyright (C) 2026 Mathieu Dubart
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import SwiftUI
import SwiftSonic

/// Displays a structured connection error: icon, title, description, and a
/// tappable technical code the user can copy for support purposes.
/// Padding is the call-site's responsibility; this view has none internally.
struct ConnectionErrorView: View {
    let error: ConnectionTestError

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(CassetteColors.accent)
                .padding(.bottom, CassetteSpacing.s)

            Text(error.presentation.title)
                .font(.headline)
                .foregroundStyle(CassetteColors.textPrimary)
                .padding(.bottom, CassetteSpacing.xs)

            Text(error.presentation.description)
                .font(.subheadline)
                .foregroundStyle(CassetteColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, CassetteSpacing.m)

            CopyableCodeLabel(code: error.presentation.technicalCode)
        }
    }

    private var iconName: String {
        if case .unauthorized = error { return "lock.fill" }
        return "exclamationmark.triangle.fill"
    }
}

// MARK: - Previews

#Preview("DNS failure") {
    ConnectionErrorView(error: .dnsFailure)
        .padding()
}

#Preview("Unauthorized") {
    ConnectionErrorView(error: .unauthorized)
        .padding()
}

#Preview("Subsonic error — not found") {
    ConnectionErrorView(error: .subsonicError(code: .notFound, message: nil))
        .padding()
}

#Preview("Unknown error") {
    ConnectionErrorView(error: .unknown(domain: "NSURLErrorDomain", code: -999))
        .padding()
}
