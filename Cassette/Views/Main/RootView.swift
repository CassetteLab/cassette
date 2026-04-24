import SwiftUI

struct RootView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        if container?.serverState.activeServer != nil {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}
