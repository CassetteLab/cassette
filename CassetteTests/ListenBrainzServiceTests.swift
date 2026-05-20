// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Flexible mock transport

/// Queue-based transport: enqueue responses in order. Throws URLError if queue is empty.
private actor FlexibleTransport: ListenBrainzTransport {
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(status: Int, headers: [String: String]? = nil) {
        let body = status == 200 ? Data(#"{"payload":{"count":0}}"#.utf8) : Data()
        let resp = HTTPURLResponse(
            url: URL(string: "https://api.listenbrainz.org/1/user/test")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        queue.append((body, resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !queue.isEmpty else { throw URLError(.unknown) }
        return queue.removeFirst()
    }
}

// MARK: - Mock keychain (LB-specific to avoid collision with ServerServiceTests.MockKeychain)

private actor LBMockKeychain: KeychainServiceProtocol {
    private var storage: [String: Data] = [:]

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) async throws {
        storage[key] = nil
    }
}

// MARK: - Helpers

private let keychainKey = "listenbrainz-username"
private let defaultsKey = "app.cassette.listenbrainz.isEnabled"

private func makeComponents(transport: any ListenBrainzTransport) -> (ListenBrainzService, LBMockKeychain, UserDefaults) {
    let client = ListenBrainzClient(transport: transport)
    let keychain = LBMockKeychain()
    let defaults = UserDefaults(suiteName: "test.lb.\(UUID().uuidString)")!
    let service = ListenBrainzService(client: client, keychain: keychain, userDefaults: defaults)
    return (service, keychain, defaults)
}

// MARK: - enable() tests

@Suite("ListenBrainzService — enable")
struct ListenBrainzServiceEnableTests {

    @Test("happy path: transitions to .valid, persists username, flips isEnabled")
    func enableHappyPath() async throws {
        let transport = FlexibleTransport()
        await transport.enqueue(status: 200)
        let (service, keychain, defaults) = makeComponents(transport: transport)

        let initial = await service.currentSnapshot()
        #expect(initial.validationStatus == ValidationStatus.unknown)
        #expect(!initial.isEnabled)

        try await service.enable(username: "validuser")

        let snap = await service.currentSnapshot()
        #expect(snap.isEnabled)
        #expect(snap.validationStatus == ValidationStatus.valid)
        #expect(snap.username == "validuser")

        let stored = try await keychain.retrieve(String.self, forKey: keychainKey)
        #expect(stored == "validuser")
        #expect(defaults.bool(forKey: defaultsKey))
    }

    @Test("user not found: stays disabled, username not persisted, status .invalid")
    func enableUserNotFound() async throws {
        let transport = FlexibleTransport()
        await transport.enqueue(status: 404)
        let (service, keychain, defaults) = makeComponents(transport: transport)

        do {
            try await service.enable(username: "ghostuser")
            Issue.record("Expected throw")
        } catch ListenBrainzError.userNotFound {
            // correct
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let snap = await service.currentSnapshot()
        #expect(!snap.isEnabled)
        if case .invalid = snap.validationStatus {} else {
            Issue.record("Expected .invalid status, got \(snap.validationStatus)")
        }

        let stored = try await keychain.retrieve(String.self, forKey: keychainKey)
        #expect(stored == nil)
        #expect(!defaults.bool(forKey: defaultsKey))
    }
}

// MARK: - disable() tests

@Suite("ListenBrainzService — disable")
struct ListenBrainzServiceDisableTests {

    @Test("isEnabled flips to false; username remains in Keychain")
    func disableKeepsKeychain() async throws {
        let transport = FlexibleTransport()
        await transport.enqueue(status: 200)
        let (service, keychain, _) = makeComponents(transport: transport)

        try await service.enable(username: "keepme")
        await service.disable()

        let snap = await service.currentSnapshot()
        #expect(!snap.isEnabled)

        // Username must survive disable — re-enable should require no re-entry
        let stored = try await keychain.retrieve(String.self, forKey: keychainKey)
        #expect(stored == "keepme")
    }
}

// MARK: - clearCredentials() tests

@Suite("ListenBrainzService — clearCredentials")
struct ListenBrainzServiceClearTests {

    @Test("purges username, isEnabled, and validationStatus")
    func clearCredentialsPurgesAll() async throws {
        let transport = FlexibleTransport()
        await transport.enqueue(status: 200)
        let (service, keychain, defaults) = makeComponents(transport: transport)

        try await service.enable(username: "clearme")
        await service.clearCredentials()

        let snap = await service.currentSnapshot()
        #expect(!snap.isEnabled)
        #expect(snap.username == nil)
        #expect(snap.validationStatus == ValidationStatus.unknown)

        let stored = try await keychain.retrieve(String.self, forKey: keychainKey)
        #expect(stored == nil)
        #expect(!defaults.bool(forKey: defaultsKey))
    }
}

// MARK: - revalidate() tests

@Suite("ListenBrainzService — revalidate")
struct ListenBrainzServiceRevalidateTests {

    @Test("no stored username: no-op, no network call")
    func revalidateWithoutUsername() async throws {
        // Empty FlexibleTransport throws URLError on send — completing without error
        // proves the no-op branch (no username) was taken.
        let (service, _, _) = makeComponents(transport: FlexibleTransport())
        try await service.revalidate()
    }

    @Test("with stored username: re-validates via network, transitions to .valid")
    func revalidateWithUsername() async throws {
        let transport = FlexibleTransport()
        await transport.enqueue(status: 200) // for enable
        await transport.enqueue(status: 200) // for revalidate
        let (service, _, _) = makeComponents(transport: transport)

        try await service.enable(username: "myuser")
        try await service.revalidate()

        let snap = await service.currentSnapshot()
        #expect(snap.validationStatus == ValidationStatus.valid)
    }

    @Test("with stored username and network failure: transitions to .invalid")
    func revalidateNetworkFailure() async throws {
        let transport = FlexibleTransport()
        await transport.enqueue(status: 200) // for enable
        await transport.enqueue(status: 404) // user disappeared
        let (service, _, _) = makeComponents(transport: transport)

        try await service.enable(username: "myuser")

        do {
            try await service.revalidate()
            Issue.record("Expected throw")
        } catch ListenBrainzError.userNotFound {
            // correct
        }

        let snap = await service.currentSnapshot()
        if case .invalid = snap.validationStatus {} else {
            Issue.record("Expected .invalid, got \(snap.validationStatus)")
        }
    }
}

// MARK: - Canary: username must never leak

@Suite("ListenBrainzService — canary secrets")
struct ListenBrainzServiceCanaryTests {

    @Test("username never appears in error descriptions or validation reason")
    func usernameNotLeakedInDescriptions() async throws {
        let canary = "CANARY_USER_DO_NOT_LEAK_42"
        let transport = FlexibleTransport()
        await transport.enqueue(status: 404)
        let (service, _, _) = makeComponents(transport: transport)

        var caughtError: (any Error)?
        do {
            try await service.enable(username: canary)
        } catch {
            caughtError = error
        }

        if let error = caughtError as? ListenBrainzError {
            #expect(!error.localizedDescription.contains(canary), "localizedDescription leaks username")
            #expect(!(error.errorDescription ?? "").contains(canary), "errorDescription leaks username")
            #expect(!error.description.contains(canary), "description leaks username")
            #expect(!error.debugDescription.contains(canary), "debugDescription leaks username")
        }

        let snap = await service.currentSnapshot()
        if case .invalid(let reason) = snap.validationStatus {
            #expect(!reason.contains(canary), "validationStatus.invalid(reason:) leaks username")
        }
    }
}
