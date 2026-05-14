// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Helpers

private actor VMTransport: ListenBrainzTransport {
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(status: Int, for username: String = "user") {
        let resp = HTTPURLResponse(
            url: URL(string: "https://api.listenbrainz.org/1/user/\(username)")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        queue.append((Data(), resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

private actor VMKeychain: KeychainServiceProtocol {
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

@MainActor
private func makeComponents() -> (ListenBrainzSettingsViewModel, VMTransport, UserDefaults) {
    let transport = VMTransport()
    let keychain = VMKeychain()
    let defaults = UserDefaults(suiteName: "test.vmtest.\(UUID().uuidString)")!
    let client = ListenBrainzClient(transport: transport)
    let service = ListenBrainzService(client: client, keychain: keychain, userDefaults: defaults)
    let vm = ListenBrainzSettingsViewModel(service: service)
    return (vm, transport, defaults)
}

// MARK: - Tests

@Suite("ListenBrainzSettingsViewModel")
struct ListenBrainzSettingsViewModelTests {

    // MARK: validateUsernameInputLocally

    @Test("valid username clears validation error")
    @MainActor func validUsernameInputClearsError() {
        let (vm, _, _) = makeComponents()

        vm.usernameInput = "valid_user-123"
        vm.validateUsernameInputLocally()

        #expect(vm.usernameInputValidationError == nil)
    }

    @Test("empty input does not set validation error")
    @MainActor func emptyInputNoError() {
        let (vm, _, _) = makeComponents()

        vm.usernameInput = ""
        vm.validateUsernameInputLocally()

        #expect(vm.usernameInputValidationError == nil)
    }

    @Test("username with space sets validation error")
    @MainActor func usernameWithSpaceSetsError() {
        let (vm, _, _) = makeComponents()

        vm.usernameInput = "bad user"
        vm.validateUsernameInputLocally()

        #expect(vm.usernameInputValidationError != nil)
    }

    @Test("username over 40 chars sets validation error")
    @MainActor func longUsernameSetsError() {
        let (vm, _, _) = makeComponents()

        vm.usernameInput = String(repeating: "a", count: 41)
        vm.validateUsernameInputLocally()

        #expect(vm.usernameInputValidationError != nil)
    }

    // MARK: connect

    @Test("connect with 200 enables integration")
    @MainActor func connectSucceeds() async {
        let (vm, transport, _) = makeComponents()
        await transport.enqueue(status: 200)

        vm.usernameInput = "user"
        await vm.connect()

        #expect(vm.snapshot.isEnabled == true)
        #expect(vm.userFacingError == nil)
        #expect(vm.isProcessing == false)
    }

    @Test("connect with 404 sets userFacingError and leaves disabled")
    @MainActor func connectUserNotFound() async {
        let (vm, transport, _) = makeComponents()
        await transport.enqueue(status: 404)

        vm.usernameInput = "ghost"
        await vm.connect()

        #expect(vm.userFacingError != nil)
        #expect(vm.snapshot.isEnabled == false)
        #expect(vm.isProcessing == false)
    }

    // MARK: disconnect

    @Test("disconnect disables after a successful connect")
    @MainActor func disconnectDisables() async {
        let (vm, transport, _) = makeComponents()
        await transport.enqueue(status: 200)

        vm.usernameInput = "user"
        await vm.connect()
        await vm.disconnect()

        #expect(vm.snapshot.isEnabled == false)
        #expect(vm.isProcessing == false)
    }

    // MARK: resetCredentials

    @Test("resetCredentials wipes username and snapshot")
    @MainActor func resetCredentialsClearsState() async {
        let (vm, transport, _) = makeComponents()
        await transport.enqueue(status: 200)

        vm.usernameInput = "user"
        await vm.connect()
        await vm.resetCredentials()

        #expect(vm.usernameInput == "")
        #expect(vm.snapshot.username == nil)
        #expect(vm.snapshot.isEnabled == false)
        #expect(vm.isProcessing == false)
    }

    // MARK: Canary — username must not appear in userFacingError

    @Test("userFacingError never exposes canary username (404)")
    @MainActor func canaryNotInUserNotFoundError() async {
        let canary = "CANARY_USER_DO_NOT_LEAK_42"
        let (vm, transport, _) = makeComponents()
        await transport.enqueue(status: 404, for: canary)

        vm.usernameInput = canary
        await vm.connect()

        if let error = vm.userFacingError {
            #expect(!error.contains(canary), "userFacingError must not expose the username — found canary in: \"\(error)\"")
        }
    }

    @Test("userFacingError never exposes canary username (500)")
    @MainActor func canaryNotInHttpError() async {
        let canary = "CANARY_USER_DO_NOT_LEAK_42"
        let (vm, transport, _) = makeComponents()
        await transport.enqueue(status: 500, for: canary)

        vm.usernameInput = canary
        await vm.connect()

        if let error = vm.userFacingError {
            #expect(!error.contains(canary), "userFacingError must not expose the username — found canary in: \"\(error)\"")
        }
    }
}
