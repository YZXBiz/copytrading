import AppKit
import Testing

@MainActor
func runQuitRequestTests() throws {
    try aSheetNeverStopsAQuitWithNothingToLose()
    try keepingTheEditsLeavesEverySheetOpen()
    try discardingTheEditsLetsTheQuitGoOn()
}

@MainActor
private func windowWithSheets(depth: Int) -> (window: NSWindow, sheets: [NSWindow]) {
    func make() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
    }
    let window = make()
    // A sheet only attaches to a window that is on screen.
    window.orderFront(nil)
    var sheets: [NSWindow] = []
    var parent = window
    for _ in 0..<depth {
        let sheet = make()
        parent.beginSheet(sheet) { _ in }
        sheets.append(sheet)
        parent = sheet
    }
    return (window, sheets)
}

@MainActor
private func aSheetNeverStopsAQuitWithNothingToLose() throws {
    let (window, sheets) = windowWithSheets(depth: 2)
    defer { window.orderOut(nil) }
    try #require(window.attachedSheet === sheets[0], "the sheet must be attached before the quit")
    var asked = 0
    let confirmed = QuitRequest.confirmed(hasUnsavedSetup: false) {
        asked += 1
        return false
    }
    try #require(confirmed, "a quit with no unsaved setup must go on with sheets open")
    try #require(asked == 0, "nothing is asked when no setup edit would be lost")
    QuitRequest.endSheets(in: [window])
    try #require(window.attachedSheet == nil, "AppKit refuses to terminate while a sheet is attached")
    try #require(sheets[0].attachedSheet == nil, "a sheet on a sheet ends too")
}

@MainActor
private func keepingTheEditsLeavesEverySheetOpen() throws {
    let (window, sheets) = windowWithSheets(depth: 1)
    defer { window.orderOut(nil) }
    var asked = 0
    let confirmed = QuitRequest.confirmed(hasUnsavedSetup: true) {
        asked += 1
        return false
    }
    try #require(!confirmed, "keeping the edits must stop the quit")
    try #require(asked == 1, "the question is asked once")
    try #require(window.attachedSheet === sheets[0], "the sheet being edited must still be open")
}

@MainActor
private func discardingTheEditsLetsTheQuitGoOn() throws {
    var asked = 0
    let confirmed = QuitRequest.confirmed(hasUnsavedSetup: true) {
        asked += 1
        return true
    }
    try #require(confirmed, "discarding the edits lets the quit go on")
    try #require(asked == 1, "the question is asked once")
}
