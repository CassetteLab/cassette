// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import OSLog
@testable import Cassette

@Suite("AudioResponseValidator — accept/reject")
struct AudioResponseValidatorTests {

    private let logger = Logger(subsystem: "app.cassette.tests", category: "AudioResponseValidatorTests")

    // Real-world audio file signatures — none start with '<' or '{'.
    private static let id3Header: [UInt8] = [0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00]
    private static let mp3FrameSync: [UInt8] = [0xFF, 0xFB, 0x90, 0x64, 0x00, 0x0F, 0xF0, 0x00]
    private static let flacMagic: [UInt8] = Array("fLaC".utf8) + [0x00, 0x00, 0x00, 0x22]
    private static let oggMagic: [UInt8] = Array("OggS".utf8) + [0x00, 0x02, 0x00, 0x00]

    /// Writes the bytes to a unique temp file, runs the body, removes the file.
    private func withTempFile<T>(_ bytes: [UInt8], _ body: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-validator-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    /// URLResponse with direct control over mimeType and expectedContentLength
    /// (-1 = unknown, mirroring NSURLResponseUnknownLength).
    private func response(for url: URL, mimeType: String? = nil, expectedLength: Int = -1) -> URLResponse {
        URLResponse(url: url, mimeType: mimeType, expectedContentLength: expectedLength, textEncodingName: nil)
    }

    private func expectRejection(
        bytes: [UInt8],
        mimeType: String? = nil,
        expectedLength: Int = -1,
        check expectedCheck: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try withTempFile(bytes) { url in
            do {
                try AudioResponseValidator.validate(
                    fileAt: url,
                    response: response(for: url, mimeType: mimeType, expectedLength: expectedLength),
                    songId: "test-song",
                    logger: logger
                )
                Issue.record("expected rejection by \(expectedCheck) check, but payload was accepted", sourceLocation: sourceLocation)
            } catch let rejection as AudioResponseRejection {
                #expect(rejection.check == expectedCheck, sourceLocation: sourceLocation)
            }
        }
    }

    private func expectAccepted(
        bytes: [UInt8],
        mimeType: String? = nil,
        expectedLength: Int = -1,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try withTempFile(bytes) { url in
            do {
                try AudioResponseValidator.validate(
                    fileAt: url,
                    response: response(for: url, mimeType: mimeType, expectedLength: expectedLength),
                    songId: "test-song",
                    logger: logger
                )
            } catch let rejection as AudioResponseRejection {
                Issue.record("expected acceptance, but rejected by \(rejection.check) check (\(rejection.detail))", sourceLocation: sourceLocation)
            }
        }
    }

    // MARK: - Subsonic error-as-200 envelopes

    @Test("XML error envelope is rejected by the body sniff")
    func xmlEnvelopeRejected() throws {
        try expectRejection(bytes: Array(#"<?xml version="1.0"?><subsonic-response status="failed"/>"#.utf8), check: "body-sniff")
        try expectRejection(bytes: Array(#"<subsonic-response status="failed"></subsonic-response>"#.utf8), check: "body-sniff")
    }

    @Test("JSON error envelope is rejected by the body sniff")
    func jsonEnvelopeRejected() throws {
        try expectRejection(bytes: Array(#"{"subsonic-response":{"status":"failed"}}"#.utf8), check: "body-sniff")
    }

    @Test("UTF-8 BOM and leading whitespace do not hide an error envelope")
    func bomAndWhitespaceStillRejected() throws {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        try expectRejection(bytes: bom + Array("\n  <?xml version=\"1.0\"?>".utf8), check: "body-sniff")
        try expectRejection(bytes: Array("\r\n\t {\"subsonic-response\":{}}".utf8), check: "body-sniff")
    }

    // MARK: - Valid audio signatures

    @Test("common audio signatures are accepted without declared length or type")
    func audioSignaturesAccepted() throws {
        for magic in [Self.id3Header, Self.mp3FrameSync, Self.flacMagic, Self.oggMagic] {
            try expectAccepted(bytes: magic)
        }
    }

    @Test("valid audio with a missing or generic mimeType is not a false positive")
    func unknownMimeTypeAccepted() throws {
        try expectAccepted(bytes: Self.mp3FrameSync, mimeType: nil)
        try expectAccepted(bytes: Self.mp3FrameSync, mimeType: "application/octet-stream")
        try expectAccepted(bytes: Self.flacMagic, mimeType: "audio/flac")
    }

    // MARK: - Size checks

    @Test("empty body is rejected")
    func emptyBodyRejected() throws {
        try expectRejection(bytes: [], check: "empty-body")
    }

    @Test("declared Content-Length mismatch is rejected, exact match accepted")
    func contentLengthChecked() throws {
        let body = Self.id3Header
        try expectRejection(bytes: body, expectedLength: body.count * 2, check: "content-length")
        try expectRejection(bytes: body, expectedLength: body.count - 1, check: "content-length")
        try expectAccepted(bytes: body, expectedLength: body.count)
    }

    @Test("zero or unknown Content-Length skips the length check")
    func unknownContentLengthSkipsCheck() throws {
        try expectAccepted(bytes: Self.oggMagic, expectedLength: 0)
        try expectAccepted(bytes: Self.oggMagic, expectedLength: -1)
    }

    // MARK: - Declared content type

    @Test("clearly non-audio declared types are rejected")
    func nonAudioMimeTypeRejected() throws {
        // Audio-looking body isolates the content-type check from the body sniff.
        try expectRejection(bytes: Self.mp3FrameSync, mimeType: "application/xml", check: "content-type")
        try expectRejection(bytes: Self.mp3FrameSync, mimeType: "application/json", check: "content-type")
        try expectRejection(bytes: Self.mp3FrameSync, mimeType: "text/plain", check: "content-type")
        try expectRejection(bytes: Self.mp3FrameSync, mimeType: "text/html", check: "content-type")
    }
}
