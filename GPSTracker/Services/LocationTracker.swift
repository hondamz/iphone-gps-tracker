import CoreLocation
import Foundation
import Observation
import SwiftData

/// Erfasst die Position über die offizielle CoreLocation-API (`CLLocationUpdate.liveUpdates`)
/// oder – in einer Simulations-Betriebsart – über den `LocationSimulator`, und speichert einen
/// neuen Punkt nur, wenn sich das Gerät bewegt hat (Mindestabstand + Genauigkeitsfilter).
@Observable
final class LocationTracker {
    /// Letzte vom System gemeldete Position (auch wenn sie nicht gespeichert wurde).
    private(set) var lastLocation: CLLocation?
    private(set) var isStationary = false
    private(set) var isRunning = false
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var accuracyAuthorization: CLAccuracyAuthorization
    /// Hinweis aus den Diagnose-Flags von CoreLocation (z. B. Berechtigung fehlt).
    private(set) var diagnostic: String?
    /// Zähler, ändert sich bei jedem gespeicherten Punkt (für abhängige Ansichten).
    private(set) var storedSinceLaunch = 0
    /// Aktive Simulations-Betriebsart (`.off` = echtes GPS).
    private(set) var activeSimulation: SimulationMode = .off
    /// Name der gerade simulierten Route.
    private(set) var simulationRouteName: String?

    var isSimulating: Bool { activeSimulation != .off }

    @ObservationIgnored var onPointStored: (() -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var lastStoredLocation: CLLocation?
    @ObservationIgnored private let simulator = LocationSimulator()

    init(context: ModelContext, settings: SettingsStore) {
        self.context = context
        self.settings = settings
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        reloadLastStored()
    }

    /// Startet die Aufzeichnung. Muss beim ersten Mal im Vordergrund aufgerufen werden,
    /// damit die Hintergrund-Sitzung gültig ist; beim App-Start im Hintergrund wird sie
    /// erneut aufgebaut, damit iOS die Updates weiterliefert.
    func start() {
        guard updatesTask == nil else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        isRunning = true
        activeSimulation = settings.simulationMode
        if isSimulating {
            diagnostic = nil
            isStationary = false
            simulator.start(
                mode: activeSimulation, speedFactor: settings.simulationSpeed,
                onRoute: { [weak self] name in self?.simulationRouteName = name },
                onLocation: { [weak self] location in self?.handle(location, source: self?.activeSimulation.source ?? "") }
            )
        }
        // Die echten Updates laufen auch bei Simulation weiter: sie halten die App im
        // Hintergrund aktiv, ihre Positionen werden dann aber nicht verwendet.
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, !Task.isCancelled else { break }
                    self.handle(update)
                }
            } catch {
                self?.diagnostic = "Standortdienst beendet: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        simulator.stop()
        activeSimulation = .off
        simulationRouteName = nil
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        isRunning = false
        isStationary = false
    }

    /// Fragt die Berechtigung „Immer“ an (Upgrade von „Beim Verwenden“).
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Nach Wechsel der Simulations-Betriebsart oder des Zeitraffers neu starten.
    func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    func refreshAuthorization() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    /// Nach Löschen oder Wiederherstellen der Daten den Bezugspunkt neu laden.
    func reloadLastStored() {
        var descriptor = FetchDescriptor<TrackPoint>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        lastStoredLocation = (try? context.fetch(descriptor))?.first?.location
    }

    private func handle(_ update: CLLocationUpdate) {
        refreshAuthorization()
        guard !isSimulating else { return }
        isStationary = update.stationary
        diagnostic = Self.describe(update)
        guard let location = update.location else { return }
        handle(location, source: TrackPoint.gpsSource)
    }

    private func handle(_ location: CLLocation, source: String) {
        lastLocation = location
        guard shouldStore(location) else { return }

        context.insert(TrackPoint(location: location, source: source, tripCategory: settings.tripCategory))
        do {
            try context.save()
        } catch {
            diagnostic = "Speichern fehlgeschlagen: \(error.localizedDescription)"
            return
        }
        lastStoredLocation = location
        storedSinceLaunch += 1
        onPointStored?()
    }

    private func shouldStore(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= settings.maxAccuracy else {
            return false
        }
        guard let last = lastStoredLocation else { return true }
        return location.distance(from: last) >= settings.minDistance
    }

    private static func describe(_ update: CLLocationUpdate) -> String? {
        if update.authorizationDeniedGlobally { return "Ortungsdienste sind auf dem Gerät ausgeschaltet." }
        if update.authorizationDenied { return "Standortzugriff wurde verweigert." }
        if update.authorizationRequestInProgress { return "Warte auf Freigabe des Standortzugriffs …" }
        if update.insufficientlyInUse { return "App muss für den Start im Vordergrund sein." }
        if update.locationUnavailable { return "Position aktuell nicht verfügbar." }
        if update.accuracyLimited { return "Nur ungefähre Position freigegeben." }
        return nil
    }
}
