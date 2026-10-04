import SwiftUI
import Vision
import AppKit
import Foundation
import Security

struct Language: Equatable, Hashable {
    let name: String
    let code: String
}

class TranslatorViewModel: ObservableObject {
    @Published var sourceLanguage: Language {
        didSet { if shouldSaveLanguagePreferences { saveLanguagePreferences() } }
    }
    @Published var targetLanguage: Language {
        didSet { if shouldSaveLanguagePreferences { saveLanguagePreferences() } }
    }
    @Published var automaticLanguage = true {
        didSet { if shouldSaveLanguagePreferences { preferences.set(automaticLanguage, forKey: "AutomaticLanguage") } }
    }
    @Published var bilingual = true {
        didSet {
            preferences.set(bilingual, forKey: "BilingualResults")
            displayPreferenceChanged?(bilingual)
        }
    }
    @Published var result: TranslationResult?
    @Published var showWordDetails = true
    @Published var completedParagraphs = 0
    @Published var totalParagraphs = 0
    @Published var inputText: String = ""
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSelectingArea: Bool = false
    @Published var deepLApiKey: String = ""
    @Published var isDeepLEnabled: Bool = false
    
    let availableLanguages: [Language] = [
        Language(name: "English", code: "en"),
        Language(name: "Spanish", code: "es"),
        Language(name: "French", code: "fr"),
        Language(name: "German", code: "de"),
        Language(name: "Italian", code: "it"),
        Language(name: "Portuguese (Brazil)", code: "pt-BR"),
        Language(name: "Portuguese (Portugal)", code: "pt-PT"),
        Language(name: "Russian", code: "ru"),
        Language(name: "Japanese", code: "ja"),
        Language(name: "Chinese (Simplified)", code: "zh-Hans"),
        Language(name: "Chinese (Traditional)", code: "zh-Hant"),
        Language(name: "Korean", code: "ko"),
        Language(name: "Arabic", code: "ar"),
        Language(name: "Dutch", code: "nl"),
        Language(name: "Hindi", code: "hi"),
        Language(name: "Indonesian", code: "id"),
        Language(name: "Thai", code: "th"),
        Language(name: "Turkish", code: "tr"),
        Language(name: "Ukrainian", code: "uk"),
        Language(name: "Vietnamese", code: "vi")
    ]
    
    // Window controller to manage the selection window's lifecycle
    private var windowController: NSWindowController?
    
    private let session: URLSession
    private let preferences: UserDefaults
    private var shouldSaveLanguagePreferences = false
    private var requestID = UUID()
    private var displayPreferenceChanged: ((Bool) -> Void)?
    private let languageDetector: (String) -> String?
    private let dictionaryLookup: (String) -> String?
    private let ocrQueue = DispatchQueue(label: "SwifTL.ocr", qos: .userInitiated)
    private let dictionaryQueue = DispatchQueue(label: "SwifTL.dictionary", qos: .userInitiated)

    init(session: URLSession = .shared, preferences: UserDefaults = .standard, persistLanguageChanges: Bool = true,
         languageDetector: @escaping (String) -> String? = TranslationText.detectLanguage,
         dictionaryLookup: @escaping (String) -> String? = TranslationText.definition) {
        self.languageDetector = languageDetector
        self.dictionaryLookup = dictionaryLookup
        self.session = session
        self.preferences = preferences
        // Default to Japanese and English, but will be overridden by saved preferences if they exist
        self.sourceLanguage = availableLanguages[8] // Default to Japanese
        self.targetLanguage = availableLanguages[0] // Default to English
        
        // Load DeepL API key from Keychain if available
        if let apiKey = loadDeepLAPIKey() {
            self.deepLApiKey = apiKey
            self.isDeepLEnabled = !apiKey.isEmpty
        }
        
        // Load saved language preferences
        loadLanguagePreferences()
        automaticLanguage = preferences.object(forKey: "AutomaticLanguage") as? Bool ?? true
        bilingual = preferences.object(forKey: "BilingualResults") as? Bool ?? true
        shouldSaveLanguagePreferences = persistLanguageChanges
    }
    
    // Save DeepL API key to Keychain
    func saveDeepLAPIKey(_ apiKey: String) {
        self.deepLApiKey = apiKey
        self.isDeepLEnabled = !apiKey.isEmpty
        
        // Create a query dictionary for the keychain
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.swiftl.DeepLAPIKey",
            kSecAttrAccount as String: "DeepLAPIKey",
            kSecValueData as String: apiKey.data(using: .utf8) ?? Data(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete any existing key before saving
        SecItemDelete(keychainQuery as CFDictionary)
        
        // Add the key to the keychain
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Error saving API key to Keychain
        }
    }
    
    // Load DeepL API key from Keychain
    private func loadDeepLAPIKey() -> String? {
        // Create a query dictionary to find the key
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.swiftl.DeepLAPIKey",
            kSecAttrAccount as String: "DeepLAPIKey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)
        
        // Check if the operation was successful
        if status == errSecSuccess {
            if let retrievedData = dataTypeRef as? Data,
               let apiKey = String(data: retrievedData, encoding: .utf8) {
                return apiKey
            }
        }
        
        return nil
    }
    
    // Remove DeepL API key from Keychain
    func removeDeepLAPIKey() {
        self.deepLApiKey = ""
        self.isDeepLEnabled = false
        
        // Create a query dictionary to find the key
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.swiftl.DeepLAPIKey",
            kSecAttrAccount as String: "DeepLAPIKey"
        ]
        
        // Delete the key from the keychain
        SecItemDelete(keychainQuery as CFDictionary)
    }
    
    // Save default language preferences to UserDefaults
    private func saveLanguagePreferences() {
        let defaults = preferences
        defaults.set(sourceLanguage.code, forKey: "DefaultSourceLanguageCode")
        defaults.set(targetLanguage.code, forKey: "DefaultTargetLanguageCode")
    }
    
    // Load default language preferences from UserDefaults
    private func loadLanguagePreferences() {
        let defaults = preferences
        
        if let sourceCode = defaults.string(forKey: "DefaultSourceLanguageCode"),
           let targetCode = defaults.string(forKey: "DefaultTargetLanguageCode") {
            
            // Find the languages that match the saved codes
            if let sourceLanguage = availableLanguages.first(where: { $0.code == sourceCode }),
               let targetLanguage = availableLanguages.first(where: { $0.code == targetCode }) {
                self.sourceLanguage = sourceLanguage
                self.targetLanguage = targetLanguage
            }
        }
    }
    
    func makeQuickTranslationModel() -> TranslatorViewModel {
        let quick = TranslatorViewModel(session: session, preferences: preferences, persistLanguageChanges: false, languageDetector: languageDetector, dictionaryLookup: dictionaryLookup)
        quick.automaticLanguage = automaticLanguage
        quick.bilingual = bilingual
        quick.displayPreferenceChanged = { [weak self] value in self?.bilingual = value }
        quick.sourceLanguage = sourceLanguage
        quick.targetLanguage = targetLanguage
        quick.deepLApiKey = deepLApiKey
        quick.isDeepLEnabled = isDeepLEnabled
        return quick
    }

    var selectedSourceCode: String {
        get { automaticLanguage ? "auto" : sourceLanguage.code }
        set {
            if newValue == "auto" { automaticLanguage = true }
            else if let language = availableLanguages.first(where: { $0.code == newValue }) {
                // Choosing the remembered manual source restores its remembered target.
                automaticLanguage = false
                sourceLanguage = language
            }
        }
    }

    var canSwap: Bool {
        !isTranslating && !isSelectingArea && (!automaticLanguage || (result?.succeeded == true && result?.source.map { availableLanguages.contains($0) } == true))
    }
    var canTranslate: Bool {
        !isTranslating && !isSelectingArea && (automaticLanguage || sourceLanguage != targetLanguage)
    }
    var inputHasChanged: Bool {
        guard let result = result, !result.fromScreenshot else { return false }
        return result.original != inputText
    }
    var automaticTarget: Language {
        if let result = result { return result.target }
        return availableLanguages.first { $0.code == "zh-Hans" }!
    }

    func swapLanguages() {
        guard canSwap else { return }
        if automaticLanguage, let result = result, let source = result.source {
            automaticLanguage = false
            sourceLanguage = result.target
            targetLanguage = source
        } else {
            let previousSource = sourceLanguage
            sourceLanguage = targetLanguage
            targetLanguage = previousSource
        }
    }

    func translateInput() {
        guard canTranslate, !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        beginTranslation(inputText, fromScreenshot: false)
    }

    func clearInput() {
        guard !isTranslating, !isSelectingArea else { return }
        inputText = ""
        resetResult()
    }

    private func resetResult() {
        requestID = UUID()
        result = nil
        translatedText = ""
        errorMessage = nil
        completedParagraphs = 0
        totalParagraphs = 0
        showWordDetails = true
    }

    private func language(for code: String?) -> Language? {
        guard let code = code else { return nil }
        let mapped = ["zh": "zh-Hans", "pt": "pt-PT" ][code] ?? code
        return availableLanguages.first(where: { $0.code == mapped }) ?? Language(name: code, code: code)
    }

    // Every request owns a snapshot and publishes the complete aligned result atomically.
    func beginTranslation(_ text: String, fromScreenshot: Bool) {
        resetResult()
        let id = requestID
        guard !TranslationText.paragraphs(text).isEmpty else {
            isTranslating = false
            errorMessage = "No text was recognized. Try again with a larger area."
            return
        }
        let automatic = automaticLanguage
        let source = automatic ? language(for: languageDetector(text)) : sourceLanguage
        let chinese = source?.code.hasPrefix("zh") == true
        let target = automatic ? availableLanguages.first(where: { $0.code == (chinese ? "en" : "zh-Hans") })! : targetLanguage
        let word = source?.code == "en" ? TranslationText.englishWord(text) : nil
        result = TranslationResult(original: text, source: source, target: target, automatic: automatic,
                                   fromScreenshot: fromScreenshot, word: word.map { WordDetails(word: $0) })
        isTranslating = true
        let blocks = TranslationText.paragraphs(text)
        totalParagraphs = blocks.count
        if let word = word {
            dictionaryQueue.async { [weak self] in
                guard let self = self else { return }
                let definition = self.dictionaryLookup(word)
                DispatchQueue.main.async {
                    guard self.requestID == id else { return }
                    self.result?.word?.definition = definition
                    self.result?.word?.isLookingUp = false
                }
            }
        }
        translateParagraphs(blocks, source: automatic ? nil : source, target: target, id: id) { [weak self] response in
            guard let self = self, self.requestID == id else { return }
            self.isTranslating = false
            switch response {
            case .success(let translations):
                self.result?.paragraphs = zip(blocks, translations).enumerated().map {
                    TranslationParagraph(id: $0.offset, original: $0.element.0, translation: $0.element.1)
                }
                self.result?.succeeded = true
                self.translatedText = self.result?.translation ?? ""
            case .failure(let error): self.errorMessage = error.localizedDescription
            }
        }
    }

    func adoptResult(from model: TranslatorViewModel) {
        guard !isTranslating, !isSelectingArea else { return }
        resetResult()
        automaticLanguage = model.automaticLanguage
        sourceLanguage = model.sourceLanguage
        targetLanguage = model.targetLanguage
        bilingual = model.bilingual
        inputText = model.result?.original ?? model.inputText
        result = model.result
        translatedText = model.translatedText
        errorMessage = model.errorMessage
        showWordDetails = model.showWordDetails
        // A lookup may still be finishing in the quick model. Resolve independently.
        if let word = result?.word, word.isLookingUp {
            let id = requestID
            dictionaryQueue.async { [weak self] in
                guard let self = self else { return }
                let definition = self.dictionaryLookup(word.word)
                DispatchQueue.main.async {
                    guard self.requestID == id else { return }
                    self.result?.word?.definition = definition
                    self.result?.word?.isLookingUp = false
                }
            }
        }
    }

    func cancelAreaSelection() {
        isSelectingArea = false
        windowController = nil
    }

    func startAreaSelection() {
        guard canTranslate else { return }
        isSelectingArea = true
        DispatchQueue.main.async {
            
            // If there's an existing window controller, close it
            if let windowController = self.windowController {
                windowController.close()
                self.windowController = nil
            }
            
            // Hide the app first
            NSApp.hide(nil)
            
            // Create the selection window
            let window = AreaSelectionWindow(viewModel: self)
            
            // Create a window controller to manage the window's lifecycle
            let controller = NSWindowController(window: window)
            self.windowController = controller
            
            // Show the window 
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            
            // Activate the app after a short delay to ensure proper window ordering
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func processSelectedArea(rect: NSRect) {
        guard !isTranslating else { return }
        windowController = nil
        isSelectingArea = false
        isTranslating = true
        resetResult()

        DispatchQueue.main.async {
            
            // Restore the main window after screenshot selection
            NSApp.unhide(nil)
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.showMainWindow()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        
        // Log the selected area for debugging
        
        // Ensure the rectangle is valid
        if rect.width <= 10 || rect.height <= 10 {
            DispatchQueue.main.async {
                self.isTranslating = false
                self.errorMessage = "Selected area is too small. Please select a larger area."
            }
            return
        }
        
        // Take a screenshot of the selected area
        if let image = captureScreenshot(of: rect) {
            // Extract text from the image
            recognizeText(in: image) { [weak self] recognizedText in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if let text = recognizedText, !text.isEmpty {
                        self.beginTranslation(text, fromScreenshot: true)
                    } else {
                        self.isTranslating = false
                        self.errorMessage = "No text was recognized in the selected area."
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isTranslating = false
                self.errorMessage = "Failed to capture screenshot."
            }
        }
    }
    
    private func captureScreenshot(of rect: NSRect) -> NSImage? {
        if let screenShot = CGWindowListCreateImage(
            rect, 
            .optionOnScreenOnly, 
            kCGNullWindowID, 
            [.boundsIgnoreFraming]
        ) {
            return NSImage(cgImage: screenShot, size: rect.size)
        }
        return nil
    }
    
    func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            
            completion(nil)
            return
        }
        
        // Get image dimensions for debugging
        let width = cgImage.width
        let height = cgImage.height
        
        
        // Don't process if the image is too small
        if width < 20 || height < 20 {
            
            completion(nil)
            return
        }
        
        // Get corresponding language code for Vision framework
        let languageHint = getVisionLanguageCode(for: sourceLanguage.code)
        
        
        // Create a text recognition request
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else {
                completion(nil)
                return
            }
            
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            
            
            if observations.isEmpty {
                
                completion(nil)
                return
            }
            
            // Create a simple string builder for the recognized text
            var recognizedString = ""
            var previousBottom: CGFloat = 1.0 // Vision coordinates are normalized [0,1]
            
            // Sort observations from top to bottom
            // Vision coordinates are normalized with the origin at the bottom-left
            let sortedObservations = observations.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            
            for observation in sortedObservations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                
                // Check if this is a new line (based on vertical position)
                let boundingBox = observation.boundingBox
                let top = boundingBox.maxY
                let lineThreshold = 0.01 // 1% of height
                
                if previousBottom - top > lineThreshold {
                    // This appears to be a new line
                    if !recognizedString.isEmpty {
                        recognizedString += "\n"
                    }
                } else if !recognizedString.isEmpty && !recognizedString.hasSuffix("\n") {
                    // Same line, add a space
                    recognizedString += " "
                }
                
                recognizedString += candidate.string
                previousBottom = boundingBox.minY
                
                
            }
            
            
            
            if recognizedString.isEmpty {
                completion(nil)
            } else {
                completion(recognizedString)
            }
        }
        
        // Configure the recognition request for optimal performance
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = automaticLanguage ? ["en-US", "zh-Hans", "zh-Hant"] : [languageHint]
        request.automaticallyDetectsLanguage = automaticLanguage
        
        // DO NOT set a specific region of interest - this forces it to use the actual image bounds
        // request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        
        // Use custom option to improve accuracy
        request.customWords = [] // No custom words needed
        request.minimumTextHeight = 0.01 // Allow smaller text to be recognized (1% of image height)
        request.revision = VNRecognizeTextRequestRevision3 // Supports automatic language detection on macOS 13+.
        
        // Create a handler to process the image
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        ocrQueue.async {
            do { try handler.perform([request]) }
            catch { completion(nil) }
        }
    }
    
    // Convert ISO language code to Vision framework language code
    private func getVisionLanguageCode(for isoCode: String) -> String {
        // Map ISO language codes to Vision framework language codes
        let languageMap: [String: String] = [
            "en": "en-US",
            "fr": "fr-FR",
            "it": "it-IT",
            "de": "de-DE",
            "es": "es-ES",
            "pt": "pt-BR",
            "zh-Hans": "zh-Hans",
            "ja": "ja-JP",
            "ko": "ko-KR",
            "ru": "ru-RU",
            "ar": "ar-SA"
        ]
        
        return languageMap[isoCode] ?? "en-US"
    }
    
    private struct TranslationFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func translateParagraphs(_ blocks: [String], source: Language?, target: Language, id: UUID,
                                     completion: @escaping (Result<[String], Error>) -> Void) {
        let deepL = isDeepLEnabled && !deepLApiKey.isEmpty
        let apiKey = deepLApiKey
        var outputs: [String] = []
        func next(_ index: Int) {
            guard self.requestID == id else { return }
            if index == blocks.count { completion(.success(outputs)); return }
            // DeepL allows 50 texts and a 128 KiB request body. Keep batches below both limits.
            var batch = [blocks[index]]
            if deepL {
                while index + batch.count < blocks.count && batch.count < 50 {
                    let proposed = batch + [blocks[index + batch.count]]
                    guard let body = try? JSONSerialization.data(withJSONObject: self.deepLPayload(proposed, source: source, target: target)), body.count < 120_000 else { break }
                    batch = proposed
                }
            }
            let requestTexts = batch
            let request: URLRequest
            do { request = try deepL ? self.deepLRequest(batch, source: source, target: target, key: apiKey) : self.googleRequest(batch[0], source: source, target: target) }
            catch { completion(.failure(error)); return }
            self.session.dataTask(with: request) { data, response, error in
                let parsed: Result<[String], Error>
                do {
                    if let error = error { throw TranslationFailure(message: "Network error: \(error.localizedDescription)") }
                    guard let http = response as? HTTPURLResponse else { throw TranslationFailure(message: "No response received. Try again.") }
                    guard http.statusCode == 200 else { throw TranslationFailure(message: "\(deepL ? "DeepL API" : "Translation API") Error: HTTP \(http.statusCode). Try again.") }
                    guard let data = data else { throw TranslationFailure(message: "No translation data received.") }
                    parsed = .success(try self.parseResponse(data, deepL: deepL, count: requestTexts.count))
                } catch { parsed = .failure(error) }
                DispatchQueue.main.async {
                    guard self.requestID == id else { return }
                    switch parsed {
                    case .failure: completion(parsed)
                    case .success(let values):
                        outputs += values
                        self.completedParagraphs = outputs.count
                        next(index + requestTexts.count)
                    }
                }
            }.resume()
        }
        next(0)
    }

    private func deepLPayload(_ texts: [String], source: Language?, target: Language) -> [String: Any] {
        var body: [String: Any] = ["text": texts, "target_lang": convertToDeepLLanguageCode(target.code)]
        if let source = source { body["source_lang"] = source.code.hasPrefix("pt") ? "PT" : convertToDeepLLanguageCode(source.code) }
        return body
    }

    private func deepLRequest(_ texts: [String], source: Language?, target: Language, key: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api-free.deepl.com/v2/translate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let body = try JSONSerialization.data(withJSONObject: deepLPayload(texts, source: source, target: target))
        guard body.count < 128 * 1024 else { throw TranslationFailure(message: "A paragraph is too long for DeepL. Split it into smaller paragraphs.") }
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func convertToDeepLLanguageCode(_ code: String) -> String {
        ["en": "EN", "es": "ES", "fr": "FR", "de": "DE", "it": "IT", "ja": "JA", "ko": "KO",
         "pt-BR": "PT-BR", "pt-PT": "PT-PT", "ru": "RU", "zh-Hans": "ZH", "zh-Hant": "ZH",
         "nl": "NL", "pl": "PL", "tr": "TR", "uk": "UK", "ar": "AR", "hi": "HI"][code] ?? code.uppercased()
    }

    private func googleRequest(_ text: String, source: Language?, target: Language) throws -> URLRequest {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source?.code ?? "auto"),
            URLQueryItem(name: "tl", value: target.code), URLQueryItem(name: "dt", value: "t"), URLQueryItem(name: "q", value: text)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw TranslationFailure(message: "Couldn't create the translation request.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func parseResponse(_ data: Data, deepL: Bool, count: Int) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: data)
        if deepL, let object = json as? [String: Any], let entries = object["translations"] as? [[String: Any]], entries.count == count {
            let texts = entries.compactMap { $0["text"] as? String }
            if texts.count == count && texts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return texts }
        } else if !deepL, let array = json as? [Any], let segments = array.first as? [[Any]], !segments.isEmpty {
            let texts = segments.compactMap { $0.first as? String }
            let text = texts.joined()
            if texts.count == segments.count && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [text] }
        }
        throw TranslationFailure(message: "Couldn't extract aligned translations from the response. Try again.")
    }
}
