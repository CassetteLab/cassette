// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// A user-configured external service for looking up releases.
/// The URL template uses `%s` as a placeholder for the search term (artist + album title).
nonisolated struct ExternalReleaseProvider: Sendable, Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var urlTemplate: String

    init(id: UUID = UUID(), name: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
    }

    /// Builds a search URL by encoding `"\(artistName) \(albumTitle)"` and substituting `%s`.
    /// Returns `nil` if encoding fails or the resulting string is not a valid URL.
    func buildURL(artistName: String, albumTitle: String) -> URL? {
        let term = "\(artistName) \(albumTitle)".trimmingCharacters(in: .whitespaces)
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: Self.searchTermEncoding) else {
            return nil
        }
        let urlString = urlTemplate.replacingOccurrences(of: "%s", with: encoded)
        return URL(string: urlString)
    }

    /// Validates a URL template. Returns `.valid` when safe to store.
    static func validate(urlTemplate: String) -> ValidationResult {
        let lower = urlTemplate.trimmingCharacters(in: .whitespaces).lowercased()
        // Security: explicitly block javascript: and any other non-http(s) scheme.
        if lower.hasPrefix("javascript:") { return .invalidScheme }
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return .invalidScheme
        }
        // Exactly one %s placeholder required.
        let placeholderCount = urlTemplate.components(separatedBy: "%s").count - 1
        if placeholderCount == 0 { return .missingPlaceholder }
        if placeholderCount > 1  { return .multiplePlaceholders }
        // Ensure the final URL is parseable with a sample term injected.
        let testString = urlTemplate.replacingOccurrences(of: "%s", with: "test")
        guard URL(string: testString) != nil else { return .malformed }
        return .valid
    }

    /// Validates a provider name: non-empty after trimming and ≤ 50 characters.
    static func validate(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && name.count <= 50
    }

    enum ValidationResult: Equatable {
        case valid
        case invalidScheme
        case missingPlaceholder
        case multiplePlaceholders
        case malformed
    }

    // Derived from urlQueryAllowed but excludes query-string delimiters so they are
    // percent-encoded when they appear inside a search term value (e.g. & → %26, / → %2F).
    private static let searchTermEncoding: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=+/?#%;,")
        return cs
    }()
}
