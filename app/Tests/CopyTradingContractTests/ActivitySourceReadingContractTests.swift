import DesktopCore
import Foundation

@MainActor
func checkActivitySourceReadingRepresentation() throws {
    let source = " \n  買入 NVDA **at $120** @everyone\n\n@here观察回撤。\t "
    let activity = try activityWithSourceText(source)

    let reading = activity.readingText()
    try requireActivityReading(
        reading == "買入 NVDA **at $120** \n\n观察回撤。",
        "The reading representation did not preserve the original paragraphs and Markdown markers"
    )

    let preview = activity.readableText()
    try requireActivityReading(
        !preview.contains("\n") && !preview.contains("@everyone") && !preview.contains("@here"),
        "The compact Activity preview stopped being a one-line mention-free summary"
    )

    let blank = try activityWithSourceText(" \n\t  ")
    try requireActivityReading(blank.readingText().isEmpty, "A blank source post was not empty after display trimming")

    let embed: [String: Any] = [
        "title": "NVDA thesis",
        "description": "Captured target.",
        "fields": [["name": "Target", "value": "$140", "inline": false]],
    ]
    let capturedContent = "買入 NVDA at $120"
    let flattenedText = [capturedContent, "NVDA thesis", "Captured target.", "Target", "$140"]
        .joined(separator: "\n")
    let withEmbed = try activityWithSourceText(
        flattenedText,
        eventContent: capturedContent,
        embeds: [embed]
    )
    try requireActivityReading(
        withEmbed.readingText() == capturedContent,
        "The reader repeated embed text already captured separately from the original message"
    )

    try requireActivityReading(
        PeopleSourcePreview.text(for: withEmbed) == capturedContent,
        "People preview repeated canonical embed text instead of the captured message"
    )
    try requireActivityReading(
        withEmbed.readableText() == capturedContent,
        "The shared post-row preview repeated flattened embed content instead of the captured message"
    )
    let formattedPost = try activityWithSourceText("**Buy NVDA** @here\n[chart](https://example.com/chart)")
    let personPreview = PeopleSourcePreview.text(for: formattedPost)
    let formatted = PeopleSourcePreview.formatted(personPreview)
    try requireActivityReading(
        String(formatted.characters) == "Buy NVDA chart" && formatted.runs.allSatisfy { $0.link == nil },
        "People preview lost inline source formatting or retained an interactive link inside the card button"
    )

    let embedOnly = try activityWithSourceText(flattenedText, eventContent: "", embeds: [embed])
    try requireActivityReading(
        embedOnly.readingText().isEmpty && embedOnly.readableSourceEmbeds.count == 1,
        "An empty original message with captured embeds duplicated flattened embed content"
    )

    try requireActivityReading(
        PeopleSourcePreview.text(for: embedOnly) == "NVDA thesis Captured target. Target $140",
        "An embed-only People preview did not use captured source evidence in order"
    )
    let mentionOnlyWithEmbed = try activityWithSourceText(
        "NVDA thesis Captured target. Target $140",
        eventContent: "@here\n  ",
        embeds: [embed]
    )
    try requireActivityReading(
        PeopleSourcePreview.text(for: mentionOnlyWithEmbed) == "NVDA thesis Captured target. Target $140",
        "A mention-only captured People message suppressed readable embed evidence"
    )
    let mentionOnly = try activityWithSourceText("@here\n  ")
    try requireActivityReading(
        PeopleSourcePreview.text(for: mentionOnly).isEmpty,
        "A mention-only People post invented source text without embed evidence"
    )
    try requireActivityReading(
        PeopleSourcePreview.text(for: blank).isEmpty,
        "A blank People post invented source text"
    )

    let legacy = try activityWithSourceText(
        "Legacy source @here",
        eventContent: "",
        eventCaptureStatus: "missing"
    )
    try requireActivityReading(
        legacy.readingText() == "Legacy source" && legacy.readableSourceEmbeds.isEmpty,
        "Missing source-event evidence stopped falling back to the legacy text exactly once"
    )

    try requireActivityReading(
        PeopleSourcePreview.text(for: legacy) == "Legacy source",
        "People preview stopped falling back to missing legacy source evidence"
    )

    let oversized = try activityWithSourceText(
        flattenedText,
        eventContent: "",
        eventCaptureStatus: "oversize",
        embeds: [embed]
    )
    try requireActivityReading(
        oversized.readingText() == flattenedText && oversized.readableSourceEmbeds.isEmpty,
        "Oversize source-event evidence did not fall back to the canonical text exactly once"
    )
    try requireActivityReading(
        oversized.readableText() == flattenedText.split(whereSeparator: \.isWhitespace).joined(separator: " "),
        "The shared post-row preview stopped using the bounded legacy fallback for oversized evidence"
    )

    let whitespaceEmbed = try activityWithSourceText(
        " \n ",
        eventContent: "",
        embeds: [
            [
                "title": " \n ",
                "description": "\t",
                "fields": [["name": " ", "value": "\n", "inline": false]],
            ]
        ]
    )
    try requireActivityReading(
        whitespaceEmbed.sourceEvent.embeds.first?.hasReadableContent == false
            && whitespaceEmbed.readableSourceEmbeds.isEmpty,
        "A whitespace-only captured embed was treated as readable source content"
    )

    print("CopyTradingContractTests: Activity reading preserves source paragraphs and markers while previews stay compact")
}

@MainActor
func checkActivityDestinationInstructionOutcomes() throws {
    let order: [String: Any] = [
        "client_id": "client-nvda",
        "symbol": "NVDA",
        "side": "buy",
        "status": "partially_filled",
        "quantity": "2",
        "filled_quantity": "1",
        "limit_price": NSNull(),
        "average_fill_price": NSNull(),
        "broker_id": NSNull(),
        "created_at": "2026-09-29T12:00:00Z",
        "instruction_index": 0,
        "requested_usd": NSNull(),
        "budget_usd": NSNull(),
    ]
    let partiallyFilled = try activityWithSourceText(
        "",
        destinations: [
            [
                "account_id": "paper-a",
                "environment": "paper",
                "status": "done",
                "instruction_outcomes": ["submitted", "symbol_unresolved"],
                "limits_hit": [],
                "orders": [order],
            ]
        ])
    guard let destination = partiallyFilled.destinations.first else {
        throw ActivityReadingContractFailure(message: "The partial-fill fixture had no destination")
    }
    let partialOutcome = DestinationOutcome(destination)
    try requireActivityReading(
        partialOutcome.title == "Partly filled",
        "A submitted partial-fill account was classified as skipped"
    )
    let partialDetails = DestinationInstructionDetails.rows(for: destination, summary: partialOutcome)
    try requireActivityReading(
        DestinationInstructionDetails.title == "Instruction details"
            && partialDetails.map(\.value) == ["Submitted", "Symbol unresolved"]
            && partialDetails.map(\.id) == [0, 1],
        "Mixed progress and skip-reason evidence was mislabeled or reordered"
    )

    let completedWithoutOrder = try activityWithSourceText(
        "",
        destinations: [
            [
                "account_id": "paper-b",
                "environment": "paper",
                "status": "done",
                "instruction_outcomes": ["symbol_unresolved"],
                "limits_hit": [],
                "orders": [],
            ]
        ])
    guard let noOrderDestination = completedWithoutOrder.destinations.first else {
        throw ActivityReadingContractFailure(message: "The no-order fixture had no destination")
    }
    let noOrderOutcome = DestinationOutcome(noOrderDestination)
    try requireActivityReading(
        noOrderOutcome.title == "Processed" && noOrderOutcome.detail == "Processing finished without an order.",
        "A completed destination without orders was described as waiting or skipped"
    )
    try requireActivityReading(
        DestinationInstructionDetails.rows(for: noOrderDestination, summary: noOrderOutcome).map(\.value)
            == ["Symbol unresolved"],
        "The completed no-order instruction reason was not retained as neutral detail"
    )

    let sameSummary = try activityWithSourceText(
        "",
        destinations: [
            [
                "account_id": "paper-c",
                "environment": "paper",
                "status": "ignored",
                "instruction_outcomes": ["ignored"],
                "limits_hit": [],
                "orders": [],
            ]
        ])
    let repeatedSummary = try activityWithSourceText(
        "",
        destinations: [
            [
                "account_id": "paper-d",
                "environment": "paper",
                "status": "ignored",
                "instruction_outcomes": ["ignored", "ignored"],
                "limits_hit": [],
                "orders": [],
            ]
        ])
    guard let sameSummaryDestination = sameSummary.destinations.first,
        let repeatedSummaryDestination = repeatedSummary.destinations.first
    else {
        throw ActivityReadingContractFailure(message: "The repeated-summary fixtures had no destinations")
    }
    let sameSummaryOutcome = DestinationOutcome(sameSummaryDestination)
    try requireActivityReading(
        DestinationInstructionDetails.rows(for: sameSummaryDestination, summary: sameSummaryOutcome).isEmpty,
        "A sole instruction detail duplicated the authoritative account outcome"
    )
    let repeatedRows = DestinationInstructionDetails.rows(
        for: repeatedSummaryDestination,
        summary: DestinationOutcome(repeatedSummaryDestination)
    )
    try requireActivityReading(
        repeatedRows.map(\.value) == ["Ignored", "Ignored"] && repeatedRows.map(\.id) == [0, 1],
        "Repeated instruction outcomes were collapsed by their display text"
    )
    print("CopyTradingContractTests: Activity destination statuses remain authoritative and instruction evidence stays complete")
}

private func activityWithSourceText(
    _ text: String,
    eventContent: String? = nil,
    eventCaptureStatus: String = "complete",
    embeds: [[String: Any]] = [],
    destinations: [[String: Any]] = []
) throws -> SourceActivity {
    let payload: [String: Any] = [
        "sequence": 1,
        "source_id": "discord:contract:1",
        "source_revision": 1,
        "source_at": "2026-09-29T12:00:00Z",
        "captured_at": "2026-09-29T12:00:01Z",
        "text": text,
        "capture_status": "delivered",
        "parse_status": "complete",
        "delivery_status": "delivered",
        "instructions": [],
        "suggested": [],
        "source_event": [
            "event_type": "discord_message",
            "content": eventContent ?? text,
            "embeds": embeds,
            "attachments": [],
            "attachments_omitted": 0,
            "capture_status": eventCaptureStatus,
            "payload_bytes": 0,
        ],
        "destinations": destinations,
    ]
    return try JSONDecoder().decode(SourceActivity.self, from: JSONSerialization.data(withJSONObject: payload))
}

private struct ActivityReadingContractFailure: Error {
    let message: String
}

@MainActor
private func requireActivityReading(_ condition: @autoclosure @MainActor () -> Bool, _ message: String) throws {
    guard condition() else { throw ActivityReadingContractFailure(message: message) }
}
