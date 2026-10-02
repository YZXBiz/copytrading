import DesktopCore
import SwiftUI

/// The posts as a quiet list: rows on the canvas, hairlines between them, and the chosen
/// post on a pale blue pill with dark text. Up and down arrows move the selection.
struct ActivityListView: View {
    let items: [SourceActivity]
    let directory: GuruDirectory
    @Binding var selection: SourceActivity.ID?
    @Binding var filter: ActivityFilter
    let hasMore: Bool
    let loadMore: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredID: SourceActivity.ID?
    @State private var listPosition = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 {
                        let nextSelected = items[index + 1].id == selection
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(item.id == selection || nextSelected ? 0 : 1)
                    }
                }
                if hasMore {
                    Button(L10n.string("Load Older Posts"), action: loadMore)
                        .buttonStyle(.link)
                        .padding(.vertical, 12)
                }
            }
            .scrollTargetLayout()
            .padding(10)
        }
        .scrollPosition($listPosition)
        .defaultScrollAnchor(.top, for: .initialOffset)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onAppear {
            scrollToSelectionIfLoaded()
        }
        .onChange(of: selection) { _, _ in
            scrollToSelectionIfLoaded()
        }
        .onChange(of: filter) { _, _ in
            scrollToSelectionIfLoaded()
        }
        .overlay {
            if items.isEmpty && filter != .all {
                ContentUnavailableView(
                    L10n.string(filter == .needsReview ? "Nothing needs review" : "No trades yet"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    private func row(_ item: SourceActivity) -> some View {
        let isSelected = item.id == selection
        return Button {
            selection = item.id
            focused = true
        } label: {
            ActivityInboxRow(item: item, guruName: directory.name(for: item.guruID), preview: directory.preview(of: item))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Palette.selection : hoveredID == item.id ? Palette.hover : .clear,
                    in: .rect(cornerRadius: 10)
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredID == item.id)
                .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovering in
            hoveredID = isHovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .id(item.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let current = items.firstIndex { $0.id == selection } ?? -1
        let next = min(max(current + offset, 0), items.count - 1)
        let nextID = items[next].id
        if selection == nextID {
            // A boundary key still reveals the selected row without issuing two scroll requests.
            scrollToSelectionIfLoaded()
        } else {
            selection = nextID
        }
        return .handled
    }

    private func scrollToSelectionIfLoaded() {
        guard let selection, items.contains(where: { $0.id == selection }) else { return }
        if selection == items.first?.id {
            listPosition.scrollTo(edge: .top)
        } else {
            listPosition.scrollTo(id: selection, anchor: .center)
        }
    }
}
