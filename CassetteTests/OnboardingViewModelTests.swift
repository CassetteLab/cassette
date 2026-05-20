// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Mock service

@MainActor
final class MockServerService: ServerServiceProtocol {
    let state: ServerState = ServerState()

    // Configurable outcomes
    var testConnectionError: (any Error)? = nil
    var addServerError: (any Error)? = nil
    var addServerCalled = false

    func testConnection(
        url: String, username: String, password: String,
        customHeaders: [String: String]
    ) async throws {
        if let error = testConnectionError { throw error }
    }

    func addServer(
        displayName: String, baseURL: String, username: String,
        password: String, customHeaders: [String: String]
    ) async throws {
        addServerCalled = true
        if let error = addServerError { throw error }
    }

    // Unused stubs
    func removeServer(id: UUID) async throws {}
    func setActiveServer(id: UUID) async throws {}
    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {}
    func updateServer(id: UUID, displayName: String, baseURL: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func testConnection() async throws {}
    func loadPersistedState() async {}
    func makeSwiftSonicClient() async throws -> SwiftSonicClient { throw CassetteError.notImplemented }
    func activeCredentials() async throws -> ServerCredentials { throw CassetteError.notImplemented }
}

// MARK: - Suite

@Suite("OnboardingViewModel — testConnection error routing")
@MainActor
struct OnboardingViewModelTests {

    private func makeViewModel() -> OnboardingViewModel {
        makeViewModel(service: MockServerService())
    }

    private func makeViewModel(service: MockServerService) -> OnboardingViewModel {
        let vm = OnboardingViewModel(serverService: service)
        vm.serverURL = "https://music.example.com"
        vm.username = "admin"
        vm.password = "secret"
        return vm
    }

    // MARK: testConnection

    @Test func testConnection_success_clearsConnectionError() async {
        let vm = makeViewModel()
        await vm.testConnection()
        #expect(vm.connectionError == nil)
        #expect(vm.isLoading == false)
    }

    @Test func testConnection_cannotConnect_setsCannotConnectError() async {
        let service = MockServerService()
        service.testConnectionError = ConnectionTestError.cannotConnect
        let vm = makeViewModel(service: service)

        await vm.testConnection()

        #expect(vm.connectionError == .cannotConnect)
    }

    @Test func testConnection_authFailed_setsUnauthorizedError() async {
        let service = MockServerService()
        service.testConnectionError = ConnectionTestError.unauthorized
        let vm = makeViewModel(service: service)

        await vm.testConnection()

        #expect(vm.connectionError == .unauthorized)
    }

    @Test func testConnection_subsonicError_setsSubsonicError() async {
        let service = MockServerService()
        service.testConnectionError = ConnectionTestError.subsonicError(code: .generic, message: "Quota exceeded")
        let vm = makeViewModel(service: service)

        await vm.testConnection()

        #expect(vm.connectionError == .subsonicError(code: .generic, message: "Quota exceeded"))
    }

    @Test func testConnection_invalidURL_setsInvalidURLError() async {
        let service = MockServerService()
        service.testConnectionError = ConnectionTestError.invalidURL
        let vm = makeViewModel(service: service)

        await vm.testConnection()

        #expect(vm.connectionError == .invalidURL)
    }

    @Test func testConnection_unknownError_wrapsAsUnknown() async {
        let service = MockServerService()
        service.testConnectionError = CassetteError.notImplemented
        let vm = makeViewModel(service: service)

        await vm.testConnection()

        if case .unknown = vm.connectionError { } else {
            Issue.record("Expected .unknown, got \(String(describing: vm.connectionError))")
        }
    }

    @Test func testConnection_isLoadingFalseAfterCompletion() async {
        let service = MockServerService()
        service.testConnectionError = ConnectionTestError.cannotConnect
        let vm = makeViewModel(service: service)

        await vm.testConnection()

        #expect(vm.isLoading == false)
    }

    // MARK: addServer

    @Test func addServer_success_noConnectionError() async {
        let service = MockServerService()
        let vm = makeViewModel(service: service)

        await vm.addServer()

        #expect(vm.connectionError == nil)
        #expect(service.addServerCalled)
    }

    @Test func addServer_connectionFails_doesNotCallAddServer() async {
        let service = MockServerService()
        service.testConnectionError = ConnectionTestError.cannotConnect
        let vm = makeViewModel(service: service)

        await vm.addServer()

        #expect(vm.connectionError == .cannotConnect)
        #expect(!service.addServerCalled)
    }

    @Test func addServer_persistFails_setsUnknownError() async {
        let service = MockServerService()
        service.addServerError = CassetteError.keychainWriteFailed(-1)
        let vm = makeViewModel(service: service)

        await vm.addServer()

        if case .unknown = vm.connectionError { } else {
            Issue.record("Expected .unknown after persist failure, got \(String(describing: vm.connectionError))")
        }
        #expect(service.addServerCalled)
    }
}
