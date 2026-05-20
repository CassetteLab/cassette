// Cassette
// Copyright (C) 2026 Mathieu Dubart
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

// MARK: - Stub transport

/// Returns a fixed response or throws a URLError. Used to drive SwiftSonicClient
/// through specific code paths without touching the network.
struct StubHTTPTransport: HTTPTransport, Sendable {
    enum Outcome: Sendable {
        case response(data: Data, statusCode: Int)
        case urlError(URLError.Code)
    }
    let outcome: Outcome

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch outcome {
        case .response(let data, let statusCode):
            let url = request.url ?? URL(string: "https://stub.example.com")!
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        case .urlError(let code):
            throw URLError(code)
        }
    }
}

// MARK: - JSON helpers

private func subsonicErrorJSON(code: Int, message: String) -> Data {
    Data("""
    {"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":\(code),"message":"\(message)"}}}
    """.utf8)
}

private func nonSubsonicJSON() -> Data {
    Data("{\"error\":\"not found\"}".utf8)
}

// MARK: - Suite

@Suite("ConnectionTestError mapping — ServerService.mapToConnectionTestError")
@MainActor
struct ConnectionTestErrorMappingTests {

    private func makeService() throws -> ServerService {
        let container = try ModelContainer.cassette(inMemory: true)
        let state = ServerState()
        return ServerService(
            state: state,
            keychain: MockKeychain(),
            modelContainer: container,
            cacheService: MockCacheService()
        )
    }

    private func makeClient(transport: StubHTTPTransport) -> SwiftSonicClient {
        SwiftSonicClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://stub.example.com")!,
                username: "u",
                password: "p"
            ),
            transport: transport,
            retryPolicy: .none
        )
    }

    // MARK: .network — DNS failure

    @Test func network_cannotFindHost_mapsToDNSFailure() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(SwiftSonicError.network(URLError(.cannotFindHost)))
        #expect(result == .dnsFailure)
    }

    @Test func network_dnsLookupFailed_mapsToDNSFailure() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(SwiftSonicError.network(URLError(.dnsLookupFailed)))
        #expect(result == .dnsFailure)
    }

    // MARK: .network — timeout

    @Test func network_timedOut_mapsToTimeout() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(SwiftSonicError.network(URLError(.timedOut)))
        #expect(result == .timeout)
    }

    // MARK: .network — ATS

    @Test func network_atsBlocked_mapsToAtsBlocked() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.network(URLError(.appTransportSecurityRequiresSecureConnection))
        )
        #expect(result == .atsBlocked)
    }

    // MARK: .network — certificate

    @Test func network_certificateUntrusted_mapsToCertificate() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.network(URLError(.serverCertificateUntrusted))
        )
        #expect(result == .certificate)
    }

    @Test func network_certificateBadDate_mapsToCertificate() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.network(URLError(.serverCertificateHasBadDate))
        )
        #expect(result == .certificate)
    }

    // MARK: .network — cannotConnect (default bucket)

    @Test func network_cannotConnectToHost_mapsToCannotConnect() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.network(URLError(.cannotConnectToHost))
        )
        #expect(result == .cannotConnect)
    }

    @Test func network_notConnectedToInternet_mapsToCannotConnect() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.network(URLError(.notConnectedToInternet))
        )
        #expect(result == .cannotConnect)
    }

    // MARK: .httpError

    @Test func httpError_401_mapsToUnauthorized() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.httpError(statusCode: 401, endpoint: "ping", serverHost: nil)
        )
        #expect(result == .unauthorized)
    }

    @Test func httpError_403_mapsToUnauthorized() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.httpError(statusCode: 403, endpoint: "ping", serverHost: nil)
        )
        #expect(result == .unauthorized)
    }

    @Test func httpError_404_mapsToHttpError() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.httpError(statusCode: 404, endpoint: "ping", serverHost: nil)
        )
        #expect(result == .httpError(statusCode: 404))
    }

    @Test func httpError_500_mapsToHttpError() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.httpError(statusCode: 500, endpoint: "ping", serverHost: nil)
        )
        #expect(result == .httpError(statusCode: 500))
    }

    // MARK: .decoding → notSubsonicServer (via stub transport)

    @Test func decoding_mapsToNotSubsonicServer() async throws {
        let service = try makeService()
        let client = makeClient(transport: StubHTTPTransport(outcome: .response(data: nonSubsonicJSON(), statusCode: 200)))
        let error: ConnectionTestError
        do {
            try await client.ping()
            Issue.record("Expected ping to throw for non-Subsonic JSON")
            return
        } catch let e {
            error = await service.mapToConnectionTestError(e)
        }
        #expect(error == .notSubsonicServer)
    }

    // MARK: .rateLimited

    @Test func rateLimited_mapsToHttpError429() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(
            SwiftSonicError.rateLimited(retryAfter: nil, endpoint: "ping", serverHost: nil)
        )
        #expect(result == .httpError(statusCode: 429))
    }

    // MARK: .invalidConfiguration

    @Test func invalidConfiguration_mapsToInvalidConfiguration() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(SwiftSonicError.invalidConfiguration("bad URL"))
        #expect(result == .invalidConfiguration)
    }

    // MARK: .insecureRedirect

    @Test func insecureRedirect_mapsToInsecureRedirect() async throws {
        let service = try makeService()
        let from = URL(string: "https://music.example.com/rest/ping")!
        let to = URL(string: "https://other.example.com/rest/ping")!
        let result = await service.mapToConnectionTestError(SwiftSonicError.insecureRedirect(from: from, to: to))
        #expect(result == .insecureRedirect)
    }

    // MARK: .api — via stub transport (SubsonicAPIError has no public init)

    @Test func api_wrongCredentials_mapsToUnauthorized() async throws {
        let service = try makeService()
        let client = makeClient(transport: StubHTTPTransport(
            outcome: .response(data: subsonicErrorJSON(code: 40, message: "Wrong username or password"), statusCode: 200)
        ))
        let error: ConnectionTestError
        do {
            try await client.ping()
            Issue.record("Expected ping to throw for Subsonic error code 40")
            return
        } catch let e {
            error = await service.mapToConnectionTestError(e)
        }
        #expect(error == .unauthorized)
    }

    @Test func api_generic_mapsToSubsonicError() async throws {
        let service = try makeService()
        let client = makeClient(transport: StubHTTPTransport(
            outcome: .response(data: subsonicErrorJSON(code: 0, message: "Generic server error"), statusCode: 200)
        ))
        let error: ConnectionTestError
        do {
            try await client.ping()
            Issue.record("Expected ping to throw for Subsonic error code 0")
            return
        } catch let e {
            error = await service.mapToConnectionTestError(e)
        }
        #expect(error == .subsonicError(code: .generic, message: "Generic server error"))
    }

    @Test func api_notFound_mapsToSubsonicError() async throws {
        let service = try makeService()
        let client = makeClient(transport: StubHTTPTransport(
            outcome: .response(data: subsonicErrorJSON(code: 70, message: "Not found"), statusCode: 200)
        ))
        let error: ConnectionTestError
        do {
            try await client.ping()
            Issue.record("Expected ping to throw for Subsonic error code 70")
            return
        } catch let e {
            error = await service.mapToConnectionTestError(e)
        }
        #expect(error == .subsonicError(code: .notFound, message: "Not found"))
    }

    // MARK: Non-SwiftSonicError

    @Test func nonSwiftSonicError_mapsToUnknown() async throws {
        let service = try makeService()
        let result = await service.mapToConnectionTestError(CassetteError.notImplemented)
        if case .unknown = result { } else {
            Issue.record("Expected .unknown, got \(result)")
        }
    }
}
