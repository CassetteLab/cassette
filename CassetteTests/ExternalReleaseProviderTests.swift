// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Validation tests

@Suite("ExternalReleaseProvider — validate(urlTemplate:)")
struct ExternalReleaseProviderValidationTests {

    @Test("valid https template returns .valid")
    func validHTTPS() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "https://bandcamp.com/search?q=%s") == .valid)
    }

    @Test("valid http template returns .valid")
    func validHTTP() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "http://example.com/search?q=%s") == .valid)
    }

    @Test("missing %s placeholder returns .missingPlaceholder")
    func missingPlaceholder() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "https://bandcamp.com/search?q=artist") == .missingPlaceholder)
    }

    @Test("two %s placeholders returns .multiplePlaceholders")
    func multiplePlaceholders() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "https://example.com?a=%s&b=%s") == .multiplePlaceholders)
    }

    @Test("javascript: scheme returns .invalidScheme — critical security test")
    func javascriptSchemeCritical() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "javascript:alert(1)%s") == .invalidScheme)
    }

    @Test("JavaScript: mixed case also returns .invalidScheme")
    func javascriptMixedCase() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "JavaScript:alert(1)%s") == .invalidScheme)
    }

    @Test("ftp:// scheme returns .invalidScheme")
    func ftpScheme() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "ftp://example.com/search?q=%s") == .invalidScheme)
    }

    @Test("malformed URL returns .malformed")
    func malformedURL() {
        #expect(ExternalReleaseProvider.validate(urlTemplate: "https://[invalid]/q=%s") == .malformed)
    }
}

@Suite("ExternalReleaseProvider — validate(name:)")
struct ExternalReleaseProviderNameValidationTests {

    @Test("valid name returns true")
    func validName() {
        #expect(ExternalReleaseProvider.validate(name: "Bandcamp") == true)
    }

    @Test("empty string returns false")
    func emptyName() {
        #expect(ExternalReleaseProvider.validate(name: "") == false)
    }

    @Test("whitespace-only string returns false")
    func whitespaceName() {
        #expect(ExternalReleaseProvider.validate(name: "   ") == false)
    }

    @Test("name of exactly 50 chars returns true")
    func exactly50Chars() {
        #expect(ExternalReleaseProvider.validate(name: String(repeating: "a", count: 50)) == true)
    }

    @Test("name of 51 chars returns false")
    func over50Chars() {
        #expect(ExternalReleaseProvider.validate(name: String(repeating: "a", count: 51)) == false)
    }
}

// MARK: - buildURL tests

@Suite("ExternalReleaseProvider — buildURL")
struct ExternalReleaseProviderBuildURLTests {

    private let provider = ExternalReleaseProvider(
        name: "Test",
        urlTemplate: "https://example.com/search?q=%s"
    )

    @Test("simple artist + album produces correct URL")
    func simpleArtistAlbum() {
        let url = provider.buildURL(artistName: "Daft Punk", albumTitle: "Discovery")
        #expect(url?.absoluteString == "https://example.com/search?q=Daft%20Punk%20Discovery")
    }

    @Test("ampersand in artist name is encoded as %26")
    func ampersandEncoded() {
        let url = provider.buildURL(artistName: "Simon & Garfunkel", albumTitle: "Bridge")
        let str = url?.absoluteString ?? ""
        #expect(str.contains("%26"), "Expected %26 for & character")
        #expect(!str.contains("=Simon & Garfunkel"), "Raw & must not appear in query value")
    }

    @Test("apostrophe in artist name produces valid URL")
    func apostropheProducesValidURL() {
        let url = provider.buildURL(artistName: "Guns N' Roses", albumTitle: "Appetite for Destruction")
        #expect(url != nil)
    }

    @Test("accented characters are percent-encoded")
    func accentEncoded() {
        let url = provider.buildURL(artistName: "Stromaé", albumTitle: "Racine Carrée")
        let str = url?.absoluteString ?? ""
        // é = %C3%A9 in UTF-8
        #expect(str.contains("%C3%A9"), "Accented 'é' must be percent-encoded")
    }

    @Test("slash in artist name is encoded as %2F")
    func slashEncoded() {
        let url = provider.buildURL(artistName: "AC/DC", albumTitle: "Back in Black")
        let str = url?.absoluteString ?? ""
        #expect(str.contains("%2F"), "Slash must be encoded as %2F")
        #expect(!str.contains("AC/DC"), "Raw slash must not appear in query value")
    }

    @Test("leading and trailing whitespace is trimmed from search term")
    func whitespaceTrimmed() {
        let urlWithSpaces = provider.buildURL(artistName: "  Daft Punk  ", albumTitle: "  Discovery  ")
        let urlClean = provider.buildURL(artistName: "Daft Punk", albumTitle: "Discovery")
        // Both should produce the same encoded term
        #expect(urlWithSpaces?.absoluteString == urlClean?.absoluteString)
    }
}
