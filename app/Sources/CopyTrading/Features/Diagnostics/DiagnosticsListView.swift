import DesktopCore
import SwiftUI

/// Journal records as a quiet list: rows on the canvas, hairlines between them, the chosen
/// record on a pale blue pill. Up and down arrows move the selection.
struct DiagnosticsListView: View {
    let entries: [DiagnosticsJournalEntry]
    @Binding var selection: DiagnosticsJournalEntry.ID?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredID: DiagnosticsJournalEntry.ID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                        if index < entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                                .opacity(entry.id == selection || entries[index + 1].id == selection ? 0 : 1)
                        }
                    }
                }
                .padding(10)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(by: 1, proxy: proxy) }
            .onKeyPress(.upArrow) { move(by: -1, proxy: proxy) }
        }
    }

    private func row(_ entry: DiagnosticsJournalEntry) -> some View {
        let isSelected = entry.id == selection
        return Button {
            selection = entry.id
            focused = true
        } label: {
            DiagnosticsEntryRow(entry: entry)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Palette.selection : hoveredID == entry.id ? Palette.hover : .clear,
                    in: .rect(cornerRadius: 10)
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredID == entry.id)
                .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovering in
            hoveredID = isHovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID)
        }
        .id(entry.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        let current = entries.firstIndex { $0.id == selection } ?? -1
        let next = entries[min(max(current + offset, 0), entries.count - 1)].id
        selection = next
        proxy.scrollTo(next)
        return .handled
    }
}
