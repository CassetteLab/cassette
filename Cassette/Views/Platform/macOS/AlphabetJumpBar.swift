// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct AlphabetJumpBar: View {
    let availableLetters: Set<String>
    let onLetterTap: (String) -> Void

    private static let letters = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "#"
    ]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Self.letters, id: \.self) { letter in
                Button {
                    if availableLetters.contains(letter) {
                        onLetterTap(letter)
                    }
                } label: {
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(
                            availableLetters.contains(letter)
                                ? Color.cassetteAccent
                                : Color.secondary.opacity(0.3)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!availableLetters.contains(letter))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Helpers

/// Returns the uppercased first letter of `name`, or "#" for names starting with a non-letter.
func alphabetFirstLetter(of name: String) -> String {
    guard let first = name.first else { return "#" }
    let upper = String(first).uppercased()
    return upper.first?.isLetter == true ? upper : "#"
}

extension Collection {
    /// Computes the set of first letters present in the collection for a given string key path.
    func availableAlphabetLetters(keyPath: KeyPath<Element, String>) -> Set<String> {
        Set(self.map { alphabetFirstLetter(of: $0[keyPath: keyPath]) })
    }
}

/// Returns the ID of the first item whose key-path value starts with `letter`.
func firstAlphabetItemID<T: Identifiable>(
    forLetter letter: String,
    in items: [T],
    keyPath: KeyPath<T, String>
) -> T.ID? {
    items.first { alphabetFirstLetter(of: $0[keyPath: keyPath]) == letter }?.id
}
#endif
