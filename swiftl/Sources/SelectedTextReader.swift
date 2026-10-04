import AppKit
import ApplicationServices

// Focus in Chromium can refer to a group, while selection belongs to its web area.
// Search only the active window, and never substitute a control's whole value.
struct SelectionSearch<Node> {
    let selectedText: (Node) -> String?
    let parent: (Node) -> Node?
    let children: (Node) -> [Node]
    let isWebArea: (Node) -> Bool
    let isSecure: (Node) -> Bool
    let canContinue: () -> Bool
    var limit = 240

    func find(focused: Node?, hit: Node?, window: Node?) -> (Node, String)? {
        var remaining = limit
        func read(_ node: Node) -> (Node, String)? {
            guard remaining > 0, canContinue(), !isSecure(node) else { return nil }
            remaining -= 1
            guard let text = selectedText(node), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (node, text)
        }
        if let focused = focused {
            guard !isSecure(focused) else { return nil }
            var ancestor: Node? = focused
            for _ in 0..<10 {
                guard let node = ancestor, remaining > 0, canContinue() else { break }
                if let result = read(node) { return result }
                ancestor = parent(node)
            }
        }
        // Prefer the enclosing web area's complete selection over a text fragment.
        if let hit = hit {
            var ancestors = [Node]()
            var current: Node? = hit
            for _ in 0..<10 {
                guard let node = current, canContinue(), !isSecure(node) else { break }
                ancestors.append(node)
                current = parent(node)
            }
            for node in ancestors.reversed() where isWebArea(node) {
                if let result = read(node) { return result }
            }
            for node in ancestors {
                if let result = read(node) { return result }
            }
        }
        guard let window = window else { return nil }
        var queue: [(Node, Bool)] = [(window, false)]
        var index = 0
        while index < queue.count, remaining > 0, canContinue() {
            let (node, insideWebArea) = queue[index]
            index += 1
            remaining -= 1
            if isSecure(node) { continue }
            let webArea = insideWebArea || isWebArea(node)
            if webArea, let result = read(node) { return result }
            // Bound the queue as well as the number of attribute reads.
            let available = max(0, limit - queue.count)
            queue.append(contentsOf: children(node).prefix(available).map { ($0, webArea) })
        }
        return nil
    }
}

struct SelectedTextResult {
    let text: String
    let bounds: CGRect?
}

final class SelectedTextReader {
    private(set) var encounteredSecureField = false
    private let deadline = Date().addingTimeInterval(1.5)

    func read(processID: pid_t, browser: Bool, mouse: CGPoint) -> SelectedTextResult? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        if browser {
            // Chromium documents this attribute as enabling its accessibility tree.
            _ = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        let focused = element(application, kAXFocusedUIElementAttribute)
        if let focused = focused, secure(focused) { encounteredSecureField = true; return nil }
        let window = element(application, kAXFocusedWindowAttribute)
        var hit: AXUIElement?
        _ = AXUIElementCopyElementAtPosition(application, Float(mouse.x), Float(mouse.y), &hit)
        let search = SelectionSearch<AXUIElement>(
            selectedText: { self.text($0) },
            parent: { self.element($0, kAXParentAttribute) },
            children: { self.children($0) },
            isWebArea: { self.attribute($0, kAXRoleAttribute) as? String == "AXWebArea" },
            isSecure: { self.secure($0) },
            canContinue: { Date() < self.deadline }
        )
        guard let (owner, text) = search.find(focused: focused, hit: hit, window: window) else { return nil }
        return SelectedTextResult(text: text, bounds: bounds(owner))
    }

    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        guard Date() < deadline else { return nil }
        AXUIElementSetMessagingTimeout(node, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func children(_ node: AXUIElement) -> [AXUIElement] {
        (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
    private func secure(_ node: AXUIElement) -> Bool {
        attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
    }
    private func text(_ node: AXUIElement) -> String? {
        if let text = attribute(node, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        // WebKit/Chromium use opaque text-marker ranges for document selections.
        guard let range = attribute(node, "AXSelectedTextMarkerRange"), Date() < deadline else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(node, "AXStringForTextMarkerRange" as CFString, range, &value) == .success else { return nil }
        return value as? String
    }
    private func bounds(_ node: AXUIElement) -> CGRect? {
        let range = attribute(node, kAXSelectedTextRangeAttribute)
        let marker = range == nil ? attribute(node, "AXSelectedTextMarkerRange") : nil
        guard let parameter = range ?? marker, Date() < deadline else { return nil }
        let name = range != nil ? kAXBoundsForRangeParameterizedAttribute : "AXBoundsForTextMarkerRange"
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(node, name as CFString, parameter, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}
