import SwiftUI

/// The reading pane before a post is chosen. Activity with no posts at all shows its invitation
/// across the whole page instead.
struct ActivityPlaceholderView: View {
    let isRefreshing: Bool

    var body: some View {
        if isRefreshing {
            ProgressView(L10n.string("Reading activity…"))
        } else {
            ContentUnavailableView(
                L10n.string("Select a post"),
                systemImage: "text.bubble",
                description: Text(L10n.string("See the message, what it was understood as, and each account's orders."))
            )
        }
    }
}
