// Cassette
// Copyright (C) 2026 Mathieu Dubart
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import Foundation
import SwiftSonic

/// Fine-grained errors from a server connection test (ping + getUser).
nonisolated enum ConnectionTestError: Error, Sendable, Equatable {
    /// The URL string is malformed, missing scheme, or missing host.
    case invalidURL
    /// DNS resolution failed — or iOS Local Network Privacy blocked the lookup.
    case dnsFailure
    /// TCP connection was refused or the network is unreachable.
    case cannotConnect
    /// The connection attempt timed out.
    case timeout
    /// TLS certificate validation failed.
    case certificate
    /// iOS App Transport Security blocked the connection (HTTP on non-ATS-exempt host).
    case atsBlocked
    /// The server rejected credentials (HTTP 401/403 or Subsonic auth error codes).
    case unauthorized
    /// A non-2xx HTTP status code other than 401/403.
    case httpError(statusCode: Int)
    /// The server returned a Subsonic API-level error.
    case subsonicError(code: SubsonicErrorCode, message: String?)
    /// The server responded but is not a Subsonic/OpenSubsonic server.
    case notSubsonicServer
    /// A client-side configuration error prevented building the request.
    case invalidConfiguration
    /// A cross-domain HTTP redirect was blocked to prevent credential leakage.
    case insecureRedirect
    /// An unclassified error — domain and code are preserved for diagnostics.
    case unknown(domain: String, code: Int)
}

// MARK: - Presentation

extension ConnectionTestError {
    var presentation: ConnectionErrorPresentation {
        switch self {
        case .invalidURL:
            return ConnectionErrorPresentation(
                title: "Invalid URL",
                description: "Check the format (e.g. https://music.example.com).",
                technicalCode: "invalid-url"
            )
        case .dnsFailure:
            return ConnectionErrorPresentation(
                title: "Server Not Found",
                description: "The hostname could not be resolved. Check the URL, DNS settings, and local network access in iOS Settings \u{203A} Privacy \u{203A} Local Network.",
                technicalCode: "dns-failure"
            )
        case .cannotConnect:
            return ConnectionErrorPresentation(
                title: "Connection Refused",
                description: "The server is not accepting connections. Check the port and whether your server is running.",
                technicalCode: "cannot-connect"
            )
        case .timeout:
            return ConnectionErrorPresentation(
                title: "Connection Timed Out",
                description: "The server took too long to respond. Check your network and try again.",
                technicalCode: "timeout"
            )
        case .certificate:
            return ConnectionErrorPresentation(
                title: "Certificate Error",
                description: "The server's TLS certificate could not be verified. Check your server's SSL configuration.",
                technicalCode: "certificate-error"
            )
        case .atsBlocked:
            return ConnectionErrorPresentation(
                title: "Connection Blocked",
                description: "iOS blocked the connection — use HTTPS or add an ATS exception in the app configuration.",
                technicalCode: "ats-blocked"
            )
        case .unauthorized:
            return ConnectionErrorPresentation(
                title: "Authentication Failed",
                description: "Incorrect username or password.",
                technicalCode: "unauthorized"
            )
        case .httpError(let statusCode):
            return ConnectionErrorPresentation(
                title: "HTTP Error",
                description: "The server returned an unexpected response.",
                technicalCode: "http-\(statusCode)"
            )
        case .subsonicError(let code, let message):
            return ConnectionErrorPresentation(
                title: "Server Error",
                description: "The server returned an API-level error.",
                technicalCode: "subsonic-\(code.rawValue)" + (message.map { ": \($0)" } ?? "")
            )
        case .notSubsonicServer:
            return ConnectionErrorPresentation(
                title: "Not a Subsonic Server",
                description: "The server did not respond as a Subsonic/Navidrome server. Check the URL.",
                technicalCode: "not-subsonic"
            )
        case .invalidConfiguration:
            return ConnectionErrorPresentation(
                title: "Configuration Error",
                description: "A client configuration error prevented connecting.",
                technicalCode: "invalid-config"
            )
        case .insecureRedirect:
            return ConnectionErrorPresentation(
                title: "Insecure Redirect",
                description: "The server redirected to a different domain. Check your server configuration.",
                technicalCode: "insecure-redirect"
            )
        case .unknown(let domain, let code):
            return ConnectionErrorPresentation(
                title: "Unexpected Error",
                description: "An unexpected error occurred.",
                technicalCode: "\(domain) \(code)"
            )
        }
    }
}

// MARK: - LocalizedError

extension ConnectionTestError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL:        return String(localized: "Invalid server URL.")
        case .dnsFailure:        return String(localized: "DNS resolution failed or local network access denied.")
        case .cannotConnect:     return String(localized: "Cannot connect to server.")
        case .timeout:           return String(localized: "Connection timed out.")
        case .certificate:       return String(localized: "TLS certificate error.")
        case .atsBlocked:        return String(localized: "App Transport Security blocked the connection.")
        case .unauthorized:      return String(localized: "Authentication failed — wrong username or password.")
        case .httpError(let sc): return String(localized: "HTTP \(sc) error.")
        case .subsonicError(let code, let msg):
            return String(localized: "Subsonic error \(code.rawValue)") + (msg.map { ": \($0)" } ?? ".")
        case .notSubsonicServer:      return String(localized: "Not a Subsonic/OpenSubsonic server.")
        case .invalidConfiguration:   return String(localized: "Invalid client configuration.")
        case .insecureRedirect:       return String(localized: "Cross-domain redirect blocked.")
        case .unknown(let domain, let code): return String(localized: "Unexpected error: \(domain) \(code).")
        }
    }
}
