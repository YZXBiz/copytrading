import Foundation
import Testing

/// Settings → Backups colors a note by what it means, never by searching its words, so a
/// problem reads as one in every language.
@MainActor
func runBackupRestoreNoteTests() async throws {
    let model = AppModel()
    await model.createOperationalBackup(to: URL(fileURLWithPath: "/nowhere/backup.zip"))
    let refused = try #require(model.backupRestoreNote, "a backup without an engine said nothing")
    try #require(refused.kind == .problem && refused.tone == .caution, "a refused backup did not read as a problem")

    await model.previewOperationalRestore(from: URL(fileURLWithPath: "/nowhere/backup.zip"))
    try #require(model.backupRestoreNote?.kind == .problem, "a refused restore preview did not read as a problem")

    try #require(BackupRestoreNote.done("Saved.").tone == .positive, "a finished backup did not read as done")
    try #require(BackupRestoreNote.working("Checking…").tone == .neutral, "work in progress read as an outcome")
}
