import SwiftData
import SwiftUI

@main
struct GPSTrackerApp: App {
    private let container: ModelContainer
    private let settings: SettingsStore
    private let tracker: LocationTracker
    private let uploads: UploadService
    private let backup: BackupService

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Ordner vorab anlegen, sonst meldet CoreData beim allerersten Start einen Fehler.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        do {
            container = try ModelContainer(for: TrackPoint.self)
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
        let context = container.mainContext
        let settings = SettingsStore()
        let uploads = UploadService(context: context, settings: settings)
        let tracker = LocationTracker(context: context, settings: settings)
        tracker.onPointStored = { [weak uploads] in uploads?.pointStored() }

        self.settings = settings
        self.tracker = tracker
        self.uploads = uploads
        backup = BackupService(context: context, settings: settings)

        // Aufzeichnung nach (Hintergrund-)Neustart der App fortsetzen.
        if settings.trackingEnabled { tracker.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(tracker)
                .environment(uploads)
                .environment(backup)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            tracker.refreshAuthorization()
            uploads.refreshPendingCount()
            Task { await uploads.uploadIfScheduledDue() }
            uploads.scheduleBackgroundRefresh()
        }
        .backgroundTask(.appRefresh(UploadService.refreshTaskID)) { [uploads] in
            await uploads.uploadIfScheduledDue()
        }
    }
}
