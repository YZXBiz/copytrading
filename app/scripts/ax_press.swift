// Presses one control of a running app through Accessibility, in the background: the first element
// whose AXIdentifier matches, searched through every window and sheet. The UI journeys use it for
// the open and save panels, whose buttons Peekaboo can see but not reliably press.
//
//   swift app/scripts/ax_press.swift <pid> <identifier>
//
// Exit status: 0 pressed, 1 not found, 2 found but disabled, 3 the press failed.
import ApplicationServices
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = pid_t(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: ax_press.swift <pid> <identifier>\n".utf8))
    exit(64)
}
let identifier = arguments[2]

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func find(in element: AXUIElement) -> AXUIElement? {
    if attribute(element, kAXIdentifierAttribute) as? String == identifier { return element }
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        if let found = find(in: child) { return found }
    }
    return nil
}

guard let element = find(in: AXUIElementCreateApplication(pid)) else { exit(1) }
if attribute(element, kAXEnabledAttribute) as? Bool == false { exit(2) }
exit(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success ? 0 : 3)
