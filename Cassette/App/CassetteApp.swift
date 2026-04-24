import SwiftUI

@main
struct CassetteApp: App {
    @State private var container: AppContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        .environment(\.appContainer, container)
                } else {
                    ProgressView()
                        .task {
                            guard container == nil else { return }
                            container = try? AppContainer()
                        }
                }
            }
        }
    }
}
