// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedPeriodPicker: View {
    @Binding var selectedPeriod: WrappedPeriod
    let availablePeriods: [WrappedPeriod]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CassetteSpacing.xs) {
                ForEach(availablePeriods, id: \.self) { period in
                    let isSelected = period == selectedPeriod
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(shortLabel(for: period))
                            .font(isSelected ? .cassetteCellTitle : .cassetteCaption)
                            .foregroundStyle(isSelected ? Color.cassetteAccentText : .primary)
                            .padding(.horizontal, CassetteSpacing.m)
                            .padding(.vertical, CassetteSpacing.s)
                            .background(isSelected ? Color.cassetteAccent : Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, CassetteSpacing.xs)
        }
        // contentMargins sets scroll insets properly (safe-area aware, trailing pad included)
        .contentMargins(.horizontal, CassetteSpacing.l, for: .scrollContent)
        // Bleed horizontally past the parent's horizontal padding
        .padding(.horizontal, -CassetteSpacing.l)
    }

    private func shortLabel(for period: WrappedPeriod) -> String {
        switch period {
        case .year(let year):
            return "\(year)"
        case .month(_, let month):
            return Calendar.current.shortMonthSymbols[month - 1]
        }
    }
}
