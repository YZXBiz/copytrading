import DesktopCore
import SwiftUI

/// The two things the owner works with, each account and each guru, above the pages that set
/// them up. Before a setup is saved, only those pages show.
struct SidebarView<Header: View>: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        let configuration = model.savedTradingConfiguration
        let gurus = GuruDirectory(configuration).gurus
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let accounts = configuration?.accounts, !accounts.isEmpty {
                    SidebarGroupTitle(title: "Accounts")
                    ForEach(accounts) { account in
                        SidebarAccountRow(account: account, model: model, accountFeature: accountFeature)
                    }
                }
                if !gurus.isEmpty {
                    SidebarGroupTitle(title: "People")
                        .padding(.top, 16)
                    ForEach(gurus) { guru in
                        SidebarGuruRow(guru: guru, model: model, accountFeature: accountFeature)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
        .navigationTitle(L10n.string("CopyTrading"))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header()
                SidebarBrandCard(model: model)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusFooter(model: model)
        }
        .background { SidebarPanelBackground() }
    }
}
