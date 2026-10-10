import DesktopCore
import SwiftUI

/// The assistant's right-hand panel. It floats over the page (which never reflows) as a plain
/// white sheet with a hairline edge, and closes on Esc.
struct AssistantPanel: View {
    static let width: CGFloat = 380

    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    let activityState: ActivityScreenState
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var assistant: AssistantModel { model.assistant }

    var body: some View {
        VStack(spacing: 0) {
            header
            if assistant.messages.isEmpty {
                AssistantEmptyState(
                    hasModel: assistant.hasModel, suggestions: suggestions, ask: ask, openConnections: openConnections)
            } else {
                transcript
            }
            AssistantComposer(
                text: $draft, isAnswering: assistant.isAnswering, isEnabled: assistant.hasModel,
                isFocused: $isComposerFocused, send: { ask(draft) }, stop: stop
            )
            .padding([.horizontal, .bottom], 14)
            .padding(.top, 6)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Palette.page)
        .clipShape(.rect(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
                .strokeBorder(edge, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 24, x: -2, y: 8)
        .onExitCommand(perform: close)
        .onChange(of: assistant.focusRequest) { isComposerFocused = true }
        .task {
            // The panel slides in; focus asked for before it has landed can miss the field.
            isComposerFocused = true
            guard (try? await Task.sleep(for: .milliseconds(350))) != nil else { return }
            isComposerFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Assistant"))
        .accessibilityIdentifier("assistant.panel")
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !assistant.messages.isEmpty {
                headerButton(L10n.string("New Conversation"), symbol: "square.and.pencil", identifier: "assistant.reset") {
                    Task { await assistant.reset() }
                }
                .transition(.opacity)
            }
            Spacer()
            headerButton(L10n.string("Close"), symbol: "xmark", identifier: "assistant.close", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(height: 44)
    }

    private func headerButton(
        _ title: String, symbol: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .frame(width: 26, height: 26)
            .background(Palette.well, in: .circle)
            .help(title)
            .accessibilityIdentifier(identifier)
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(assistant.messages.enumerated()), id: \.element.id) { index, message in
                    AssistantMessageRow(
                        message: message,
                        isWriting: assistant.isAnswering && index == assistant.messages.count - 1,
                        model: model, follow: follow
                    )
                    .accessibilityIdentifier("assistant.message.\(index)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private var edge: Color {
        contrast == .increased ? Palette.secondaryInk : (colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.06))
    }

    private var suggestions: [String] {
        let directory = GuruDirectory(model.savedTradingConfiguration)
        let guru = directory.name(for: model.selectedScreen.guruID) ?? directory.gurus.first?.name
        return AssistantSuggestions.suggestions(for: model.selectedScreen, guru: guru, hasSelectedPost: selectedPost != nil)
    }

    private var selectedPost: SourceActivity? {
        accountFeature.activity.first { $0.id == activityState.selectedActivityID }
    }

    private func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !assistant.isAnswering, assistant.hasModel else { return }
        draft = ""
        let context = model.assistantContext(selectedPost: selectedPost)
        Task { await assistant.ask(text, context: context) }
    }

    private func stop() {
        Task { await assistant.stop() }
    }

    private func follow(_ link: AssistantLink) {
        model.follow(link, activity: accountFeature.activity) { id in
            activityState.focusActivity(id)
        }
    }

    private func openConnections() {
        model.selectedScreen = .connections
    }

    private func close() {
        assistant.isOpen = false
    }
}
