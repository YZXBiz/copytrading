import SwiftUI

/// The four screens a trader comes back to, each with what it answers.
struct GuideDaySection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            GuideScreenRow(
                screen: .today,
                text:
                    "Did you make or lose money today? **Today** shows your accounts' equity, the curve since the open, what your gurus posted, and how close each account is to its limits.",
                open: { open(.today) }
            ) {
                TodayMiniFigure()
            }
            GuideScreenRow(
                screen: .activity,
                text:
                    "Every post, read as what it asked for, with what each account did about it. A post CopyTrading couldn't read with confidence waits under **Needs Review** until you decide.",
                open: { open(.activity) }
            ) {
                ActivityMiniFigure()
            }
            GuideScreenRow(
                screen: .people,
                text:
                    "The gurus you copy: their latest call, how their calls went, and which accounts follow them. Add or change a guru here.",
                open: { open(.people) }
            ) {
                PeopleMiniFigure()
            }
            GuideScreenRow(
                screen: .accounts,
                text:
                    "Each broker account's balance, positions, and limits. **Enable Entries** lets an account buy; **Pause Entries** stops new buys while exits still follow your rules.",
                open: { open(.accounts) }
            ) {
                AccountsMiniFigure()
            }
        }
    }

    private func open(_ screen: AppModel.Screen) {
        model.selectedScreen = screen
    }
}
