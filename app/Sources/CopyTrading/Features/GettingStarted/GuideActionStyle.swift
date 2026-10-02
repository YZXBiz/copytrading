import SwiftUI

/// The guide's step buttons: prominent for the step to do next, quiet once it is done.
struct GuideActionStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
