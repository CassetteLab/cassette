// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Fixtures

/// `SubsonicAPIError` has no public initialiser, so a real one is produced the only way a real
/// one ever is: by letting SwiftSonic decode a server response. The transport stub supplies it.
private func subsonicErrorJSON(code: Int, message: String) -> Data {
    Data("""
    {"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":\(code),"message":"\(message)"}}}
    """.utf8)
}

@Suite("UserFacingError — mapping SwiftSonic failures")
struct UserFacingErrorMappingTests {

    private func client(_ outcome: StubHTTPTransport.Outcome) -> SwiftSonicClient {
        SwiftSonicClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://stub.example.com")!, username: "u", password: "p"
            ),
            transport: StubHTTPTransport(outcome: outcome),
            retryPolicy: .none
        )
    }

    /// Runs a real request against the stub and maps whatever it throws.
    private func mapped(_ outcome: StubHTTPTransport.Outcome) async throws -> UserFacingError {
        do {
            _ = try await client(outcome).getArtist(id: "ar-1")
            Issue.record("Expected the request to throw")
            return .unexpected
        } catch {
            return UserFacingError.from(error)
        }
    }

    private func mapped(subsonicCode: Int, message: String = "nope") async throws -> UserFacingError {
        try await mapped(.response(data: subsonicErrorJSON(code: subsonicCode, message: message), statusCode: 200))
    }

    // MARK: - Subsonic error codes

    @Test("code 30 — the server says it doesn't implement this")
    func serverMustUpgrade() async throws {
        #expect(try await mapped(subsonicCode: 30) == .notSupportedByServer)
    }

    @Test("code 70 — not found")
    func notFound() async throws {
        #expect(try await mapped(subsonicCode: 70) == .notFound)
    }

    @Test("code 50 — authorised user, forbidden operation, which is not a credentials problem")
    func unauthorizedIsNotAuthenticationFailure() async throws {
        let error = try await mapped(subsonicCode: 50)
        #expect(error == .notAuthorized)
        #expect(error != .authenticationFailed)
    }

    @Test("code 40 — wrong credentials")
    func wrongCredentials() async throws {
        #expect(try await mapped(subsonicCode: 40) == .authenticationFailed)
    }

    @Test("code 60 — trial expired")
    func trialExpired() async throws {
        #expect(try await mapped(subsonicCode: 60) == .trialExpired)
    }

    @Test("code 0 — the server failed on its own side")
    func genericIsAServerError() async throws {
        #expect(try await mapped(subsonicCode: 0) == .serverError)
    }

    @Test("code 10 — a parameter the spec doesn't require means a dialect Cassette doesn't speak")
    func missingParameterIsIncompatible() async throws {
        #expect(try await mapped(subsonicCode: 10) == .incompatibleServer)
    }

    // MARK: - Transport-level failures

    @Test("200 OK that isn't Subsonic JSON — a partial implementation answering something else")
    func undecodableBodyIsIncompatible() async throws {
        let html = Data("<!DOCTYPE html><html><body>Not found</body></html>".utf8)
        #expect(try await mapped(.response(data: html, statusCode: 200)) == .incompatibleServer)
    }

    @Test("404 and 501 — the endpoint isn't there")
    func missingEndpointIsUnsupported() async throws {
        let empty = Data()
        #expect(try await mapped(.response(data: empty, statusCode: 404)) == .notSupportedByServer)
        #expect(try await mapped(.response(data: empty, statusCode: 501)) == .notSupportedByServer)
    }

    @Test("5xx — the server's own problem")
    func serverSideStatusIsServerError() async throws {
        #expect(try await mapped(.response(data: Data(), statusCode: 500)) == .serverError)
        #expect(try await mapped(.response(data: Data(), statusCode: 502)) == .serverError)
    }

    @Test("401 and 403 — credentials")
    func authStatusCodes() async throws {
        #expect(try await mapped(.response(data: Data(), statusCode: 401)) == .authenticationFailed)
        #expect(try await mapped(.response(data: Data(), statusCode: 403)) == .authenticationFailed)
    }

    @Test("no connection is still reported as no connection, not as a server fault")
    func networkErrorsKeepTheirMeaning() async throws {
        #expect(try await mapped(.urlError(.notConnectedToInternet)) == .noNetwork)
        #expect(try await mapped(.urlError(.timedOut)) == .serverUnreachable)
    }

    // MARK: - Retry

    @Test("Retry is not offered for an answer the server has already settled")
    func settledAnswersAreNotRetryable() async throws {
        for code in [30, 70, 50, 40, 60, 10] {
            let error = try await mapped(subsonicCode: code)
            #expect(error.isRetryable == false, "code \(code) offered a Retry that cannot work")
        }
        #expect(try await mapped(.response(data: Data("x".utf8), statusCode: 200)).isRetryable == false)
    }

    @Test("Retry stays available when another attempt could plausibly succeed")
    func transientFailuresAreRetryable() async throws {
        #expect(try await mapped(.urlError(.notConnectedToInternet)).isRetryable)
        #expect(try await mapped(.urlError(.timedOut)).isRetryable)
        #expect(try await mapped(.response(data: Data(), statusCode: 500)).isRetryable)
        #expect(try await mapped(subsonicCode: 0).isRetryable)
    }

    // MARK: - Regressions

    @Test("a Subsonic failure no longer collapses into the empty 'Something went wrong'")
    func typedFailuresAreNoLongerUnexpected() async throws {
        // This is the whole point: every one of these used to reach the user as .unexpected,
        // beside a Retry button that replayed the same failing request.
        for code in [0, 10, 20, 30, 40, 50, 60, 70] {
            #expect(try await mapped(subsonicCode: code) != .unexpected, "code \(code) still unexpected")
        }
    }

    @Test("every case says something, and only .unexpected has nothing to suggest")
    func messagesExist() {
        let all: [UserFacingError] = [
            .noNetwork, .serverUnreachable, .authenticationFailed, .contentUnavailableOffline,
            .downloadFailed, .playbackFailed, .syncFailed, .notSupportedByServer, .notFound,
            .notAuthorized, .trialExpired, .incompatibleServer, .rateLimited, .serverError,
            .insecureRedirect, .unexpected
        ]
        for error in all {
            #expect(error.errorDescription?.isEmpty == false, "\(error.id) has no message")
            #expect(error.displayMessage.isEmpty == false)
        }
        #expect(Set(all.map(\.id)).count == all.count, "two cases share an id")
    }
}
