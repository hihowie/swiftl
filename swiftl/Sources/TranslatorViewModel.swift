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

    init(session: URLSession = .shared, preferences: UserDefaults = .standard, persistLanguageChanges: Bool = true) {
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
        let quick = TranslatorViewModel(session: session, preferences: preferences, persistLanguageChanges: false)
        quick.sourceLanguage = sourceLanguage
        quick.targetLanguage = targetLanguage
        quick.deepLApiKey = deepLApiKey
        quick.isDeepLEnabled = isDeepLEnabled
        return quick
    }

    func swapLanguages() {
        guard !isTranslating, !isSelectingArea else { return }
        let previousSource = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = previousSource
    }

    var canTranslate: Bool {
        !isTranslating && !isSelectingArea && sourceLanguage != targetLanguage
    }

    func translateInput() {
        guard canTranslate, !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTranslating = true
        translatedText = ""
        errorMessage = nil
        translateText(inputText) { [weak self] result in
            self?.finishTranslation(result)
        }
    }

    func clearInput() {
        guard !isTranslating, !isSelectingArea else { return }
        inputText = ""
        translatedText = ""
        errorMessage = nil
    }

    private func finishTranslation(_ result: String?) {
        isTranslating = false
        if let result = result {
            translatedText = result
        } else if errorMessage == nil {
            errorMessage = "Translation failed. Check your connection and try again."
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
        errorMessage = nil
        translatedText = ""

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
                        self.translateText(text) { result in
                            self.finishTranslation(result)
                        }
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
    
    private func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
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
        request.recognitionLanguages = [languageHint]
        
        // DO NOT set a specific region of interest - this forces it to use the actual image bounds
        // request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        
        // Use custom option to improve accuracy
        request.customWords = [] // No custom words needed
        request.minimumTextHeight = 0.01 // Allow smaller text to be recognized (1% of image height)
        request.revision = VNRecognizeTextRequestRevision2 // Use latest revision
        
        // Create a handler to process the image
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            
            completion(nil)
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
    
    private func translateText(_ text: String, completion: @escaping (String?) -> Void) {
        guard !text.isEmpty else {
            completion("")
            return
        }
        
        // Check if DeepL is enabled and we have an API key
        if isDeepLEnabled && !deepLApiKey.isEmpty {
            translateWithDeepL(text, completion: completion)
        } else {
            translateWithGoogleTranslate(text, completion: completion)
        }
    }
    
    private func translateWithDeepL(_ text: String, completion: @escaping (String?) -> Void) {
        let from = convertToDeepLLanguageCode(sourceLanguage.code)
        let to = convertToDeepLLanguageCode(targetLanguage.code)
        var request = URLRequest(url: URL(string: "https://api-free.deepl.com/v2/translate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": [text], "source_lang": from, "target_lang": to
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(deepLApiKey)", forHTTPHeaderField: "Authorization")

        // Make the request
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    completion(nil)
                }
                return
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                
                
                if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async {
                        self.errorMessage = "DeepL API Error: HTTP \(httpResponse.statusCode)"
                        completion(nil)
                    }
                    return
                }
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No data received from DeepL API"
                    completion(nil)
                }
                return
            }
            
            do {
                // Parse the DeepL API response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let translations = json["translations"] as? [[String: Any]],
                   let firstTranslation = translations.first,
                   let translatedText = firstTranslation["text"] as? String {
                    
                    
                    
                    DispatchQueue.main.async {
                        completion(translatedText)
                    }
                    return
                }
                
                // Failed to parse as expected
                
                DispatchQueue.main.async {
                    self.errorMessage = "Couldn't extract translation from DeepL response"
                    completion(nil)
                }
            } catch {
                
                DispatchQueue.main.async {
                    self.errorMessage = "Error processing DeepL translation result"
                    completion(nil)
                }
            }
        }
        
        task.resume()
    }
    
    private func convertToDeepLLanguageCode(_ code: String) -> String {
        // Map language codes to DeepL supported codes
        // DeepL has different format requirements for some languages
        let languageMap: [String: String] = [
            "en": "EN",
            "es": "ES",
            "fr": "FR",
            "de": "DE",
            "it": "IT",
            "ja": "JA",
            "ko": "KO",
            "pt-BR": "PT-BR",
            "pt-PT": "PT-PT",
            "ru": "RU",
            "zh-Hans": "ZH", // Simplified Chinese
            "zh-Hant": "ZH", // Traditional Chinese
            "nl": "NL",
            "pl": "PL",
            "tr": "TR",
            "uk": "UK",
            "ar": "AR",
            "hi": "HI"
        ]
        
        return languageMap[code] ?? "EN"
    }
    
    private func translateWithGoogleTranslate(_ text: String, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sourceLanguage.code),
            URLQueryItem(name: "tl", value: targetLanguage.code),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        // Some servers decode query strings as form data, where a literal + means space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            errorMessage = "Couldn't create the translation request."
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Make the request
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    completion(nil)
                }
                return
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                
                
                if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async {
                        self.errorMessage = "API Error: HTTP \(httpResponse.statusCode)"
                        completion(nil)
                    }
                    return
                }
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No data received from translation API"
                    completion(nil)
                }
                return
            }
            
            do {
                // Parse the Google Translate free API response format
                // The format is an array of arrays, with the first sub-array containing translation segments
                if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                   let translations = json.first as? [[Any]] {
                    
                    // Concatenate all translation segments to get the full translated text
                    var completeTranslation = ""
                    
                    for translationPart in translations {
                        if let translatedText = translationPart.first as? String {
                            completeTranslation += translatedText
                        }
                    }
                    
                    if !completeTranslation.isEmpty {
                        
                        
                        DispatchQueue.main.async {
                            completion(completeTranslation)
                        }
                        return
                    }
                }
                
                // Failed to parse as expected
                
                DispatchQueue.main.async {
                    self.errorMessage = "Couldn't extract translation from response"
                    completion(nil)
                }
            } catch {
                
                DispatchQueue.main.async {
                    self.errorMessage = "Error processing translation result"
                    completion(nil)
                }
            }
        }
        
        task.resume()
    }
}
