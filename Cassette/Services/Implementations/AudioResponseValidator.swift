// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// Thrown when a downloaded payload is rejected before being committed as local audio.
nonisolated struct AudioResponseRejection: Error, Sendable, CustomStringConvertible {
    let check: String
    let detail: String
    var description: String { "audio response rejected by \(check) check (\(detail))" }
}

/// Validates a downloaded audio payload before it is committed to the cache or the
/// permanent downloads store. Subsonic servers can answer HTTP 200 with an XML/JSON
/// error envelope, and close-delimited transcoded streams can truncate silently on
/// poor connections — both would otherwise be saved as "valid" local audio and play
/// as silence. Validation reads only file attributes and a small prefix, never the
/// whole payload.
nonisolated enum AudioResponseValidator {

    /// Validates the downloaded temp file against the HTTP response that produced it.
    /// - Throws: `AudioResponseRejection` when the payload is empty, truncated, or not audio.
    static func validate(fileAt url: URL, response: URLResponse, songId: String, logger: Logger) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        if size == 0 {
            logger.warning("[VALIDATE] '\(songId, privacy: .public)' rejected — empty body")
            throw AudioResponseRejection(check: "empty-body", detail: "0 bytes")
        }

        let expected = response.expectedContentLength
        if expected > 0 && size != expected {
            logger.warning("[VALIDATE] '\(songId, privacy: .public)' rejected — truncated body (expected \(expected) bytes, got \(size))")
            throw AudioResponseRejection(check: "content-length", detail: "expected \(expected) bytes, got \(size)")
        }

        // Subsonic error-as-200: the body is an XML/JSON envelope, not audio. Sniffing
        // the first meaningful byte is content-type-independent — proxies (Cloudflare)
        // can mangle the declared mimeType.
        if let first = try firstMeaningfulByte(of: url),
           first == UInt8(ascii: "<") || first == UInt8(ascii: "{") {
            logger.warning("[VALIDATE] '\(songId, privacy: .public)' rejected — structured text body (XML/JSON error envelope)")
            throw AudioResponseRejection(check: "body-sniff", detail: "body starts with structured text marker 0x\(String(first, radix: 16))")
        }

        // Secondary signal: trust a clearly non-audio declared type. A missing or
        // unknown mimeType is NOT a rejection — valid audio behind a proxy can lack it.
        if let mime = response.mimeType?.lowercased(),
           mime.hasPrefix("text/") || mime == "application/xml" || mime == "application/json" {
            logger.warning("[VALIDATE] '\(songId, privacy: .public)' rejected — non-audio content type \(mime, privacy: .public)")
            throw AudioResponseRejection(check: "content-type", detail: mime)
        }
    }

    /// First byte of the payload after skipping a UTF-8 BOM and ASCII whitespace,
    /// reading at most 512 bytes from disk.
    private static func firstMeaningfulByte(of url: URL) throws -> UInt8? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var prefix = try handle.read(upToCount: 512) ?? Data()
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            prefix = prefix.dropFirst(3)
        }
        let whitespace: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
        return prefix.first { !whitespace.contains($0) }
    }
}
