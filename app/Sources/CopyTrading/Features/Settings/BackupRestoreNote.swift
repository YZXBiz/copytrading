import Foundation

/// The latest word from a backup or restore, and whether it is progress, an outcome, or a problem.
struct BackupRestoreNote: Equatable {
    enum Kind: Equatable {
        case working
        case done
        case problem
    }

    let kind: Kind
    let text: String

    static func working(_ text: String) -> Self { Self(kind: .working, text: text) }
    static func done(_ text: String) -> Self { Self(kind: .done, text: text) }
    static func problem(_ text: String) -> Self { Self(kind: .problem, text: text) }
}

extension BackupRestoreNote {
    var tone: StatusTone {
        switch kind {
        case .working: .neutral
        case .done: .positive
        case .problem: .caution
        }
    }
}
