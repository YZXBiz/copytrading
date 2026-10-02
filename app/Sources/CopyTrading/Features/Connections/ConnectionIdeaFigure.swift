import SwiftUI

/// A small picture of where an idea happens:
/// Discord's channel menu, the browser's request headers, a key page, a Telegram chat. Decorative.
struct ConnectionIdeaFigure: View {
    let idea: ConnectionIdea
    @Environment(\.colorScheme) private var colorScheme

    private var paper: Color { colorScheme == .dark ? Color(white: 0.16) : .white }
    private var line: Color { Palette.hairline }

    var body: some View {
        content
            .font(.system(size: 10))
            .foregroundStyle(Palette.secondaryInk)
            .padding(12)
            .frame(width: 190, height: 136, alignment: .topLeading)
            .background(paper, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            .rotationEffect(.degrees(idea == .discordToken || idea == .telegram ? 2.5 : -2.5))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch idea {
        case .channelID: channelMenu
        case .discordToken: requestHeaders
        case .interpreterKey: keyPage
        case .telegram: chat
        }
    }

    private var channelMenu: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string("TRADING")).font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.tertiaryInk)
            channel("general")
            channel("trading-calls")
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Palette.group, in: .rect(cornerRadius: 4))
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                Text(L10n.string("Copy Channel ID"))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(red: 0.345, green: 0.396, blue: 0.949), in: .rect(cornerRadius: 5))
            .offset(x: 40)
        }
    }

    private var requestHeaders: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string("Request Headers")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink)
            headerRow("accept", "*/*")
            headerRow("authorization", "MTA4••••••••")
                .padding(3)
                .background(Color.yellow.opacity(0.25), in: .rect(cornerRadius: 3))
            headerRow("referer", "discord.com")
            headerRow("user-agent", "Mozilla/5.0")
        }
        .monospaced()
    }

    private var keyPage: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string("API Keys")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
            HStack {
                Text("CopyTrading").foregroundStyle(Palette.ink)
                Spacer()
                Text("sk-•••• 4f2a").monospaced()
            }
            Rectangle().fill(line).frame(height: 1)
            Text(L10n.string("Create Key"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Palette.ink, in: .capsule)
        }
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 6) {
            bubble("Bought 12 NVDA at $182.40 in primary")
            bubble("Skipped TSLA: entries are off")
            bubble("Sold 12 NVDA at $189.10")
        }
    }

    private func channel(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "number").foregroundStyle(Palette.tertiaryInk)
            Text(name)
        }
    }

    private func headerRow(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(Palette.ink)
            Text(value).lineLimit(1)
        }
        .font(.system(size: 9))
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(red: 0.86, green: 0.93, blue: 1.0).opacity(colorScheme == .dark ? 0.25 : 1), in: .rect(cornerRadius: 9))
    }
}
