import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    var serverURL: String = ""
    var username: String = ""
    var password: String = ""
    /// Editable list of custom HTTP headers (key/value pairs).
    /// Includes Cloudflare Access tokens or any other reverse-proxy auth headers.
    var customHeaders: [(key: String, value: String)] = []
    var isLoading: Bool = false
    var connectionError: ConnectionTestError?

    /// Display name derived from the URL host, falling back to the raw URL string.
    var derivedDisplayName: String {
        URL(string: serverURL.trimmingCharacters(in: .whitespaces))?.host ?? serverURL
    }

    private let serverService: any ServerServiceProtocol

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    func testConnection() async {
        guard !isLoading else { return }
        connectionError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await serverService.testConnection(
                url: serverURL,
                username: username,
                password: password,
                customHeaders: headersDict()
            )
        } catch let error as ConnectionTestError {
            connectionError = error
        } catch {
            connectionError = .unknown(description: error.localizedDescription)
        }
    }

    func addServer() async {
        // TODO: implement in next commit
    }

    func addCustomHeader() {
        customHeaders.append((key: "", value: ""))
    }

    func removeCustomHeader(at index: Int) {
        guard customHeaders.indices.contains(index) else { return }
        customHeaders.remove(at: index)
    }

    // MARK: - Private

    private func headersDict() -> [String: String] {
        var dict: [String: String] = [:]
        for pair in customHeaders where !pair.key.isEmpty {
            dict[pair.key] = pair.value
        }
        return dict
    }
}
