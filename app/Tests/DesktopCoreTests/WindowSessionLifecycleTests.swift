import DesktopCore
import Foundation
import Testing

@MainActor
func runWindowSessionLifecycleTests() throws {
    let lifecycle = WindowSessionLifecycle()
    let window = NSObject()
    let firstOpening = UUID()
    let reopenedWindow = UUID()

    try #require(
        lifecycle.attach(to: window, sessionID: firstOpening) == nil,
        "the first native window opening must not replace another session")
    try #require(
        lifecycle.attach(to: window, sessionID: firstOpening) == nil,
        "duplicate representable attachment must keep the current window token")
    try #require(
        lifecycle.close(window, sessionID: firstOpening) == firstOpening,
        "the native close callback must end the active window token")

    try #require(
        lifecycle.attach(to: window, sessionID: reopenedWindow) == nil,
        "reopening a native window must create a fresh session token")
    try #require(
        firstOpening != reopenedWindow,
        "a reopened native window must not reuse its previous authentication token")
    try #require(
        lifecycle.close(window, sessionID: firstOpening) == nil,
        "a delayed close from the prior opening must not close the reopened window")
    try #require(
        lifecycle.close(window, sessionID: reopenedWindow) == reopenedWindow,
        "the current native close callback must close only the reopened session")
}
