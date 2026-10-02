import DesktopCore
import SwiftUI

/// The engine's local log, read straight from disk: searchable, filterable, and readable while the
/// engine is stopped.
struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var filter = DiagnosticsFilter.all
    @State private var query = ""
    @State private var selection: DiagnosticsJournalEntry.ID?

    private var visibleEntries: [DiagnosticsJournalEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.diagnosticsEntries.filter { entry in
            filter.includes(entry) && (needle.isEmpty || entry.searchText.contains(needle))
        }
    }

    private var selectedEntry: DiagnosticsJournalEntry? {
        visibleEntries.first { $0.id == selection }
    }

    var body: some View {
        Group {
            if model.diagnosticsEntries.isEmpty {
                ScrollView {
                    LogInvitation(model: model)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DesignTokens.pagePadding)
                        .padding(.top, 28)
                        .padding(.bottom, 32)
                }
            } else {
                readingLayout
            }
        }
        .pageBar {
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        header
                        Spacer(minLength: 12)
                        controls
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        controls
                    }
                }
                .padding(.horizontal, DesignTokens.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
                if let message = model.diagnosticsJournalMessage {
                    Callout(message, tone: .caution)
                        .padding(.horizontal, DesignTokens.pagePadding)
                        .padding(.bottom, 10)
                }
                Divider()
            }
        }
        .navigationTitle(L10n.string("Diagnostics"))
        .task { await refreshWhileVisible() }
        .onChange(of: filter) { reconcileSelection() }
        .onChange(of: query) { reconcileSelection() }
    }

    /// The record list beside the record it shows.
    private var readingLayout: some View {
        HStack(spacing: 0) {
            Group {
                if visibleEntries.isEmpty {
                    emptyList
                } else {
                    DiagnosticsListView(entries: visibleEntries, selection: $selection)
                }
            }
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 320, maxHeight: .infinity)

            Divider()

            Group {
                if let selectedEntry {
                    DiagnosticsEntryDetailView(entry: selectedEntry)
                } else {
                    ContentUnavailableView(
                        L10n.string("Select a record"),
                        systemImage: "waveform.path.ecg",
                        description: Text(L10n.string("See when it happened, how it ended, and the redacted payload it captured."))
                    )
                }
            }
            .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string("Diagnostics"))
                .font(DesignTokens.pageTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(
                L10n.string(
                    "%@ · %@ on this Mac",
                    Humanize.count(model.diagnosticsEntries.count, "record"),
                    Humanize.bytes(model.diagnosticsJournalBytes)
                )
            )
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.tertiaryInk)
            .monospacedDigit()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            SegmentedTrack(options: DiagnosticsFilter.allCases, selection: $filter) { option in
                Text(L10n.string(option.rawValue))
            }
            .fixedSize()
            .accessibilityLabel(L10n.string("Record type"))
            TextField(L10n.string("Search"), text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .accessibilityIdentifier("diagnostics.search")
            Button(L10n.string("Refresh"), systemImage: "arrow.clockwise") {
                Task { await model.reloadDiagnostics() }
            }
            .labelStyle(.iconOnly)
            .disabled(model.isLoadingDiagnostics)
            .help(L10n.string("Read the log again"))
            .accessibilityIdentifier("diagnostics.refresh")
        }
    }

    /// A search or filter that matches nothing; an empty log shows its invitation instead.
    @ViewBuilder
    private var emptyList: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView(
                L10n.string(filter.emptyTitle),
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(L10n.string(filter.emptyDescription))
            )
        }
    }

    /// The journal grows while the engine runs; reread it every few seconds while this page is open.
    private func refreshWhileVisible() async {
        while !Task.isCancelled {
            await model.reloadDiagnostics()
            reconcileSelection()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func reconcileSelection() {
        if selectedEntry == nil { selection = visibleEntries.first?.id }
    }
}
