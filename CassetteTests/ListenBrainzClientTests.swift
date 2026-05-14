// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Mock transport

private struct MockTransport: ListenBrainzTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

/// Transport that always fails with URLError. If called when not expected, tests catch it.
private struct FailingTransport: ListenBrainzTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.unknown)
    }
}

// MARK: - Helpers

private func makeClient(_ handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) -> ListenBrainzClient {
    ListenBrainzClient(transport: MockTransport(handler: handler))
}

private func response(status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.listenbrainz.org/1/user/test")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

// MARK: - validateUsername tests

@Suite("ListenBrainzClient — validateUsername")
struct ListenBrainzClientTests {

    @Test("valid username, 200 + count > 0 returns true")
    func happyPathWithCount() async throws {
        let body = Data(#"{"payload":{"count":1234}}"#.utf8)
        let client = makeClient { _ in (body, response(status: 200)) }
        let result = try await client.validateUsername("testuser")
        #expect(result == true)
    }

    @Test("valid username, 200 + count = 0 still returns true (user exists, never listened)")
    func happyPathZeroCount() async throws {
        let body = Data(#"{"payload":{"count":0}}"#.utf8)
        let client = makeClient { _ in (body, response(status: 200)) }
        let result = try await client.validateUsername("newuser")
        #expect(result == true)
    }

    @Test("200 with non-JSON body throws .decoding (guards against HTML redirect responses)")
    func twoHundredNonJSONBodyThrowsDecoding() async throws {
        let htmlBody = Data("<html><body>Not JSON</body></html>".utf8)
        let client = makeClient { _ in (htmlBody, response(status: 200)) }
        do {
            _ = try await client.validateUsername("testuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.decoding {
            // correct
        } catch {
            Issue.record("Expected .decoding, got \(error)")
        }
    }

    @Test("404 throws userNotFound")
    func userNotFound() async throws {
        let client = makeClient { _ in (Data(), response(status: 404)) }
        do {
            _ = try await client.validateUsername("ghostuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.userNotFound {
            // correct
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("429 without Retry-After throws rateLimited(retryAfter: nil)")
    func rateLimitedNoHeader() async throws {
        let client = makeClient { _ in (Data(), response(status: 429)) }
        do {
            _ = try await client.validateUsername("someuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.rateLimited(let delay) {
            #expect(delay == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("429 with Retry-After header parses delay")
    func rateLimitedWithHeader() async throws {
        let client = makeClient { _ in (Data(), response(status: 429, headers: ["Retry-After": "42"])) }
        do {
            _ = try await client.validateUsername("someuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.rateLimited(let delay) {
            #expect(delay == 42)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("500 throws httpError")
    func serverError() async throws {
        let client = makeClient { _ in (Data(), response(status: 500)) }
        do {
            _ = try await client.validateUsername("someuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.httpError(let code) {
            #expect(code == 500)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("network failure wraps in .network")
    func networkFailure() async throws {
        let client = makeClient { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.validateUsername("someuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.network {
            // correct
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("invalid username format rejects locally without network call")
    func invalidUsernameRejectsLocally() async throws {
        // FailingTransport throws URLError -> would become .network if called.
        // Receiving .invalidUsername proves no network hop happened.
        let client = ListenBrainzClient(transport: FailingTransport())
        do {
            _ = try await client.validateUsername("invalid user@#!")
            Issue.record("Expected throw")
        } catch ListenBrainzError.invalidUsername {
            // correct: local rejection
        } catch {
            Issue.record("Expected .invalidUsername, got \(type(of: error))")
        }
    }

    @Test("empty username rejects locally")
    func emptyUsernameRejectsLocally() async throws {
        let client = ListenBrainzClient(transport: FailingTransport())
        do {
            _ = try await client.validateUsername("")
            Issue.record("Expected throw")
        } catch ListenBrainzError.invalidUsername {
            // correct
        } catch {
            Issue.record("Expected .invalidUsername, got \(type(of: error))")
        }
    }

    @Test("username over 40 chars rejects locally")
    func tooLongUsernameRejectsLocally() async throws {
        let client = ListenBrainzClient(transport: FailingTransport())
        let long = String(repeating: "a", count: 41)
        do {
            _ = try await client.validateUsername(long)
            Issue.record("Expected throw")
        } catch ListenBrainzError.invalidUsername {
            // correct
        } catch {
            Issue.record("Expected .invalidUsername, got \(type(of: error))")
        }
    }

    // MARK: - Canary: error descriptions must never expose username

    @Test("canary: error descriptions do not leak the username")
    func errorDescriptionsClean() {
        let canary = "CANARY_USER_DO_NOT_LEAK_42"
        let errors: [ListenBrainzError] = [
            .invalidUsername,
            .userNotFound,
            .network(URLError(.notConnectedToInternet)),
            .rateLimited(retryAfter: 60),
            .rateLimited(retryAfter: nil),
            .httpError(statusCode: 500),
            .unauthorized,
        ]
        for error in errors {
            #expect(!error.localizedDescription.contains(canary), "localizedDescription leaks canary in \(error)")
            #expect(!(error.errorDescription ?? "").contains(canary), "errorDescription leaks canary in \(error)")
            #expect(!error.description.contains(canary), "description leaks canary in \(error)")
            #expect(!error.debugDescription.contains(canary), "debugDescription leaks canary in \(error)")
        }
    }
}
