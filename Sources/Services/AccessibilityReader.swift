import AppKit
import ApplicationServices

enum AccessibilityReader {
    static func isTrusted(promptIfNeeded: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    struct FocusedElement {
        let element: AXUIElement
        let text: String
        let selectedRange: CFRange
    }

    static func readFocusedElementText() -> FocusedElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else {
            return nil
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }

        let axElement = element as! AXUIElement

        var subrole: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subrole) == .success,
           let subroleStr = subrole as? String,
           subroleStr == kAXSecureTextFieldSubrole as String {
            return nil
        }

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else {
            return nil
        }

        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        return FocusedElement(element: axElement, text: text, selectedRange: range)
    }

    static func replaceText(in element: AXUIElement, range: CFRange, with replacement: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else {
            return false
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return false
        }

        let currentElement = focusedElement as! AXUIElement
        guard CFEqual(currentElement, element) else {
            Log.autocorrect.debug("Focused element changed, skipping replacement")
            return false
        }

        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }

        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success else {
            return false
        }

        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef) == .success else {
            return false
        }

        return true
    }
}
