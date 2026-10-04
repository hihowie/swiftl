import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: TranslatorViewModel
    @ObservedObject private var selection = SelectionTranslation.shared
    @State private var apiKeyInput: String = ""
    @State private var isEditing: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SwifTL Settings")
                .font(.headline)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Translation Service")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("Current service:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.isDeepLEnabled ? "DeepL API" : "Google Translate (free)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(viewModel.isDeepLEnabled ? .green : .blue)
                }
                
                Text("SwifTL uses Google Translate's free web API by default")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("You can also use DeepL for translation by providing your own API key below")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("DeepL API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if !viewModel.isDeepLEnabled || isEditing {
                    HStack {
                        SecureField("Enter your DeepL API key", text: $apiKeyInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(!isEditing && viewModel.isDeepLEnabled)

                        Button(viewModel.isDeepLEnabled ? "Save" : "Add") {
                            viewModel.saveDeepLAPIKey(apiKeyInput)
                            isEditing = false
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }
                    .padding(.bottom, 4)
                } else {
                    HStack {
                        Text("API key saved")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Spacer()
                        
                        Button("Edit") {
                            apiKeyInput = viewModel.deepLApiKey
                            isEditing = true
                        }
                        
                        Button("Remove") {
                            viewModel.removeDeepLAPIKey()
                            apiKeyInput = ""
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Text("Your API key is securely stored in macOS Keychain")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Your last selected languages are remembered automatically.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
            Text("Quick Translation").font(.subheadline.weight(.medium))
            Picker("Selected text shortcut", selection: $selection.shortcutChoice) {
                ForEach(SelectionTranslation.shortcutLabels.indices, id: \.self) { index in
                    Text(SelectionTranslation.shortcutLabels[index]).tag(index)
                }
            }
            Text("Select text in another app, then press the shortcut. Copy text and press ⌘⌥⇧T for clipboard translation.")
                .font(.caption).foregroundColor(.secondary)
            Toggle("Show a button after selecting text", isOn: $selection.showSelectionButton)
            Text("Requires Accessibility and an app that exposes selected text. Click the button to translate.")
                .font(.caption).foregroundColor(.secondary)
            Button("Enable Accessibility…") { selection.requestAccessibility() }
            if let error = selection.shortcutError { Text(error).font(.caption).foregroundColor(.red) }
            Spacer()
            HStack {
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                
                Spacer()
            }
            .padding(.bottom, 8)
        }
        .padding()
        .frame(width: 450, height: 600)
        .onAppear {
            apiKeyInput = viewModel.deepLApiKey
        }
    }
}

#Preview {
    SettingsView(viewModel: TranslatorViewModel())
}