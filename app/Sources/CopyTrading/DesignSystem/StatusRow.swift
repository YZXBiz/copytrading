import SwiftUI

/// A label on the left and a status badge on the right, for health lists.
struct StatusRow: View {
    let title: String
    let value: String
    let tone: StatusTone
    private let localizesTitle: Bool

    init(_ title: String, value: String, tone: StatusTone, localizesTitle: Bool = true) {
        self.title = title
        self.value = value
        self.tone = tone
        self.localizesTitle = localizesTitle
    }

    var body: some View {
        HStack {
            Text(localizesTitle ? L10n.string(title) : title)
            Spacer(minLength: 12)
            StatusBadge(value, tone: tone)
        }
        .accessibilityElement(children: .combine)
    }
}
