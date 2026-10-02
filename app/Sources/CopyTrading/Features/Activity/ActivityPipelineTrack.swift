import DesktopCore
import SwiftUI

/// A post's trip in three stops — captured, read, delivered — joined by a line, so where it
/// stopped is visible at a glance instead of in three rows of status words.
struct ActivityPipelineTrack: View {
    let item: SourceActivity

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ActivityPipelineStage(
                title: L10n.string("Captured"), code: item.captureStatus,
                detail: Humanize.date(item.capturedAt)?.formatted(
                    .dateTime.hour().minute().second().locale(AppLanguagePreference.shared.language.locale)
                ))
            ActivityPipelineConnector(code: item.parseStatus)
            ActivityPipelineStage(title: L10n.string("Read"), code: item.parseStatus)
            ActivityPipelineConnector(code: item.deliveryStatus)
            ActivityPipelineStage(title: L10n.string("Delivered"), code: item.deliveryStatus)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Post pipeline"))
    }
}
