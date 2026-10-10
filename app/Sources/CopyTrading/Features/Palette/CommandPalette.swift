import DesktopCore
import SwiftUI

/// ⌘K (or ⌘F): one field that finds a page, a safe action, or a guru's post by its words, chosen
/// with the arrow keys and Return. Starting copying is left to its own button, which checks live
/// accounts first; nothing here can place an order.
struct CommandPalette: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private var items: [PaletteItem] {
        let pages = model.navigableScreens.map { screen in
            PaletteItem(
                id: "page.\(screen.identifier)", kind: .page, title: model.title(of: screen),
                detail: pageKind(screen), symbol: screen.symbol
            ) { model.selectedScreen = screen }
        }
        var actions: [PaletteItem] = []
        if model.isCopying {
            actions.append(
                PaletteItem(id: "action.pause", kind: .action, title: L10n.string("Pause Copying"), symbol: "pause.fill") {
                    Task { await model.pauseTrading() }
                })
        }
        for account in model.savedTradingConfiguration?.accounts ?? [] {
            actions.append(
                PaletteItem(
                    id: "action.limits.\(account.id)", kind: .action, title: L10n.string("Edit Limits"), detail: account.id,
                    symbol: "slider.horizontal.3"
                ) {
                    model.selectedScreen = .account(account.id)
                    model.editAccount(named: account.id, focus: .limits)
                })
        }
        actions.append(
            PaletteItem(id: "action.assistant", kind: .action, title: L10n.string("Ask the Assistant"), symbol: "sparkle") {
                model.assistant.isOpen = true
            })
        let directory = GuruDirectory(model.savedTradingConfiguration)
        let posts = accountFeature.activity.compactMap { post -> PaletteItem? in
            let text = post.readableText()
            guard !text.isEmpty, let guruID = post.guruID else { return nil }
            return PaletteItem(
                id: "post.\(post.id)", kind: .post, title: "“\(text)”",
                detail: [directory.name(for: guruID), Humanize.feedTime(post.sourceAt)].compactMap(\.self).joined(separator: " · "),
                symbol: "text.quote"
            ) { model.selectedScreen = .guru(guruID) }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // Posts only answer a search; an empty field lists the pages and actions.
        return (pages + actions).filter { $0.matches(trimmed) }
            + (trimmed.isEmpty ? [] : Array(posts.filter { $0.matches(trimmed) }.prefix(20)))
    }

    var body: some View {
        let items = self.items
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
                TextField(
                    L10n.string("Go to a page, run an action, or find a post"), text: $query,
                    prompt: Text(L10n.string("Go to a page, run an action, or find a post")).foregroundStyle(Palette.tertiaryInk)
                )
                .textFieldStyle(.plain)
                .font(DesignTokens.bodyText.weight(.medium))
                .focused($isFocused)
                .onSubmit { choose(items) }
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, max(items.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .accessibilityIdentifier("palette.field")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isHighlighted: index == highlighted)
                                .id(index)
                                .onTapGesture {
                                    highlighted = index
                                    choose(items)
                                }
                        }
                        if items.isEmpty {
                            Text(L10n.string("Nothing matches."))
                                .font(DesignTokens.bodyText)
                                .foregroundStyle(Palette.tertiaryInk)
                                .padding(20)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 560)
        .background(Palette.page, in: .rect(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        .onAppear { isFocused = true }
        .onChange(of: query) { highlighted = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Command palette"))
    }

    private func row(_ item: PaletteItem, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .frame(width: 20)
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            Text(item.title)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .markerHighlight(isHighlighted)
            if let detail = item.detail {
                Text(detail)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isHighlighted {
                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private func pageKind(_ screen: AppModel.Screen) -> String? {
        switch screen {
        case .account: L10n.string("Account")
        case .guru: L10n.string("Guru")
        default: nil
        }
    }

    private func choose(_ items: [PaletteItem]) {
        guard items.indices.contains(highlighted) else { return }
        let item = items[highlighted]
        close()
        item.run()
    }

    private func close() {
        model.isShowingPalette = false
    }
}
