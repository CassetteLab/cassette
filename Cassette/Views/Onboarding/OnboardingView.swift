import SwiftUI

struct OnboardingView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?
    @State private var showingServerForm = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hifispeaker.2")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Welcome to Cassette")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Connect to your Subsonic-compatible music server to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Add Server") {
                showingServerForm = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel == nil)
        }
        .padding(32)
        .onAppear {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
        }
        .sheet(isPresented: $showingServerForm) {
            if let viewModel {
                NavigationStack {
                    ServerFormView(viewModel: viewModel)
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
