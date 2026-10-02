import SwiftUI

/// The chart's day, with a native calendar that stays open while choosing a date.
struct DayPickerButton: View {
    @Binding var day: Date
    @State private var isPicking = false

    @MainActor private var title: String {
        Calendar.current.isDateInToday(day)
            ? L10n.string("Today")
            : day.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguagePreference.shared.language.locale)
            )
    }

    var body: some View {
        Button {
            isPicking.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .foregroundStyle(Palette.secondaryInk)
        }
        .buttonStyle(FloatingControlButtonStyle(isActive: isPicking))
        .accessibilityLabel(L10n.string("Chart day, %@", title))
        .accessibilityIdentifier("today.day")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            FloatingPanelSurface(
                title: L10n.string("Chart day"),
                subtitle: day.formatted(
                    .dateTime.weekday(.wide).month(.wide).day().year().locale(AppLanguagePreference.shared.language.locale)
                )
            ) {
                VStack(spacing: 16) {
                    DatePicker(L10n.string("Day"), selection: $day, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    HStack {
                        Button(L10n.string("Today")) { day = .now }
                            .disabled(Calendar.current.isDateInToday(day))
                        Spacer()
                        Button(L10n.string("Done")) { isPicking = false }
                            .keyboardShortcut(.defaultAction)
                    }
                    .buttonStyle(FloatingControlButtonStyle())
                }
            }
            .frame(width: 240)
            .onExitCommand { isPicking = false }
        }
    }
}
