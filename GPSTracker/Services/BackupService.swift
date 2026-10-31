import Foundation
import Observation
import SwiftData

/// Inhalt einer Backup-Datei (JSON).
nonisolated struct BackupFile: Codable, Sendable {
    var formatVersion = 2
    var createdAt: Date
    var appVersion: String
    var settings: SettingsSnapshot
    var points: [TrackPointRecord]
}

/// Sichert Einstellungen und GPS-Daten in einen frei wählbaren Ordner (Dateien-App:
/// iCloud Drive, lokal, SMB-Server, …) und stellt sie wieder her.
@Observable
final class BackupService {
    private(set) var isWorking = false
    private(set) var lastMessage: String?
    private(set) var lastError: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: SettingsStore

    init(context: ModelContext, settings: SettingsStore) {
        self.context = context
        self.settings = settings
    }

    /// Merkt sich den gewählten Ordner als Security-Scoped Bookmark.
    func setFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            settings.backupFolderBookmark = try url.bookmarkData()
            settings.backupFolderName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = "Ordner konnte nicht gemerkt werden: \(error.localizedDescription)"
        }
    }

    func createBackup() {
        guard let bookmark = settings.backupFolderBookmark else {
            lastError = "Bitte zuerst ein Speicherziel wählen."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            if stale { settings.backupFolderBookmark = try? folder.bookmarkData() }

            let points = try context.fetch(FetchDescriptor<TrackPoint>(sortBy: [SortDescriptor(\.timestamp)]))
            let backup = BackupFile(
                createdAt: .now,
                appVersion: AppInfo.fullVersion,
                settings: settings.snapshot,
                points: points.map(TrackPointRecord.init)
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backup)

            let file = folder.appending(path: "GPSTracker-Backup-\(Self.fileStamp.string(from: .now)).json")
            try data.write(to: file)
            settings.lastBackupAt = .now
            lastMessage = "\(points.count) Punkte gesichert in \(file.lastPathComponent)"
            lastError = nil
        } catch {
            lastError = "Backup fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Spielt ein Backup ein. Punkte werden über ihre ID zusammengeführt (keine Duplikate).
    func restore(from url: URL, includeSettings: Bool) {
        isWorking = true
        defer { isWorking = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(BackupFile.self, from: Data(contentsOf: url))
            for record in backup.points {
                context.insert(TrackPoint(record: record))
            }
            try context.save()
            if includeSettings { settings.apply(backup.settings) }
            lastMessage = "\(backup.points.count) Punkte aus Backup vom \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)) übernommen"
            lastError = nil
        } catch {
            lastError = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
