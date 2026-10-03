import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: TranslatorViewModel
    @State private var showingSettings = false
    @State private var showCopyFeedback = false
    @State private var showSaveDefaultsFeedback = false

    private var isBusy: Bool { viewModel.isTranslating || viewModel.isSelectingArea }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SwifTL").font(.title2.weight(.semibold))
                Spacer()
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .disabled(isBusy)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From").font(.caption).foregroundColor(.secondary)
                    Picker("Source language", selection: $viewModel.sourceLanguage) {
                        ForEach(viewModel.availableLanguages, id: \.code) { language in
                            Text(language.name).tag(language)
                        }
                    }.labelsHidden()
                }
                Image(systemName: "arrow.right").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("To").font(.caption).foregroundColor(.secondary)
                    Picker("Target language", selection: $viewModel.targetLanguage) {
                        ForEach(viewModel.availableLanguages, id: \.code) { language in
                            Text(language.name).tag(language)
                        }
                    }.labelsHidden()
                }
            }
            .disabled(isBusy)
            HStack {
                Button("Set as Default") {
                    viewModel.saveLanguagePreferences()
                    showSaveDefaultsFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showSaveDefaultsFeedback = false
                    }
                }
                .disabled(isBusy || viewModel.sourceLanguage == viewModel.targetLanguage)
                .font(.caption)
                if showSaveDefaultsFeedback { Text("Saved!").font(.caption).foregroundColor(.green) }
            }
            Text("Original text").font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .accessibilityLabel("Text to translate")
                    .disabled(isBusy)
                if viewModel.inputText.isEmpty {
                    Text("Type or paste text to translate…")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 140)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            HStack {
                Button("Translate") { viewModel.translateInput() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.sourceLanguage == viewModel.targetLanguage)
                Button("Clear") { viewModel.clearInput() }
                    .disabled(isBusy || (viewModel.inputText.isEmpty && viewModel.translatedText.isEmpty && viewModel.errorMessage == nil))
                Spacer()
                Button { viewModel.startAreaSelection() } label: {
                    Label("Screenshot", systemImage: "viewfinder")
                }
                .disabled(isBusy || viewModel.sourceLanguage == viewModel.targetLanguage)
            }
            if viewModel.sourceLanguage == viewModel.targetLanguage {
                Text("Choose different source and target languages.").font(.caption).foregroundColor(.red)
            }
            if viewModel.isTranslating {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Translating…").font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).lineLimit(3)
            }
            Divider()
            HStack {
                Text("Translation").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.translatedText, forType: .string)
                    showCopyFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopyFeedback = false }
                } label: {
                    Label(showCopyFeedback ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.translatedText.isEmpty || isBusy)
            }
            ScrollView {
                Text(viewModel.translatedText.isEmpty ? "Your translation will appear here." : viewModel.translatedText)
                    .foregroundColor(viewModel.translatedText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(width: 400, height: 600)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}
