import DesktopCore
import SwiftUI

/// The gurus this setup copies, as cards: where they post, where their calls go, how they went.
/// Gurus are added and edited here; changes wait in the setup until it is checked and started.
struct PeopleView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    @State private var openGuru: GuruDirectory.Guru?
    @State private var guruToEdit: String?
    @State private var hoveredCardID: String?

    private var directory: GuruDirectory { GuruDirectory(model.savedTradingConfiguration) }

    /// Gurus in the setup that are not saved yet.
    private var draftOnlyRoutes: [TradingRouteDraft] {
        let saved = Set(directory.gurus.map(\.id))
        return model.setupDraft.routes.filter { !saved.contains($0.guruID.trimmed) }
    }

    private var cardCount: Int { directory.gurus.count + draftOnlyRoutes.count }

    var body: some View {
        GeometryReader { geometry in
            let available = min(max(0, geometry.size.width - DesignTokens.pagePadding * 2), DesignTokens.peopleContentMaxWidth)
            let columns = max(
                1,
                min(
                    cardCount,
                    Int(
                        (available + DesignTokens.personGallerySpacing)
                            / (DesignTokens.personCardMinWidth + DesignTokens.personGallerySpacing)
                    )))
            let galleryWidth =
                cardCount == 0
                ? min(available, 620)
                : min(
                    available,
                    CGFloat(columns) * DesignTokens.personCardMaxWidth
                        + CGFloat(columns - 1) * DesignTokens.personGallerySpacing)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.panelSpacing) {
                    PageHeader(
                        L10n.string("People"),
                        subtitle: cardCount == 0 ? nil : Humanize.count(cardCount, "guru"),
                        actions: {
                            RoundGlassButton(title: "Add Guru", symbol: "plus.circle.fill", action: model.addGuru)
                        })
                    if cardCount == 0 {
                        PeopleInvitation(addGuru: model.addGuru)
                            .padding(.top, 10)
                    } else {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: DesignTokens.personGallerySpacing, alignment: .topLeading),
                                count: columns),
                            alignment: .leading,
                            spacing: DesignTokens.personGallerySpacing
                        ) {
                            ForEach(directory.gurus) { guru in
                                Button {
                                    openGuru = guru
                                } label: {
                                    GuruCard(
                                        guru: guru,
                                        stats: GuruStats(guruID: guru.id, activity: feature.activity),
                                        latest: feature.activity.first { $0.guruID == guru.id },
                                        isHovered: hoveredCardID == guru.id,
                                        pendingNote: pendingNote(for: guru)
                                    )
                                }
                                .buttonStyle(QuietPressButtonStyle())
                                .onHover { hover(guru.id, $0) }
                                .accessibilityHint(L10n.string("Shows %@'s calls and where they are copied", guru.name))
                            }
                            ForEach(draftOnlyRoutes) { route in
                                Button {
                                    model.setupEditor = .route(route.id)
                                } label: {
                                    DraftGuruCard(
                                        route: route,
                                        channel: model.setupDraft.effectiveChannel(for: route),
                                        isHovered: hoveredCardID == route.guruID
                                    )
                                }
                                .buttonStyle(QuietPressButtonStyle())
                                .onHover { hover(route.guruID, $0) }
                                .accessibilityHint(L10n.string("Edits this guru"))
                                .accessibilityIdentifier("people.draftGuru")
                            }
                        }
                    }
                }
                .frame(width: galleryWidth, alignment: .leading)
                .padding([.horizontal, .bottom], DesignTokens.pagePadding)
                .padding(.top, DesignTokens.pageTopPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(L10n.string("People"))
        .onChange(of: model.requestedGuruID, initial: true) { _, id in
            guard let id else { return }
            model.requestedGuruID = nil
            openGuru = directory.gurus.first { $0.id == id }
        }
        // The assistant asks about the guru whose sheet is open, and no one once it closes.
        .onChange(of: openGuru?.id, initial: true) { _, id in model.openGuruID = id }
        .onDisappear { model.openGuruID = nil }
        .sheet(item: $openGuru, onDismiss: editAfterDetail) { guru in
            VStack(spacing: 0) {
                GuruDetailView(
                    model: model, feature: feature, guru: guru,
                    openPost: { item in
                        openGuru = nil
                        feature.focusedActivityID = item.id
                        model.selectedScreen = .activity
                    },
                    edit: {
                        guruToEdit = guru.id
                        openGuru = nil
                    })
                Divider()
                HStack {
                    Spacer()
                    Button(L10n.string("Done")) { openGuru = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(14)
            }
            .frame(minWidth: 560, minHeight: 420)
            .presentationBackground(Palette.canvas)
        }
    }

    /// A saved guru the unsaved setup removes or changes says so on their card.
    private func pendingNote(for guru: GuruDirectory.Guru) -> String? {
        guard model.hasUnsavedSetupChanges else { return nil }
        return model.setupDraft.routes.contains { $0.guruID.trimmed == guru.id } ? nil : "Removed — not saved yet"
    }

    private func hover(_ id: String, _ isHovering: Bool) {
        hoveredCardID = isHovering ? id : (hoveredCardID == id ? nil : hoveredCardID)
    }

    /// The editor opens once the detail sheet is gone, so the two never fight over the window.
    private func editAfterDetail() {
        guard let guruID = guruToEdit else { return }
        guruToEdit = nil
        model.editGuru(guruID)
    }
}
