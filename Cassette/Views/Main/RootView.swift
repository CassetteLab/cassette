import SwiftUI

struct RootView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        if let serverState = container?.serverState {
            if serverState.isLoadingPersistedState {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if serverState.activeServer != nil {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}
