import SwiftUI

/// The guide's last lines: where to ask for help, and the tips that point things out again.
struct GuideFooter: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack(spacing: 16) {
                GuideFooterLinks(model: model)
            }
        }
    }
}
