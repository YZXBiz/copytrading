import DesktopCore
import Foundation

@MainActor
func runWindowSessionLifecycleTests() throws {
    let lifecycle = WindowSessionLifecycle()
    let window = NSObject()
    let firstOpening = UUID()
    let reopenedWindow = UUID()

    try verify(
        lifecycle.attach(to: window, sessionID: firstOpening) == nil,
        "the first native window opening must not replace another session")
    try verify(
        lifecycle.attach(to: window, sessionID: firstOpening) == nil,
        "duplicate representable attachment must keep the current window token")
    try verify(
        lifecycle.close(window, sessionID: firstOpening) == firstOpening,
        "the native close callback must end the active window token")

    try verify(
        lifecycle.attach(to: window, sessionID: reopenedWindow) == nil,
        "reopening a native window must create a fresh session token")
    try verify(
        firstOpening != reopenedWindow,
        "a reopened native window must not reuse its previous authentication token")
    try verify(
        lifecycle.close(window, sessionID: firstOpening) == nil,
        "a delayed close from the prior opening must not close the reopened window")
    try verify(
        lifecycle.close(window, sessionID: reopenedWindow) == reopenedWindow,
        "the current native close callback must close only the reopened session")
}
