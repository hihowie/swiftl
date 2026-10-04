import AppKit
import Foundation
import CoreText

// This executable checks the production view model without opening windows.
class AppDelegate: NSObject, NSApplicationDelegate {
    func showMainWindow() {}
}
class AreaSelectionWindow: NSWindow {
    init(viewModel: TranslatorViewModel) {
        super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    }
}

final class TranslationProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var responseData = Data()
    static var status = 200
    static var failure: Error?
    static var responder: ((URLRequest) -> (Data, Int))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
        } else {
            let response = Self.responder?(request) ?? (Self.responseData, Self.status)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.1, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.0)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main struct TranslationChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        print("PASS: \(name)")
    }
    static func wait(_ model: TranslatorViewModel) {
        let end = Date().addingTimeInterval(35)
        while model.isTranslating && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        check(!model.isTranslating, "request completed")
    }
    static func checkSelectionSearch() {
        func search(_ selections: [Int: String], secure: Set<Int> = [], children: [Int: [Int]] = [0: [1], 1: [2]], parents: [Int: Int] = [2: 1, 1: 0], webAreas: Set<Int> = [1]) -> SelectionSearch<Int> {
            SelectionSearch(selectedText: { selections[$0] }, parent: { parents[$0] }, children: { children[$0] ?? [] }, isWebArea: { webAreas.contains($0) }, isSecure: { secure.contains($0) }, canContinue: { true })
        }
        check(search([1: "Across two paragraphs"]).find(focused: 2, hit: nil, window: 0)?.1 == "Across two paragraphs", "Chrome group focus resolves selection on parent web area")
        check(search([1: "Complete selection", 2: "fragment"]).find(focused: nil, hit: 2, window: 0)?.1 == "Complete selection", "pointer hit prefers complete web-area selection")
        check(search([1: "Page selection"]).find(focused: 3, hit: nil, window: 0)?.1 == "Page selection", "active-window web area resolves missing focus selection")
        check(search([2: "secret"], secure: [2]).find(focused: 2, hit: nil, window: 0) == nil, "secure focused field blocks all selection search")
        check(search([1: "   \n"]).find(focused: 2, hit: nil, window: 0) == nil, "whitespace selection does not trigger a button")
        check(search([3: "Unrelated toolbar selection"], children: [0: [3]], webAreas: []).find(focused: nil, hit: nil, window: 0) == nil, "window scan does not use unrelated toolbar selections")
        var visits = 0
        let bounded = SelectionSearch<Int>(selectedText: { _ in nil }, parent: { _ in nil }, children: { node in visits += 1; return [node] }, isWebArea: { _ in true }, isSecure: { _ in false }, canContinue: { true }, limit: 12)
        check(bounded.find(focused: nil, hit: nil, window: 0) == nil && visits <= 12, "cyclic accessibility children are bounded")
    }
    static func body(_ request: URLRequest) -> [String: Any] {
        if let data = request.httpBody { return try! JSONSerialization.jsonObject(with: data) as! [String: Any] }
        let stream = request.httpBodyStream!
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        var collected = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            collected.append(contentsOf: bytes.prefix(count))
        }
        return try! JSONSerialization.jsonObject(with: collected) as! [String: Any]
    }
    static func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
    static func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(condition(), "asynchronous lookup completed")
    }
    static func checkReadingFeatures() {
        let suite = "SwifTL.ReadingChecks.\(UUID())"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        prefs.set("ja", forKey: "DefaultSourceLanguageCode")
        prefs.set("en", forKey: "DefaultTargetLanguageCode")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = TranslatorViewModel(session: session, preferences: prefs, dictionaryLookup: { "Definition of \($0)" })
        model.isDeepLEnabled = false
        check(model.automaticLanguage && model.bilingual && model.sourceLanguage.code == "ja" && model.targetLanguage.code == "en", "upgrade defaults to Auto without overwriting manual pair")
        model.selectedSourceCode = "ja"
        check(!model.automaticLanguage && model.targetLanguage.code == "en", "manual mode restores remembered target")
        model.selectedSourceCode = "auto"
        check(!model.canSwap, "Auto swap unavailable before successful detection")
        for (text, expected) in [("你好，这是一个中文翻译测试。", "zh-Hans"), ("這是一段繁體中文，用來測試翻譯軟體。", "zh-Hant"), ("これは日本語の文章で、翻訳機能をテストしています。", "ja"), ("This is an English sentence for testing language detection.", "en")] {
            check(TranslationText.detectLanguage(text) == expected, "local language detection: \(expected)")
        }
        for word in ["Hello", "don't", "mother-in-law", "“hello!”"] { check(TranslationText.englishWord(word) != nil, "word candidate: \(word)") }
        for text in ["two words", "123", "hello42", "你好", "https://example.com", "example.com", "test@example.com"] { check(TranslationText.englishWord(text) == nil, "not a word: \(text)") }
        check(TranslationText.paragraphs("One\r\nline\r\n\r\n \t\r\nTwo\r\n\r\n") == ["One\nline", "Two"], "paragraph boundaries preserve internal newlines and normalize CRLF")
        TranslationProtocol.responder = { request in
            let text = query(request, "q")!
            return (try! JSONSerialization.data(withJSONObject: [[["Translated: " + text, text]], NSNull(), "en"]), 200)
        }
        model.inputText = "First paragraph.\nWithin first.\n\nA&B + C? 😀"
        let original = model.inputText
        model.translateInput()
        model.inputText = "edited while pending"
        model.translateInput()
        wait(model)
        check(model.result?.source?.code == "en" && model.result?.target.code == "zh-Hans", "Auto English routes to Chinese")
        check(model.result?.original == original && model.inputHasChanged && model.result?.paragraphs.count == 2, "editing keeps submitted snapshot and aligned paragraphs")
        check(model.result?.paragraphs[1].original == "A&B + C? 😀" && model.translatedText.contains("\n\n"), "translation-only copy retains paragraph order")
        check(TranslationProtocol.requests.count == 2 && TranslationProtocol.requests.allSatisfy { query($0, "sl") == "auto" && query($0, "tl") == "zh-Hans" }, "Google sequential paragraph requests share auto direction")
        model.swapLanguages()
        check(!model.automaticLanguage && model.sourceLanguage.code == "zh-Hans" && model.targetLanguage.code == "en", "Auto swap enters manual reversed effective direction")
        model.automaticLanguage = true
        model.inputText = "你好，这是中文。"
        model.translateInput(); wait(model)
        check(model.result?.target.code == "en" && query(TranslationProtocol.requests.last!, "tl") == "en", "Auto Chinese routes to English")
        check(model.sourceLanguage.code == "zh-Hans" && model.targetLanguage.code == "en", "automatic result does not overwrite manual pair")
        model.bilingual = false
        let reloaded = TranslatorViewModel(session: session, preferences: prefs)
        check(reloaded.automaticLanguage && !reloaded.bilingual, "mode and display preference reload")
        let unknown = TranslatorViewModel(session: session, preferences: prefs, languageDetector: { _ in nil })
        unknown.isDeepLEnabled = false
        unknown.inputText = "😀"
        unknown.translateInput(); wait(unknown)
        check(unknown.result?.source == nil && unknown.result?.target.code == "zh-Hans" && !unknown.canSwap, "unknown language uses Chinese and cannot swap")
        model.inputText = "  Hello!  "
        model.translateInput(); wait(model)
        waitUntil { model.result?.word?.isLookingUp == false }
        check(model.result?.word?.word == "Hello" && model.result?.word?.definition == "Definition of Hello", "local dictionary attaches independently to word")
        model.showWordDetails = false
        let quick = model.makeQuickTranslationModel()
        check(quick.automaticLanguage && !quick.bilingual, "quick model copies automatic and bilingual settings")
        quick.inputText = "hello"
        quick.translateInput(); wait(quick)
        model.adoptResult(from: quick)
        waitUntil { model.result?.word?.isLookingUp == false }
        check(model.result == quick.result && model.translatedText == quick.translatedText, "opening main window transfers complete result")
        quick.bilingual = true
        check(prefs.bool(forKey: "BilingualResults") && model.bilingual, "quick display changes persist and update the main model")
        TranslationProtocol.failure = URLError(.notConnectedToInternet)
        model.inputText = "offline"
        model.translateInput(); wait(model)
        waitUntil { model.result?.word?.isLookingUp == false }
        check(model.errorMessage != nil && model.result?.word?.definition == "Definition of offline" && model.translatedText.isEmpty, "network failure preserves independent local definition")
        TranslationProtocol.failure = nil
        let noDictionary = TranslatorViewModel(session: session, preferences: prefs, dictionaryLookup: { _ in nil })
        noDictionary.isDeepLEnabled = false
        noDictionary.inputText = "hello"
        noDictionary.translateInput(); wait(noDictionary)
        waitUntil { noDictionary.result?.word?.isLookingUp == false }
        check(noDictionary.result?.word?.definition == nil && !noDictionary.translatedText.isEmpty, "missing local dictionary does not fail translation")
        var calls = 0
        TranslationProtocol.responder = { request in
            calls += 1
            return calls == 2 ? (Data(), 429) : (try! JSONSerialization.data(withJSONObject: [[["First translated", query(request, "q")!]]]), 200)
        }
        model.inputText = "First.\n\nSecond."
        model.translateInput(); wait(model)
        check(model.translatedText.isEmpty && model.result?.paragraphs.isEmpty == true && model.errorMessage?.contains("429") == true, "second paragraph failure publishes no partial result")
        calls = 0
        TranslationProtocol.responder = { _ in (Data(#"[[["Retry success",null]]]"#.utf8), 200) }
        model.translateInput(); wait(model)
        check(model.result?.paragraphs.count == 2 && model.errorMessage == nil, "whole result retries after paragraph failure")
        // Exercise the production Vision OCR without needing screen-recording permission.
        let bitmap = CGContext(data: nil, width: 1000, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1000, height: 160))
        bitmap.textPosition = CGPoint(x: 30, y: 60)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello world.", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]))
        CTLineDraw(line, bitmap)
        let image = NSImage(cgImage: bitmap.makeImage()!, size: NSSize(width: 1000, height: 160))
        var recognized: String?
        model.automaticLanguage = true
        var ocrFinished = false
        model.recognizeText(in: image) { value in DispatchQueue.main.async { recognized = value; ocrFinished = true } }
        waitUntil(timeout: 35) { ocrFinished }
        check(recognized?.contains("Hello world") == true, "automatic Vision OCR reads a synthetic English image")
        model.automaticLanguage = false
        model.sourceLanguage = Language(name: "English", code: "en")
        recognized = nil
        ocrFinished = false
        model.recognizeText(in: image) { value in DispatchQueue.main.async { recognized = value; ocrFinished = true } }
        waitUntil(timeout: 35) { ocrFinished }
        check(recognized?.contains("Hello world") == true, "manual Vision OCR keeps selected language hint")
        model.automaticLanguage = true
        let manualInput = model.inputText
        model.beginTranslation("Screenshot text.", fromScreenshot: true); wait(model)
        check(model.inputText == manualInput && model.result?.original == "Screenshot text." && !model.inputHasChanged, "screenshot snapshot does not overwrite manual input")
        model.isDeepLEnabled = true
        model.deepLApiKey = "test-only-key"
        TranslationProtocol.requests = []
        TranslationProtocol.responder = { request in
            let payload = body(request)
            let texts = payload["text"] as! [String]
            return (try! JSONSerialization.data(withJSONObject: ["translations": texts.map { ["text": "DeepL: " + $0] }]), 200)
        }
        model.inputText = (1...51).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        model.translateInput(); wait(model)
        check(TranslationProtocol.requests.count == 2 && model.result?.paragraphs.count == 51 && model.completedParagraphs == 51, "DeepL splits over 50 texts into ordered batches")
        check(body(TranslationProtocol.requests[0])["source_lang"] == nil, "DeepL auto omits source_lang")
        model.automaticLanguage = false
        model.sourceLanguage = Language(name: "English", code: "en")
        model.targetLanguage = Language(name: "Chinese (Simplified)", code: "zh-Hans")
        model.inputText = "One.\n\nTwo."
        TranslationProtocol.responder = { _ in (Data(#"{"translations":[{"text":"only one"}]}"#.utf8), 200) }
        model.translateInput(); wait(model)
        check(model.errorMessage != nil && model.translatedText.isEmpty, "DeepL count mismatch fails without incorrect alignment")
        check(body(TranslationProtocol.requests.last!)["source_lang"] as? String == "EN", "DeepL manual source preserved")
        // A lookup started for a previous result cannot repopulate a cleared result.
        let gate = DispatchSemaphore(value: 0)
        let stale = TranslatorViewModel(session: session, preferences: prefs, dictionaryLookup: { _ in gate.wait(); return "late definition" })
        stale.isDeepLEnabled = false
        stale.inputText = "hello"
        TranslationProtocol.responder = { _ in (Data(#"[[["你好",null]]]"#.utf8), 200) }
        stale.translateInput(); wait(stale)
        stale.clearInput()
        gate.signal()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(stale.result == nil && stale.translatedText.isEmpty, "late dictionary response cannot overwrite clear")
        TranslationProtocol.responder = nil
        TranslationProtocol.requests = []
        print("Local dictionary availability: \(TranslationText.definition("hello") == nil ? "not installed" : "available")")
    }
    static func main() {
        setbuf(stdout, nil)
        checkSelectionSearch()
        checkReadingFeatures()
        let suite = "SwifTL.Checks.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = TranslatorViewModel(session: session, preferences: prefs)
        model.automaticLanguage = false
        model.isDeepLEnabled = false
        model.sourceLanguage = Language(name: "English", code: "en")
        model.targetLanguage = Language(name: "Chinese (Simplified)", code: "zh-Hans")
        model.inputText = " \n\t"
        model.translateInput()
        check(!model.isTranslating && TranslationProtocol.requests.isEmpty, "blank input sends no request")
        let original = "A&B + C? #100% 中文😀\nSecond paragraph."
        model.inputText = original
        TranslationProtocol.responseData = Data(#"[[["第一段",null],["第二段",null]],null,"en"]"#.utf8)
        model.translatedText = "old"
        model.errorMessage = "old error"
        model.translateInput()
        check(model.isTranslating && model.translatedText.isEmpty && model.errorMessage == nil, "new request clears previous result and error")
        model.translateInput()
        model.clearInput()
        wait(model)
        check(TranslationProtocol.requests.count == 1 && model.inputText == original, "duplicate submit and clear blocked during request")
        check(model.translatedText == "第一段第二段", "all translation segments joined")
        let query = URLComponents(url: TranslationProtocol.requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        check(query.first(where: { $0.name == "q" })?.value == original, "special characters and paragraphs round-trip")
        check(!query.contains(where: { $0.name == "tk" }), "no random token")
        let reloaded = TranslatorViewModel(session: session, preferences: prefs)
        check(reloaded.sourceLanguage == model.sourceLanguage && reloaded.targetLanguage == model.targetLanguage, "language selections automatically reload")
        let previousSource = model.sourceLanguage
        let previousTarget = model.targetLanguage
        model.swapLanguages()
        check(model.sourceLanguage == previousTarget && model.targetLanguage == previousSource, "swap exchanges source and target")
        let swapped = TranslatorViewModel(session: session, preferences: prefs)
        check(swapped.sourceLanguage == previousTarget && swapped.targetLanguage == previousSource, "swapped languages automatically reload")
        model.swapLanguages()
        for invalid in ["[]", "[[[]]]", "not json"] {
            TranslationProtocol.responseData = Data(invalid.utf8)
            model.translateInput(); wait(model)
            check(model.errorMessage != nil && model.inputText == original, "malformed response fails safely: \(invalid)")
        }
        TranslationProtocol.failure = URLError(.notConnectedToInternet)
        model.translateInput(); wait(model)
        check(model.errorMessage?.contains("Network error") == true && model.inputText == original, "network failure preserves input")
        TranslationProtocol.failure = nil
        TranslationProtocol.status = 429
        model.translateInput(); wait(model)
        check(model.errorMessage?.contains("429") == true, "HTTP failure visible")
        TranslationProtocol.status = 200
        TranslationProtocol.responseData = Data(#"[[["重试成功",null]],null,"en"]"#.utf8)
        model.translateInput(); wait(model)
        check(model.translatedText == "重试成功" && model.errorMessage == nil, "retry recovers")
        model.isSelectingArea = true
        model.translateInput()
        check(!model.isTranslating, "input blocked during screenshot selection")
        model.cancelAreaSelection()
        check(model.canTranslate && model.inputText == original, "cancel selection restores input mode")
        model.clearInput()
        check(model.inputText.isEmpty && model.translatedText.isEmpty && model.errorMessage == nil, "clear resets input and result")
        model.sourceLanguage = model.targetLanguage
        model.inputText = "same language"
        model.translateInput()
        check(!model.isTranslating, "same-language request blocked")
        model.sourceLanguage = Language(name: "English", code: "en")
        model.targetLanguage = Language(name: "Chinese", code: "zh-Hans")
        model.inputText = original
        model.isDeepLEnabled = true
        model.deepLApiKey = "test-only-key"
        TranslationProtocol.responseData = Data(#"{"translations":[{"text":"DeepL result"}]}"#.utf8)
        model.translateInput(); wait(model)
        let deepLRequest = TranslationProtocol.requests.last!
        // URLProtocol can receive a body stream instead of httpBody.
        var body = deepLRequest.httpBody
        if body == nil, let stream = deepLRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                collected.append(contentsOf: bytes.prefix(count))
            }
            body = collected
        }
        let payload = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        check(deepLRequest.url?.host == "api-free.deepl.com" && payload["text"] as? [String] == [original], "DeepL JSON preserves special characters")
        check(model.translatedText == "DeepL result", "existing DeepL provider used")
        let savedInput = model.inputText
        let savedTranslation = model.translatedText
        let quick = model.makeQuickTranslationModel()
        check(quick.sourceLanguage == model.sourceLanguage && quick.targetLanguage == model.targetLanguage && quick.isDeepLEnabled && quick.deepLApiKey == model.deepLApiKey, "quick translation snapshots languages and provider")
        quick.inputText = "Selected text"
        TranslationProtocol.responseData = Data(#"{"translations":[{"text":"Quick result"}]}"#.utf8)
        quick.translateInput(); wait(quick)
        check(quick.translatedText == "Quick result" && model.inputText == savedInput && model.translatedText == savedTranslation, "quick translation leaves main-window text intact")
        quick.sourceLanguage = Language(name: "Japanese", code: "ja")
        check(prefs.string(forKey: "DefaultSourceLanguageCode") == model.sourceLanguage.code, "quick model does not overwrite saved language preferences")
        quick.isDeepLEnabled = false
        TranslationProtocol.failure = URLError(.notConnectedToInternet)
        quick.translateInput(); wait(quick)
        check(quick.errorMessage != nil && model.errorMessage == nil && model.translatedText == savedTranslation, "quick translation failure is isolated from main window")
        TranslationProtocol.failure = nil
        if CommandLine.arguments.contains("--live") {
            let live = TranslatorViewModel(preferences: prefs)
            live.isDeepLEnabled = false
            for (from, to, text) in [("en", "zh-Hans", "Hello world."), ("zh-Hans", "en", "你好，世界。"), ("en", "zh-Hans", original)] {
                live.sourceLanguage = Language(name: from, code: from)
                live.targetLanguage = Language(name: to, code: to)
                live.inputText = text
                live.translateInput(); wait(live)
                check(live.errorMessage == nil && !live.translatedText.isEmpty, "live \(from) → \(to)")
                print(live.translatedText)
            }
            live.automaticLanguage = true
            for text in ["This is the first paragraph.\n\nThe second paragraph has A&B + emoji 😀.", "你好，这是自动翻译测试。", "hello", "這是一段繁體中文，用來測試自動翻譯。", "これは日本語の文章です。"] {
                live.inputText = text
                live.translateInput(); wait(live)
                check(live.errorMessage == nil && live.result?.succeeded == true, "live automatic translation: \(live.result?.direction ?? "missing")")
                print(live.translatedText)
            }
        }
    }
}
