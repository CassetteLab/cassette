// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Fixtures

private let twoReleasesJSON = Data("""
{
  "payload": {
    "releases": [
      {
        "artist_credit_name": "Fixture Artist One",
        "release_name": "Fixture Album One",
        "release_date": "2026-03-15",
        "release_group_mbid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "caa_id": 987654321,
        "caa_release_mbid": "ffffffff-0000-1111-2222-333333333333",
        "release_mbid": "11111111-2222-3333-4444-555555555555",
        "artist_mbids": ["66666666-7777-8888-9999-aaaaaaaaaaaa"],
        "confidence": 0.95
      },
      {
        "artist_credit_name": "Fixture Artist Two",
        "release_name": "Fixture Album Two",
        "release_date": "2026-04-01",
        "release_group_mbid": "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
      }
    ]
  }
}
""".utf8)

private let malformedJSON = Data("{ not valid json }".utf8)

private let emptyReleasesJSON = Data("""
{ "payload": { "releases": [] } }
""".utf8)

// MARK: - Mock transport

private actor FRTransport: ListenBrainzTransport {
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(data: Data = Data(), status: Int, headers: [String: String]? = nil, url: String = "https://api.listenbrainz.org") {
        let resp = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        queue.append((data, resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

private func makeClient(transport: FRTransport) -> ListenBrainzClient {
    ListenBrainzClient(transport: transport)
}

// MARK: - Happy path

@Suite("ListenBrainzClient — freshReleases")
struct ListenBrainzClientFreshReleasesTests {

    @Test("happy path: parses two releases with correct field mapping")
    func happyPathTwoReleases() async throws {
        let transport = FRTransport()
        await transport.enqueue(data: twoReleasesJSON, status: 200)
        let client = makeClient(transport: transport)

        let releases = try await client.freshReleases(forUser: "testuser")

        #expect(releases.count == 2)
        #expect(releases[0].artistCreditName == "Fixture Artist One")
        #expect(releases[0].releaseName == "Fixture Album One")
        #expect(releases[0].releaseDate == "2026-03-15")
        #expect(releases[0].releaseGroupMbid == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(releases[0].caaId == 987654321)
        #expect(releases[0].caaReleaseMbid == "ffffffff-0000-1111-2222-333333333333")
        #expect(releases[1].artistCreditName == "Fixture Artist Two")
        #expect(releases[1].caaId == nil)
        #expect(releases[1].caaReleaseMbid == nil)
    }

    @Test("empty releases array parses without error")
    func emptyReleasesArray() async throws {
        let transport = FRTransport()
        await transport.enqueue(data: emptyReleasesJSON, status: 200)
        let client = makeClient(transport: transport)

        let releases = try await client.freshReleases(forUser: "testuser")
        #expect(releases.isEmpty)
    }

    @Test("unknown JSON fields are silently ignored")
    func unknownFieldsIgnored() async throws {
        let transport = FRTransport()
        await transport.enqueue(data: twoReleasesJSON, status: 200)
        let client = makeClient(transport: transport)

        let releases = try await client.freshReleases(forUser: "testuser")
        #expect(releases.count == 2)
    }

    // MARK: - HTTP error mapping

    @Test("404 response throws userNotFound")
    func notFoundThrows() async throws {
        let transport = FRTransport()
        await transport.enqueue(status: 404)
        let client = makeClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.freshReleases(forUser: "ghost")
        } catch {
            caught = error
        }
        #expect(caught is ListenBrainzError)
        if case .userNotFound = caught as? ListenBrainzError {} else {
            Issue.record("Expected .userNotFound, got \(String(describing: caught))")
        }
    }

    @Test("429 with Retry-After header throws rateLimited with parsed delay")
    func rateLimitedWithRetryAfter() async throws {
        let transport = FRTransport()
        await transport.enqueue(status: 429, headers: ["Retry-After": "30"])
        let client = makeClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.freshReleases(forUser: "testuser")
        } catch {
            caught = error
        }
        if case .rateLimited(let after) = caught as? ListenBrainzError {
            #expect(after == 30)
        } else {
            Issue.record("Expected .rateLimited, got \(String(describing: caught))")
        }
    }

    @Test("429 without Retry-After header throws rateLimited(retryAfter: nil)")
    func rateLimitedNoHeader() async throws {
        let transport = FRTransport()
        await transport.enqueue(status: 429)
        let client = makeClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.freshReleases(forUser: "testuser")
        } catch {
            caught = error
        }
        if case .rateLimited(let after) = caught as? ListenBrainzError {
            #expect(after == nil)
        } else {
            Issue.record("Expected .rateLimited(nil), got \(String(describing: caught))")
        }
    }

    @Test("500 response throws httpError")
    func serverErrorThrows() async throws {
        let transport = FRTransport()
        await transport.enqueue(status: 500)
        let client = makeClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.freshReleases(forUser: "testuser")
        } catch {
            caught = error
        }
        if case .httpError(let code) = caught as? ListenBrainzError {
            #expect(code == 500)
        } else {
            Issue.record("Expected .httpError(500), got \(String(describing: caught))")
        }
    }

    @Test("malformed JSON throws decoding error")
    func malformedJSONThrows() async throws {
        let transport = FRTransport()
        await transport.enqueue(data: malformedJSON, status: 200)
        let client = makeClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.freshReleases(forUser: "testuser")
        } catch {
            caught = error
        }
        if case .decoding = caught as? ListenBrainzError {} else {
            Issue.record("Expected .decoding, got \(String(describing: caught))")
        }
    }

    @Test("network failure throws network error")
    func networkFailureThrows() async throws {
        let transport = FRTransport()
        // Empty queue → URLError(.timedOut) from transport
        let client = makeClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.freshReleases(forUser: "testuser")
        } catch {
            caught = error
        }
        if case .network = caught as? ListenBrainzError {} else {
            Issue.record("Expected .network, got \(String(describing: caught))")
        }
    }

    // MARK: - Canary

    @Test("canary: error descriptions never expose the username")
    func canaryUsernameNotInErrors() async throws {
        let canary = "CANARY_USER_DO_NOT_LEAK_42"
        let transport = FRTransport()
        await transport.enqueue(status: 404)
        let client = makeClient(transport: transport)

        do {
            _ = try await client.freshReleases(forUser: canary)
        } catch let error as ListenBrainzError {
            let desc = error.description
            let localizedDesc = error.errorDescription ?? ""
            #expect(!desc.contains(canary), "description exposed canary: \"\(desc)\"")
            #expect(!localizedDesc.contains(canary), "errorDescription exposed canary: \"\(localizedDesc)\"")
        } catch {
            Issue.record("Expected ListenBrainzError, got \(error)")
        }
    }
}
