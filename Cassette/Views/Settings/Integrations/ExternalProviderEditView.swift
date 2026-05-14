// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ExternalProviderEditView: View {

    enum Mode {
        case new
        case edit(ExternalReleaseProvider)

        var title: String {
            switch self {
            case .new:  return "New Provider"
            case .edit: return "Edit Provider"
            }
        }

        var existingID: UUID? {
            if case .edit(let p) = self { return p.id }
            return nil
        }
    }

    let mode: Mode
    let onSave: (ExternalReleaseProvider) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var urlTemplate: String
    @State private var showingDeleteConfirm = false

    init(mode: Mode, onSave: @escaping (ExternalReleaseProvider) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _urlTemplate = State(initialValue: "")
        case .edit(let provider):
            _name = State(initialValue: provider.name)
            _urlTemplate = State(initialValue: provider.urlTemplate)
        }
    }

    // MARK: - Computed validation

    private var urlValidation: ExternalReleaseProvider.ValidationResult? {
        guard !urlTemplate.isEmpty else { return nil }
        return ExternalReleaseProvider.validate(urlTemplate: urlTemplate)
    }

    private var urlErrorMessage: String? {
        switch urlValidation {
        case .missingPlaceholder:  return "URL must contain a %s placeholder"
        case .multiplePlaceholders: return "Only one %s placeholder is allowed"
        case .invalidScheme:       return "URL must start with http:// or https://"
        case .malformed:           return "URL is malformed"
        case .valid, nil:          return nil
        }
    }

    private var previewText: String? {
        guard urlValidation == .valid else { return nil }
        let provider = ExternalReleaseProvider(name: name, urlTemplate: urlTemplate)
        return provider.buildURL(artistName: "Daft Punk", albumTitle: "Random Access Memories")?.absoluteString
    }

    private var canSave: Bool {
        ExternalReleaseProvider.validate(name: name) && urlValidation == .valid
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                if !name.isEmpty && !ExternalReleaseProvider.validate(name: name) {
                    Text("Name must be 1–50 characters")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Provider Name")
            }

            Section {
                TextField("https://example.com/search?q=%s", text: $urlTemplate, axis: .vertical)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                if let error = urlErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let preview = previewText {
                    Text("Example: \(preview)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } header: {
                Text("URL Template")
            } footer: {
                Text("Use %s as a placeholder — replaced by \"Artist Album\" when opening a release.")
            }

            if case .edit = mode, onDelete != nil {
                Section {
                    Button("Delete Provider", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(mode.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let provider = ExternalReleaseProvider(
                        id: mode.existingID ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        urlTemplate: urlTemplate.trimmingCharacters(in: .whitespaces)
                    )
                    onSave(provider)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .confirmationDialog(
            "Delete \"\(name)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
