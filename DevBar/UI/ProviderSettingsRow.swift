import SwiftUI

struct ProviderSettingsRow: View {
    let provider: any ToolbarProvider
    @ObservedObject var store: ToolbarStore

    @State private var values: [String: String] = [:]
    @State private var isTesting = false
    @State private var testResult: TestResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(provider.displayName, systemImage: provider.iconSystemName)
                    .font(.headline)
                    .foregroundStyle(DevBarTheme.primaryText)
                Spacer()
                Toggle("Enabled", isOn: enabledBinding)
                    .toggleStyle(.switch)
            }

            if store.isEnabled(provider.id) {
                ForEach(provider.credentialFields) { field in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Text(field.label).font(.caption.weight(.semibold))
                            if field.isRequired {
                                Text("Required").font(.caption2).foregroundStyle(DevBarTheme.secondaryText)
                            } else {
                                Text("Optional").font(.caption2).foregroundStyle(DevBarTheme.tertiaryText)
                            }
                        }
                        if field.isSecret {
                            SecureField(field.placeholder, text: valueBinding(for: field.key))
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField(field.placeholder, text: valueBinding(for: field.key))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                HStack {
                    if let testResult {
                        Label(testResult.message, systemImage: testResult.icon)
                            .font(.caption)
                            .foregroundStyle(testResult.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                    }
                    Spacer()
                    Button("Save securely") { saveCredentials() }
                        .help("Save this provider's credentials in Keychain")
                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Testing connection")
                        } else {
                            Text("Test Connection")
                        }
                    }
                        .disabled(isTesting || missingRequiredValue)
                        .help(missingRequiredValue ? "Enter all required values first" : "Verify these credentials with \(provider.displayName)")
                }
            }
        }
        .padding(16)
        .devBarCard()
        .onAppear { loadCredentials() }
        .accessibilityElement(children: .contain)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(provider.id) },
            set: { store.setEnabled($0, providerId: provider.id) }
        )
    }

    private var missingRequiredValue: Bool {
        provider.credentialFields.contains { $0.isRequired && values[$0.key, default: ""].isEmpty }
    }

    private func valueBinding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key, default: ""] },
            set: { values[key] = $0; testResult = nil }
        )
    }

    private func loadCredentials() {
        values = CredentialStore.credentials(for: provider)
    }

    private func saveCredentials() {
        do {
            for field in provider.credentialFields {
                try CredentialStore.save(values[field.key, default: ""], key: field.key, providerId: provider.id)
            }
            testResult = .success("Saved securely")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    private func testConnection() {
        saveCredentials()
        guard testResult?.isFailure != true else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                let items = try await provider.fetchItems(credentials: values)
                testResult = .success("Connected · \(items.count) items")
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }
}

private struct TestResult {
    let message: String
    let isFailure: Bool

    static func success(_ message: String) -> Self { .init(message: message, isFailure: false) }
    static func failure(_ message: String) -> Self { .init(message: message, isFailure: true) }

    var icon: String { isFailure ? "xmark.circle.fill" : "checkmark.circle.fill" }
    var color: Color { isFailure ? DevBarTheme.failed : DevBarTheme.healthy }
}
