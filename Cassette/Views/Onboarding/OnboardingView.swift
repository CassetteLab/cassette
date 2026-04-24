import SwiftUI

struct OnboardingView: View {
    @Environment(\.appContainer) private var container

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

            // TODO: implement in Étape 2 — open ServerFormView sheet
            // ServerFormView includes: URL, username, password, and
            // an "Advanced" disclosure group for custom HTTP headers (Cloudflare Access etc.)
            Button("Add Server") { }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}

#Preview {
    OnboardingView()
}
