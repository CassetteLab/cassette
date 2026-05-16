// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Mock

private struct CHTRecordingTransport: HTTPTransport {
    actor State {
        private(set) var lastRequest: URLRequest?
        func record(_ request: URLRequest) { lastRequest = request }
    }
    let state = State()
    let response: (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await state.record(request)
        return response
    }
}

private func makeResponse(status: Int = 200) -> (Data, HTTPURLResponse) {
    let resp = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
    return (Data(), resp)
}

// MARK: - Header injection

@Suite("CustomHeadersTransport — header injection")
struct CustomHeadersTransportTests {

    @Test("injects custom headers onto the forwarded request")
    func injectsHeaders() async throws {
        let mock = CHTRecordingTransport(response: makeResponse())
        let transport = CustomHeadersTransport(
            base: mock,
            headers: ["CF-Access-Client-Id": "id-123", "X-Custom": "hello"]
        )

        var req = URLRequest(url: URL(string: "https://sub.example.com/api")!)
        _ = try await transport.data(for: req)

        let recorded = await mock.state.lastRequest
        #expect(recorded?.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id-123")
        #expect(recorded?.value(forHTTPHeaderField: "X-Custom") == "hello")
    }

    @Test("does not inject headers when map is empty")
    func noHeadersWhenEmpty() async throws {
        let mock = CHTRecordingTransport(response: makeResponse())
        let transport = CustomHeadersTransport(base: mock, headers: [:])

        var req = URLRequest(url: URL(string: "https://sub.example.com/api")!)
        req.setValue("keep-me", forHTTPHeaderField: "Authorization")
        _ = try await transport.data(for: req)

        let recorded = await mock.state.lastRequest
        #expect(recorded?.value(forHTTPHeaderField: "Authorization") == "keep-me")
    }

    @Test("preserves existing request headers alongside injected ones")
    func preservesExistingHeaders() async throws {
        let mock = CHTRecordingTransport(response: makeResponse())
        let transport = CustomHeadersTransport(base: mock, headers: ["X-Injected": "yes"])

        var req = URLRequest(url: URL(string: "https://sub.example.com/api")!)
        req.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        _ = try await transport.data(for: req)

        let recorded = await mock.state.lastRequest
        #expect(recorded?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(recorded?.value(forHTTPHeaderField: "X-Injected") == "yes")
    }

    @Test("propagates error from base transport")
    func propagatesError() async throws {
        struct AlwaysFailTransport: HTTPTransport {
            func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                throw URLError(.notConnectedToInternet)
            }
        }
        let transport = CustomHeadersTransport(base: AlwaysFailTransport(), headers: [:])
        let req = URLRequest(url: URL(string: "https://sub.example.com/api")!)
        var caught: Error?
        do { _ = try await transport.data(for: req) } catch { caught = error }
        #expect((caught as? URLError)?.code == .notConnectedToInternet)
    }
}

// MARK: - Slow-server timeout (disabled — takes ~30s)

@Suite("CustomHeadersTransport — timeout")
struct CustomHeadersTransportTimeoutTests {

    // Enable manually to validate that the default session's 30s resource timeout fires.
    // Requires no proxy / firewall intercepting the request — uses a black-hole server address.
    @Test(.disabled("Takes ~30s — enable manually to validate timeout config"))
    func defaultInit_timesOutOnHungServer() async throws {
        let transport = CustomHeadersTransport(headers: [:])
        // RFC 5737 TEST-NET address — routable but guaranteed to never respond.
        var req = URLRequest(url: URL(string: "http://192.0.2.1/ping")!)
        req.timeoutInterval = 35  // outer guard; real timeout comes from the session config
        var caught: Error?
        do { _ = try await transport.data(for: req) } catch { caught = error }
        let code = (caught as? URLError)?.code
        #expect(code == .timedOut || code == .cannotConnectToHost)
    }
}
