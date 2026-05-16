// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedRecapMonthCard: View {
    let period: WrappedPeriod

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var year: Int {
        switch period {
        case .month(let y, _): return y
        case .year(let y): return y
        }
    }

    private var title: String {
        switch period {
        case .month(let y, let m):
            var components = DateComponents()
            components.year = y
            components.month = m
            let date = Calendar.current.date(from: components) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: date)
        case .year(let y):
            return String(y)
        }
    }

    private var subtitle: String {
        switch period {
        case .month(let y, _): return String(y)
        case .year: return "Year in Review"
        }
    }

    var body: some View {
        NavigationLink {
            WrappedView(initialPeriod: period)
        } label: {
            MeshGradientBackground(palette: WrappedYearPalette.colors(for: year), animated: !reduceMotion)
                .frame(width: 140, height: 160)
                .overlay { cardOverlay }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CassetteSpacing.s)
    }
}
