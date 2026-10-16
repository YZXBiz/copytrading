/// The screens Back and Forward step through. Only the owner's own moves are recorded: the screen
/// a launch opens on has nothing before it, and a screen that has since gone (a removed guru or
/// account) is passed over.
struct ScreenHistory: Equatable {
    private(set) var back: [AppModel.Screen] = []
    private(set) var forward: [AppModel.Screen] = []

    /// The owner moved on from `screen`; whatever was ahead of it is dropped.
    mutating func leave(_ screen: AppModel.Screen) {
        back.append(screen)
        forward.removeAll()
    }

    /// The newest earlier screen that still exists, with `current` kept for Forward.
    mutating func goBack(from current: AppModel.Screen, keeping exists: (AppModel.Screen) -> Bool) -> AppModel.Screen? {
        guard let screen = Self.pop(&back, keeping: exists) else { return nil }
        forward.append(current)
        return screen
    }

    /// The screen Back last left, with `current` kept for Back.
    mutating func goForward(from current: AppModel.Screen, keeping exists: (AppModel.Screen) -> Bool) -> AppModel.Screen? {
        guard let screen = Self.pop(&forward, keeping: exists) else { return nil }
        back.append(current)
        return screen
    }

    private static func pop(_ stack: inout [AppModel.Screen], keeping exists: (AppModel.Screen) -> Bool) -> AppModel.Screen? {
        while let screen = stack.popLast() {
            if exists(screen) { return screen }
        }
        return nil
    }
}
