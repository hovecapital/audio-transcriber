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

    static func insertTextAtCursor(_ text: String, preserveClipboard: Bool = true) -> Bool {
        if let focused = readFocusedElementText() {
            let range = focused.selectedRange
            var mutableRange = range
            guard let axRange = AXValueCreate(.cfRange, &mutableRange) else {
                return pasteViaClipboard(text, preserveClipboard: preserveClipboard)
            }

            guard AXUIElementSetAttributeValue(focused.element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success else {
                return pasteViaClipboard(text, preserveClipboard: preserveClipboard)
            }

            guard AXUIElementSetAttributeValue(focused.element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
                return pasteViaClipboard(text, preserveClipboard: preserveClipboard)
            }

            Log.dictation.debug("Inserted text via AX API")
            return true
        }

        return pasteViaClipboard(text, preserveClipboard: preserveClipboard)
    }

    private static func pasteViaClipboard(_ text: String, preserveClipboard: Bool = true) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousContents = preserveClipboard ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            if let prev = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if preserveClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let prev = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(prev, forType: .string)
                }
            }
        }

        Log.dictation.debug("Inserted text via clipboard paste fallback")
        return true
    }
}
