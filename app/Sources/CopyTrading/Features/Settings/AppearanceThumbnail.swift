import SwiftUI

/// A small picture of the app in one appearance, for System, Light, and Dark: a
/// window on a desktop with a sidebar, a title, and a rising line. System shows both halves.
struct AppearanceThumbnail: View {
    let appearance: AppAppearance

    var body: some View {
        ZStack {
            switch appearance {
            case .system:
                HStack(spacing: 0) {
                    scene(dark: false)
                        .frame(width: 60, alignment: .leading)
                        .clipped()
                    scene(dark: true)
                        .frame(width: 60, alignment: .trailing)
                        .clipped()
                }
            case .light:
                scene(dark: false)
            case .dark:
                scene(dark: true)
            }
        }
        .frame(width: 120, height: 76)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private func scene(dark: Bool) -> some View {
        let desktop: [Color] =
            dark
            ? [Color(red: 0.24, green: 0.27, blue: 0.34), Color(red: 0.13, green: 0.15, blue: 0.19)]
            : [Color(red: 0.80, green: 0.88, blue: 0.93), Color(red: 0.88, green: 0.92, blue: 0.95)]
        let window = dark ? Color(white: 0.13) : .white
        let sidebar = dark ? Color(white: 0.18) : Color(white: 0.93)
        let ink = dark ? Color(white: 0.75) : Color(white: 0.35)
        return ZStack {
            LinearGradient(colors: desktop, startPoint: .top, endPoint: .bottom)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4, id: \.self) { row in
                        Capsule().fill(ink.opacity(row == 1 ? 0.5 : 0.22)).frame(width: row == 1 ? 14 : 11, height: 2.5)
                    }
                }
                .padding(.top, 8)
                .frame(width: 24, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(sidebar)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(ink.opacity(0.6)).frame(width: 22, height: 3)
                    RisingLine()
                        .stroke(
                            Color(red: 0.2, green: 0.78, blue: 0.62), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                        )
                        .frame(height: 22)
                    Capsule().fill(ink.opacity(0.2)).frame(width: 40, height: 2.5)
                    Capsule().fill(ink.opacity(0.2)).frame(width: 30, height: 2.5)
                }
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(window)
            .clipShape(.rect(cornerRadius: 5))
            .frame(width: 92, height: 56)
            .offset(y: 6)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .frame(width: 120, height: 76)
    }
}
