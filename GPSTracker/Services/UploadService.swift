import BackgroundTasks
import Foundation
import Observation
import SwiftData

/// Laufzeitstatus eines Serverziels.
nonisolated struct TargetStatus: Sendable {
    var isUploading = false
    var lastError: String?
    var pendingCount = 0
}

/// Steuert die Übertragung an alle aktiven Serverziele gemäß Übertragungsmodus.
/// Jedes Ziel hat seinen eigenen Rückstand; ein ausgefallenes Ziel blockiert die anderen nicht.
@Observable
final class UploadService {
    static let refreshTaskID = "io.github.hondamz.gpstracker.upload"
    private static let batchSize = 500

    private(set) var status: [Int: TargetStatus] = [:]
    /// Fehler, der kein einzelnes Ziel betrifft (z. B. kein Ziel aktiv).
    private(set) var generalError: String?

    @ObservationIgnored var uploader: any TrackUploader = ProvisionalJSONUploader()
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var liveTask: Task<Void, Never>?

    init(context: ModelContext, settings: SettingsStore) {
        self.context = context
        self.settings = settings
        refreshPendingCount()
    }

    var isUploading: Bool { status.values.contains { $0.isUploading } }

    func status(for target: Int) -> TargetStatus { status[target] ?? TargetStatus() }

    /// Summe der offenen Punkte über alle aktiven Ziele.
    var pendingCountEnabled: Int {
        settings.enabledTargets.reduce(0) { $0 + status(for: $1.id).pendingCount }
    }

    func refreshPendingCount() {
        for id in ServerTarget.slots {
            let descriptor = FetchDescriptor<TrackPoint>(predicate: TrackPoint.pending(target: id))
            status[id, default: TargetStatus()].pendingCount = (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    /// Wird nach jedem gespeicherten Punkt aufgerufen.
    func pointStored() {
        refreshPendingCount()
        switch settings.uploadMode {
        case .live: scheduleLiveUpload()
        case .scheduled: Task { await uploadIfScheduledDue() }
        case .manual: break
        }
    }

    /// Live-Modus: Punkte über das Sammelintervall bündeln, dann senden.
    private func scheduleLiveUpload() {
        guard liveTask == nil else { return }
        let delay = settings.liveIntervalSeconds
        liveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.liveTask = nil
            await self.uploadPending()
        }
    }

    /// Überträgt an alle aktiven Ziele. `true`, wenn alle erfolgreich waren.
    @discardableResult
    func uploadPending() async -> Bool {
        let targets = settings.enabledTargets
        guard !targets.isEmpty else {
            generalError = "Kein Serverziel aktiv."
            return false
        }
        generalError = nil
        var allOK = true
        for target in targets {
            let ok = await upload(to: target.id)
            allOK = allOK && ok
        }
        return allOK
    }

    /// Überträgt alle offenen Punkte an ein Ziel in Paketen. `true` bei Erfolg.
    @discardableResult
    func upload(to id: Int) async -> Bool {
        guard !status(for: id).isUploading, let target = settings.target(id) else { return false }
        guard let server = settings.serverConfig(for: target) else {
            status[id, default: TargetStatus()].lastError = "Keine gültige Serveradresse (http/https) eingetragen."
            return false
        }
        status[id, default: TargetStatus()].isUploading = true
        defer { status[id, default: TargetStatus()].isUploading = false }
        do {
            while true {
                var descriptor = FetchDescriptor<TrackPoint>(
                    predicate: TrackPoint.pending(target: id),
                    sortBy: [SortDescriptor(\.timestamp)]
                )
                descriptor.fetchLimit = Self.batchSize
                let batch = try context.fetch(descriptor)
                if batch.isEmpty { break }
                try await uploader.upload(batch.map(TrackPointRecord.init), to: server)
                let now = Date.now
                for point in batch { point.setUploadedAt(now, target: id) }
                try context.save()
                if batch.count < Self.batchSize { break }
            }
            settings.updateTarget(id) { $0.lastUploadAt = .now }
            status[id, default: TargetStatus()].lastError = nil
            refreshPendingCount()
            return true
        } catch {
            status[id, default: TargetStatus()].lastError = error.localizedDescription
            refreshPendingCount()
            return false
        }
    }

    /// Markiert alle Punkte für ein Ziel als übertragen (Rückstand verwerfen)
    /// oder als offen (alles erneut senden).
    func setAllUploaded(_ uploaded: Bool, target id: Int) {
        guard let points = try? context.fetch(FetchDescriptor<TrackPoint>()) else { return }
        let date: Date? = uploaded ? .now : nil
        for point in points { point.setUploadedAt(date, target: id) }
        try? context.save()
        if uploaded { status[id, default: TargetStatus()].lastError = nil }
        refreshPendingCount()
    }

    // MARK: - Zeitgesteuerte Übertragung

    /// Nächster geplanter Lauf; liegt er in der Vergangenheit, ist die Übertragung fällig.
    var nextScheduledRun: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings.scheduledMinutes * 60))
        if let last = settings.lastScheduledRunAt, last >= today {
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
    }

    func uploadIfScheduledDue() async {
        guard settings.uploadMode == .scheduled, nextScheduledRun <= .now else { return }
        if await uploadPending() {
            settings.lastScheduledRunAt = .now
        }
        scheduleBackgroundRefresh()
    }

    /// Meldet bei iOS einen Hintergrundlauf zum nächsten geplanten Zeitpunkt an.
    func scheduleBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        guard settings.uploadMode == .scheduled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = max(nextScheduledRun, .now)
        try? BGTaskScheduler.shared.submit(request)
    }
}
