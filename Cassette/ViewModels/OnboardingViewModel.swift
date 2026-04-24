import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    var serverURL: String = ""
    var username: String = ""
    var password: String = ""
    var displayName: String = ""
    /// Editable list of custom HTTP headers (key/value pairs).
    /// Includes Cloudflare Access tokens or any other reverse-proxy auth headers.
    var customHeaders: [(key: String, value: String)] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let serverService: any ServerServiceProtocol

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    func addServer() async {
        // TODO: implement in Étape 2
    }

    func testConnection() async {
        // TODO: implement in Étape 2
    }

    func addCustomHeader() {
        customHeaders.append((key: "", value: ""))
    }

    func removeCustomHeader(at index: Int) {
        guard customHeaders.indices.contains(index) else { return }
        customHeaders.remove(at: index)
    }
}
