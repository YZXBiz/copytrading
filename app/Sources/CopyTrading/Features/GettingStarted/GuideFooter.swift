import SwiftUI

/// The guide's last lines: where to ask for help, and the tips that point things out again.
struct GuideFooter: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            GuideFooterLinks(model: model)
        }
        .padding(.top, 14)
    }
}
