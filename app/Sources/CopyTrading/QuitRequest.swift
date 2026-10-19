import AppKit

/// The two steps of a quit that sheets and unsaved setup edits get in the way of.
///
/// Quit, the Dock's Quit, a logout, and an update's Install and Relaunch all arrive as
/// `NSApplication.terminate(_:)`, and AppKit cancels that while any window has a sheet attached,
/// before the app delegate hears of it. So the app asks about edits the quit would drop, and
/// ends the sheets itself in the same breath as it calls `terminate` again.
@MainActor
enum QuitRequest {
    /// Whether the quit goes on. Keeping the edits leaves every sheet as it was.
    static func confirmed(hasUnsavedSetup: Bool, confirmDiscardingSetup: () -> Bool) -> Bool {
        !hasUnsavedSetup || confirmDiscardingSetup()
    }

    /// Ends every sheet. SwiftUI still counts a sheet it presents as open and can bring one back
    /// a moment after it ends, so this is called right before `terminate`, and goes again for any
    /// sheet that is still there.
    static func endSheets(in windows: [NSWindow]) {
        let deadline = Date.now.addingTimeInterval(2)
        repeat {
            for window in windows { window.endAttachedSheets() }
            if !windows.contains(where: { $0.attachedSheet != nil }) { return }
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.02))
        } while Date.now < deadline
    }
}

extension NSWindow {
    /// Ends every sheet on the window, the innermost first.
    func endAttachedSheets() {
        var ended: NSWindow?
        while let sheet = attachedSheet, sheet !== ended {
            sheet.endAttachedSheets()
            endSheet(sheet, returnCode: .cancel)
            ended = sheet
        }
    }
}
