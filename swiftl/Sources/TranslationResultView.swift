import SwiftUI
import AppKit

struct TranslationResultView: View {
    @ObservedObject var model: TranslatorViewModel
    @ObservedObject private var speech = SelectionTranslation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result = model.result {
                Text(result.direction).font(.caption).foregroundColor(.secondary)
                if result.automatic && result.source == nil {
                    Text("Language could not be identified. Choose From manually if needed.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if model.inputHasChanged {
                    Text("Input changed. Translate again to update this result.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if model.isTranslating {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.totalParagraphs > 0 ? "Translating \(model.completedParagraphs)/\(model.totalParagraphs) paragraphs…" : "Recognizing text…")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }
            if let word = model.result?.word, model.showWordDetails {
                HStack {
                    Text(word.word).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Spacer()
                    Button(speech.isSpeaking ? "Stop" : "Pronounce") { speech.speak(word.word, language: "en") }
                        .accessibilityLabel("Pronounce original word")
                    Button("Text mode") { model.showWordDetails = false }
                }
            } else {
                Picker("Result display", selection: $model.bilingual) {
                    Text("Bilingual").tag(true)
                    Text("Translation only").tag(false)
                }.pickerStyle(.segmented).labelsHidden()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let word = model.result?.word, model.showWordDetails {
                        if !model.translatedText.isEmpty {
                            Text(model.translatedText).font(.headline).textSelection(.enabled)
                        }
                        Divider()
                        Text("Local dictionary").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        if word.isLookingUp {
                            Text("Looking up definition…").foregroundColor(.secondary)
                        } else if let definition = word.definition {
                            Text(definition).textSelection(.enabled)
                        } else {
                            Text("No local definition is available. Enable an English dictionary in Dictionary settings.")
                                .foregroundColor(.secondary)
                        }
                        Button("Open Dictionary") {
                            var components = URLComponents()
                            components.scheme = "dict"
                            components.host = word.word
                            if let url = components.url { NSWorkspace.shared.open(url) }
                        }
                    } else if let result = model.result, result.succeeded {
                        ForEach(result.paragraphs) { paragraph in
                            VStack(alignment: .leading, spacing: 8) {
                                if model.bilingual {
                                    Text(paragraph.original).foregroundColor(.secondary).textSelection(.enabled)
                                }
                                Text(paragraph.translation).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if paragraph.id != result.paragraphs.last?.id { Divider() }
                        }
                    } else {
                        Text(model.isTranslating ? "Your translation is on its way…" : "Your translation will appear here.")
                            .foregroundColor(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
