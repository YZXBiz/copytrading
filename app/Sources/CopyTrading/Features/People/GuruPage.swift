import DesktopCore
import SwiftUI

/// One guru as a page in the main window. A stand-in that shows the guru's card until the guru
/// page is built out.
struct GuruPage: View {
    let guruID: String
    let model: AppModel
    let feature: AccountFeatureModel

    init(guruID: String, model: AppModel, feature: AccountFeatureModel) {
        self.guruID = guruID
        self.model = model
        self.feature = feature
    }

    private var guru: GuruDirectory.Guru? {
        GuruDirectory(model.savedTradingConfiguration).gurus.first { $0.id == guruID }
    }

    var body: some View {
        Group {
            if let guru {
                GuruDetailView(model: model, feature: feature, guru: guru, openPost: { _ in }, edit: edit)
            } else {
                ContentUnavailableView(L10n.string("This guru is not in your setup"), systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .background(Palette.page)
        .navigationTitle(guru?.name ?? guruID)
    }

    private func edit() {
        model.editGuru(guruID)
    }
}
