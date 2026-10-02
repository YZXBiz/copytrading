import SwiftUI

/// One account's result for one post: symbol and word, tinted by meaning.
struct OutcomeBadge: View {
    let outcome: DestinationOutcome
    var accountID: String?

    var body: some View {
        Label {
            Text(accountID.map { "\($0) · \(outcome.title)" } ?? outcome.title)
        } icon: {
            Image(systemName: outcome.symbol)
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(outcome.tone.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(outcome.tone.color.opacity(0.1), in: .capsule)
        .fixedSize()
        .help(outcome.detail)
    }
}
