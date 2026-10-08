import DesktopCore
import SwiftUI

/// The posts as a quiet list: rows on the canvas, hairlines between them, and the chosen
/// post on a pale blue pill with dark text. Up and down arrows move the selection.
struct ActivityListView: View {
    let items: [SourceActivity]
    /// Sales the owner made, listed among the posts by time; choosing one opens the post that
    /// bought what it sold.
    var sales: [(accountID: String, item: AccountFeedItem)] = []
    let directory: GuruDirectory
    /// Several accounts are in view, so each row names the ones a post reached.
    var showsAccounts = false
    @Binding var selection: SourceActivity.ID?
    @Binding var filter: ActivityFilter
    let hasMore: Bool
    let loadMore: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredID: SourceActivity.ID?
    @State private var hoveredSaleID: String?
    @State private var listPosition = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let entries = ActivityListEntry.merged(posts: items, sales: sales, hasMorePosts: hasMore)
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    switch entry {
                    case .post(let item): row(item)
                    case .sale(let accountID, let sale): saleRow(accountID: accountID, sale)
                    }
                    if index < entries.count - 1 {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(isSelected(entry) || isSelected(entries[index + 1]) ? 0 : 1)
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
                    L10n.string(filter == .waiting ? "Nothing is waiting for you" : "No trades yet"),
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
            ActivityInboxRow(
                item: item, guruName: directory.name(for: item.guruID), preview: directory.preview(of: item),
                showsAccounts: showsAccounts
            )
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

    private func isSelected(_ entry: ActivityListEntry) -> Bool {
        if case .post(let item) = entry { return item.id == selection }
        return false
    }

    private func saleRow(accountID: String, _ sale: AccountFeedItem) -> some View {
        let entryID = ActivityListEntry.sale(accountID: accountID, sale).id
        let post = items.first { post in
            post.destinations.contains { $0.orders.contains { $0.clientID == sale.orderID } }
        }
        return Button {
            if let post {
                selection = post.id
                focused = true
            }
        } label: {
            ActivitySaleRow(accountID: accountID, item: sale, showsAccount: showsAccounts)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hoveredSaleID == entryID ? Palette.hover : .clear, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .disabled(post == nil)
        .onHover { isHovering in
            hoveredSaleID = isHovering ? entryID : (hoveredSaleID == entryID ? nil : hoveredSaleID)
        }
        .accessibilityHint(post == nil ? "" : L10n.string("Open the post that bought these shares."))
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
