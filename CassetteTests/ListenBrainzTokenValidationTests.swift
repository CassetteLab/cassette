// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Helpers

private struct TokenMockTransport: ListenBrainzTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

private func stubResponse(status: Int, body: String = "") -> (Data, HTTPURLResponse) {
    let resp = HTTPURLResponse(
        url: URL(string: "https://api.listenbrainz.org/1/validate-token")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
    return (Data(body.utf8), resp)
}

private let defaultRoot = URL(string: "https://api.listenbrainz.org")!

// MARK: - validateToken decoding

@Suite("ListenBrainzClient — validateToken")
struct ListenBrainzTokenValidationTests {

    @Test("200 valid:true with user_name → isValid true, username populated")
    func validTokenWithUsername() async throws {
        let body = #"{"code":200,"valid":true,"user_name":"alice"}"#
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in stubResponse(status: 200, body: body) })
        let result = try await client.validateToken("tok_secret", rootURL: defaultRoot)
        #expect(result.isValid == true)
        #expect(result.username == "alice")
    }

    @Test("200 valid:false → isValid false, no throw")
    func invalidTokenNoThrow() async throws {
        let body = #"{"code":200,"valid":false,"user_name":null}"#
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in stubResponse(status: 200, body: body) })
        let result = try await client.validateToken("bad_token", rootURL: defaultRoot)
        #expect(result.isValid == false)
        #expect(result.username == nil)
    }

    @Test("200 user_name absent → username nil")
    func validTokenWithoutUsername() async throws {
        let body = #"{"valid":true}"#
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in stubResponse(status: 200, body: body) })
        let result = try await client.validateToken("tok_secret", rootURL: defaultRoot)
        #expect(result.isValid == true)
        #expect(result.username == nil)
    }

    @Test("401 → isValid false, no throw")
    func unauthorizedNoThrow() async throws {
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in stubResponse(status: 401) })
        let result = try await client.validateToken("bad_token", rootURL: defaultRoot)
        #expect(result.isValid == false)
        #expect(result.username == nil)
    }

    @Test("500 → throws httpError(500)")
    func serverErrorThrows() async throws {
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in stubResponse(status: 500) })
        do {
            _ = try await client.validateToken("tok", rootURL: defaultRoot)
            Issue.record("Expected throw")
        } catch ListenBrainzError.httpError(let code) {
            #expect(code == 500)
        } catch {
            Issue.record("Expected .httpError, got \(error)")
        }
    }

    @Test("network failure → throws .network")
    func networkFailureThrows() async throws {
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await client.validateToken("tok", rootURL: defaultRoot)
            Issue.record("Expected throw")
        } catch ListenBrainzError.network {
            // correct
        } catch {
            Issue.record("Expected .network, got \(error)")
        }
    }

    @Test("200 non-JSON body → throws .decoding")
    func nonJSONBodyThrowsDecoding() async throws {
        let client = ListenBrainzClient(transport: TokenMockTransport { _ in stubResponse(status: 200, body: "<html>not json</html>") })
        do {
            _ = try await client.validateToken("tok", rootURL: defaultRoot)
            Issue.record("Expected throw")
        } catch ListenBrainzError.decoding {
            // correct
        } catch {
            Issue.record("Expected .decoding, got \(error)")
        }
    }

    @Test("Authorization header contains token, token absent from URL")
    func authorizationHeaderSet() async throws {
        var capturedRequest: URLRequest?
        let body = #"{"valid":true,"user_name":"alice"}"#
        let client = ListenBrainzClient(transport: TokenMockTransport { req in
            capturedRequest = req
            return stubResponse(status: 200, body: body)
        })
        _ = try await client.validateToken("my_secret_token", rootURL: defaultRoot)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Token my_secret_token")
        let urlString = capturedRequest?.url?.absoluteString ?? ""
        #expect(!urlString.contains("my_secret_token"))
    }

    @Test("custom rootURL path component preserved")
    func customRootURLPathPreserved() async throws {
        var capturedURL: URL?
        let body = #"{"valid":true,"user_name":"bob"}"#
        let customRoot = URL(string: "https://myhost.example.com/lb")!
        let client = ListenBrainzClient(transport: TokenMockTransport { req in
            capturedURL = req.url
            return stubResponse(status: 200, body: body)
        })
        _ = try await client.validateToken("tok", rootURL: customRoot)
        #expect(capturedURL?.absoluteString == "https://myhost.example.com/lb/1/validate-token")
    }
}

// MARK: - URL normalization

@Suite("ListenBrainzService — normalizeServerURL")
struct ListenBrainzURLNormalizationTests {

    @Test("trailing slash stripped")
    func trailingSlashStripped() {
        #expect(ListenBrainzService.normalizeServerURL("https://api.listenbrainz.org/") == "https://api.listenbrainz.org")
    }

    @Test("multiple trailing slashes stripped")
    func multipleTrailingSlashesStripped() {
        #expect(ListenBrainzService.normalizeServerURL("https://myserver.com///") == "https://myserver.com")
    }

    @Test("leading and trailing whitespace trimmed")
    func whitespaceTrimmed() {
        #expect(ListenBrainzService.normalizeServerURL("  https://api.listenbrainz.org  ") == "https://api.listenbrainz.org")
    }

    @Test("whitespace and trailing slash both handled")
    func whitespaceAndSlashHandled() {
        #expect(ListenBrainzService.normalizeServerURL("  https://api.listenbrainz.org/  ") == "https://api.listenbrainz.org")
    }

    @Test("URL with path component preserved")
    func pathComponentPreserved() {
        #expect(ListenBrainzService.normalizeServerURL("https://myhost.com/lb") == "https://myhost.com/lb")
    }

    @Test("clean URL unchanged")
    func cleanURLUnchanged() {
        #expect(ListenBrainzService.normalizeServerURL("https://api.listenbrainz.org") == "https://api.listenbrainz.org")
    }
}
