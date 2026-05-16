// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class ExternalProvidersSettingsViewModel {
    private let store: ExternalProvidersStore
    private(set) var providers: [ExternalReleaseProvider] = []

    init(store: ExternalProvidersStore) {
        self.store = store
        self.providers = store.load()
    }

    func save(_ provider: ExternalReleaseProvider) {
        if providers.contains(where: { $0.id == provider.id }) {
            store.update(provider)
        } else {
            store.add(provider)
        }
        providers = store.load()
    }

    func delete(_ provider: ExternalReleaseProvider) {
        store.remove(id: provider.id)
        providers = store.load()
    }
}

// MARK: - View

struct ExternalProvidersSettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var vm: ExternalProvidersSettingsViewModel?
    @State private var showingAdd = false
    @State private var editingProvider: ExternalReleaseProvider?

    var body: some View {
        Group {
            if let vm {
                content(vm: vm)
            }
        }
        .navigationTitle("Open Releases In")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            if let vm {
                NavigationStack {
                    ExternalProviderEditView(mode: .new) { vm.save($0) }
                }
            }
        }
        .sheet(item: $editingProvider) { provider in
            if let vm {
                NavigationStack {
                    ExternalProviderEditView(mode: .edit(provider), onSave: { vm.save($0) }) {
                        vm.delete(provider)
                    }
                }
            }
        }
        .onAppear {
            if vm == nil, let store = container?.externalProvidersStore {
                vm = ExternalProvidersSettingsViewModel(store: store)
            }
        }
    }

    @ViewBuilder
    private func content(vm: ExternalProvidersSettingsViewModel) -> some View {
        if vm.providers.isEmpty {
            ContentUnavailableView {
                Label("No Providers Configured", systemImage: "arrow.up.right.square")
            } description: {
                Text("Add a custom search provider to open releases in your service of choice. Without a provider, releases fall back to ListenBrainz.")
            } actions: {
                Button("Add Provider") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                Section {
                    ForEach(vm.providers) { provider in
                        Button {
                            editingProvider = provider
                        } label: {
                            HStack {
                                Text(provider.name)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") { editingProvider = provider }
                            Button("Delete", role: .destructive) { vm.delete(provider) }
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { vm.delete(vm.providers[i]) }
                    }
                } footer: {
                    Text("URL template must contain %s — replaced by \"Artist Album\" when opening a release.")
                }

                Section {
                    Button("Add Provider") { showingAdd = true }
                }
            }
        }
    }
}
