import AppKit
import Foundation

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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
        } else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseData)
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
    static func main() {
        checkSelectionSearch()
        let suite = "SwifTL.Checks.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = TranslatorViewModel(session: session, preferences: prefs)
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
        }
    }
}
