import Foundation
import Observation
import UIKit

/// Simulations-Betriebsart: statt GPS werden Fahrten entlang hinterlegter Routen erzeugt.
nonisolated enum SimulationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, germany, cgnAirport

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Aus (echtes GPS)"
        case .germany: "Mainz, Paderborn & Deutschland"
        case .cgnAirport: "Flughafen Köln/Bonn"
        }
    }

    var explanation: String {
        switch self {
        case .off: "Positionen kommen vom GPS des iPhones."
        case .germany: "Zufällige Fahrten und Spaziergänge zwischen Orten/Wiesbaden, Paderborn/Borchen und Köln/Bonn (bevorzugt zu selten besuchten Orten), gelegentlich eine Fernfahrt in eine andere Region."
        case .cgnAirport: "Zufällige Wege zu Fuß und mit dem Fahrzeug über das ganze Flughafengelände (bevorzugt in bisher selten besuchte Bereiche), Follow-me-Fahrten auf den Rollwegen, gelegentlich Start und Landung – und ab und zu ein Ausflug mit Auto oder Bahn nach Köln oder Bonn und zurück."
        }
    }

    /// Wert für `TrackPoint.source`.
    var source: String { self == .off ? TrackPoint.gpsSource : "simulation-\(rawValue)" }
}

/// Übertragungsmodus zum Server.
nonisolated enum UploadMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case live, scheduled, manual

    var id: Self { self }

    var title: String {
        switch self {
        case .live: "Live"
        case .scheduled: "Zeitgesteuert"
        case .manual: "Nur manuell"
        }
    }

    var explanation: String {
        switch self {
        case .live: "Neue Punkte werden nahezu in Echtzeit gesammelt übertragen."
        case .scheduled: "Einmal täglich zur eingestellten Uhrzeit (iOS kann den Zeitpunkt etwas verschieben)."
        case .manual: "Keine automatische Übertragung – nur über „Jetzt übertragen“."
        }
    }
}

/// Vordefinierte Zeiträume für die Verlaufsansicht.
nonisolated enum HistoryRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case hour1, hours24, days7, days30, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .hour1: "1 Std."
        case .hours24: "24 Std."
        case .days7: "7 Tage"
        case .days30: "30 Tage"
        case .custom: "Eigener"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .hour1: 3600
        case .hours24: 86_400
        case .days7: 7 * 86_400
        case .days30: 30 * 86_400
        case .custom: nil
        }
    }
}

/// Ein konfigurierbares Serverziel (es gibt genau vier, IDs 1–4).
nonisolated struct ServerTarget: Codable, Sendable, Identifiable, Hashable {
    var id: Int
    var name: String
    var enabled: Bool
    var url: String
    var account: String
    /// Zeitpunkt der letzten erfolgreichen Übertragung an dieses Ziel.
    var lastUploadAt: Date?

    static let slots = [1, 2, 3, 4]

    /// Vorbelegung von Ziel 4 aus `PrivateDefaults.json` (nicht im Git, siehe
    /// Config/PrivateDefaults.example.json); `nil`, wenn die Datei fehlt.
    static let presetTarget4 = PrivateDefaults.shared?.serverTarget4

    /// Startwert eines Ziels: Ziel 4 ist – sofern `PrivateDefaults.json` vorhanden ist – mit dem eigenen
    /// Server vorbelegt (ausgeschaltet, bis das Passwort eingetragen ist), die übrigen sind leer.
    static func preset(_ id: Int) -> ServerTarget {
        guard id == 4, let p = presetTarget4 else { return .empty(id) }
        return ServerTarget(id: 4, name: p.name, enabled: false, url: p.url, account: p.account)
    }

    static func empty(_ id: Int) -> ServerTarget {
        ServerTarget(id: id, name: "Server \(id)", enabled: false, url: "", account: "")
    }

    /// Hinweis, wenn iOS die Adresse voraussichtlich blockiert: http zu einer Tailscale-IP
    /// (100.64.0.0/10) ist für App Transport Security kein „lokales Netz“.
    var transportWarning: String? {
        guard let url = validURL, url.scheme?.lowercased() == "http", let host = url.host() else { return nil }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100, (64...127).contains(parts[1]) else { return nil }
        return "iOS blockiert http zu Tailscale-IPs. Bitte den Tailscale-Namen verwenden, z. B. "
            + "http://<rechner>.<tailnet>.ts.net:\(url.port.map(String.init) ?? "80")\(url.path())"
    }

    /// `true`, wenn eine http(s)-Adresse mit Host eingetragen ist.
    var hasValidURL: Bool { validURL != nil }

    var validURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }
}

/// Art der aufgezeichneten Strecke; gilt für alle Punkte ab dem Umschalten.
nonisolated enum TripCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case personal = "private"
    case business

    var id: Self { self }

    var title: String {
        switch self {
        case .personal: "Privat"
        case .business: "Geschäftlich"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: "house.fill"
        case .business: "briefcase.fill"
        }
    }

    var toggled: TripCategory { self == .personal ? .business : .personal }
}

/// Kartenausschnitt der Live-Karte.
nonisolated enum MapScale: String, CaseIterable, Identifiable, Codable, Sendable {
    case local, km30, km100, km500

    var id: Self { self }

    var title: String {
        switch self {
        case .local: "Lokal"
        case .km30: "30 km"
        case .km100: "100 km"
        case .km500: "500 km"
        }
    }

    /// Breite des Ausschnitts in Metern; `nil` = automatisch auf die Umgebung des Trackers.
    var meters: Double? {
        switch self {
        case .local: nil
        case .km30: 30_000
        case .km100: 100_000
        case .km500: 500_000
        }
    }
}

/// Private Voreinstellungen (eigene Server-Adresse, Benutzer) aus `Resources/PrivateDefaults.json`.
/// Die Datei ist nicht versioniert; ohne sie startet die App ohne Vorbelegung.
nonisolated struct PrivateDefaults: Decodable, Sendable {
    struct Target: Decodable, Sendable {
        let name: String
        let url: String
        let account: String
    }

    let serverTarget4: Target?

    static let shared: PrivateDefaults? = {
        #if DEBUG
        guard let url = Bundle.main.url(forResource: "PrivateDefaults", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PrivateDefaults.self, from: data)
        #else
        return nil      // verteilte Builds (TestFlight) haben nie private Voreinstellungen
        #endif
    }()
}

/// Server-Zugangsdaten für eine Übertragung.
nonisolated struct ServerConfig: Sendable {
    let url: URL
    let account: String
    let password: String
    let deviceID: String
    let trackerName: String
}

/// Einstellungen, die im Backup enthalten sind (ohne Passwörter und Speicherziel).
nonisolated struct SettingsSnapshot: Codable, Sendable {
    var trackerName: String?
    var simulationMode: SimulationMode?
    var simulationSpeed: Int?
    var tripCategory: TripCategory?
    var mapScale: MapScale?
    var historyMapScale: MapScale?
    var targets: [ServerTarget]?
    /// Altformat v0.1 (ein einziger Server) – nur noch zum Einlesen alter Backups.
    var serverURL: String?
    var account: String?
    var uploadMode: UploadMode
    var scheduledMinutes: Int
    var liveIntervalSeconds: Int
    var minDistance: Double
    var maxAccuracy: Double
    var historyDefaultRange: HistoryRange
    var deviceID: String
}

/// Alle App-Einstellungen, persistiert in UserDefaults (Passwort in der Keychain).
@Observable
final class SettingsStore {
    private enum Key {
        static let trackingEnabled = "trackingEnabled"
        static let trackerName = "trackerName"
        static let simulationMode = "simulationMode"
        static let simulationSpeed = "simulationSpeed"
        static let tripCategory = "tripCategory"
        static let mapScale = "mapScale"
        static let historyMapScale = "historyMapScale"
        static let targets = "serverTargets"
        static let legacyServerURL = "serverURL"
        static let legacyAccount = "account"
        static let uploadMode = "uploadMode"
        static let scheduledMinutes = "scheduledMinutes"
        static let liveIntervalSeconds = "liveIntervalSeconds"
        static let minDistance = "minDistance"
        static let maxAccuracy = "maxAccuracy"
        static let historyDefaultRange = "historyDefaultRange"
        static let deviceID = "deviceID"
        static let backupFolderBookmark = "backupFolderBookmark"
        static let backupFolderName = "backupFolderName"
        static let lastScheduledRunAt = "lastScheduledRunAt"
        static let lastBackupAt = "lastBackupAt"
        static let legacyPasswordAccount = "server-password"
        static func passwordAccount(_ target: Int) -> String { "server-password-\(target)" }
    }

    @ObservationIgnored private let defaults: UserDefaults

    var trackingEnabled: Bool { didSet { defaults.set(trackingEnabled, forKey: Key.trackingEnabled) } }
    /// Name des Trackers, mit dem der Server die Geräte unterscheidet.
    var trackerName: String { didSet { defaults.set(trackerName, forKey: Key.trackerName) } }
    var simulationMode: SimulationMode { didSet { defaults.set(simulationMode.rawValue, forKey: Key.simulationMode) } }
    /// Zeitraffer der Simulation (1 = Echtzeit).
    var simulationSpeed: Int { didSet { defaults.set(simulationSpeed, forKey: Key.simulationSpeed) } }
    /// Art der aktuell aufgezeichneten Strecke (privat/geschäftlich).
    var tripCategory: TripCategory { didSet { defaults.set(tripCategory.rawValue, forKey: Key.tripCategory) } }
    /// Kartenausschnitt der Live-Karte (lokal automatisch oder feste Breite).
    var mapScale: MapScale { didSet { defaults.set(mapScale.rawValue, forKey: Key.mapScale) } }
    /// Kartenausschnitt im Verlauf (lokal = automatisch auf die ganze Spur).
    var historyMapScale: MapScale { didSet { defaults.set(historyMapScale.rawValue, forKey: Key.historyMapScale) } }
    /// Immer genau vier Serverziele (IDs 1–4); Passwörter liegen getrennt in der Keychain.
    var targets: [ServerTarget] { didSet { saveTargets() } }
    var uploadMode: UploadMode { didSet { defaults.set(uploadMode.rawValue, forKey: Key.uploadMode) } }
    /// Uhrzeit der zeitgesteuerten Übertragung in Minuten nach Mitternacht.
    var scheduledMinutes: Int { didSet { defaults.set(scheduledMinutes, forKey: Key.scheduledMinutes) } }
    /// Sammelintervall im Live-Modus (Sekunden zwischen neuem Punkt und Übertragung).
    var liveIntervalSeconds: Int { didSet { defaults.set(liveIntervalSeconds, forKey: Key.liveIntervalSeconds) } }
    /// Mindestabstand in Metern zum zuletzt gespeicherten Punkt.
    var minDistance: Double { didSet { defaults.set(minDistance, forKey: Key.minDistance) } }
    /// Punkte mit schlechterer horizontaler Genauigkeit (Meter) werden nicht gespeichert.
    var maxAccuracy: Double { didSet { defaults.set(maxAccuracy, forKey: Key.maxAccuracy) } }
    var historyDefaultRange: HistoryRange { didSet { defaults.set(historyDefaultRange.rawValue, forKey: Key.historyDefaultRange) } }
    /// Stabile Geräte-Kennung für den Server (wird mit dem Backup gesichert).
    var deviceID: String { didSet { defaults.set(deviceID, forKey: Key.deviceID) } }
    var backupFolderBookmark: Data? { didSet { defaults.set(backupFolderBookmark, forKey: Key.backupFolderBookmark) } }
    var backupFolderName: String? { didSet { defaults.set(backupFolderName, forKey: Key.backupFolderName) } }
    var lastScheduledRunAt: Date? { didSet { defaults.set(lastScheduledRunAt, forKey: Key.lastScheduledRunAt) } }
    var lastBackupAt: Date? { didSet { defaults.set(lastBackupAt, forKey: Key.lastBackupAt) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        trackingEnabled = defaults.bool(forKey: Key.trackingEnabled)
        trackerName = defaults.string(forKey: Key.trackerName) ?? Self.deviceName
        simulationMode = defaults.string(forKey: Key.simulationMode).flatMap(SimulationMode.init) ?? .off
        simulationSpeed = defaults.object(forKey: Key.simulationSpeed) as? Int ?? 1
        tripCategory = defaults.string(forKey: Key.tripCategory).flatMap(TripCategory.init) ?? .personal
        mapScale = defaults.string(forKey: Key.mapScale).flatMap(MapScale.init) ?? .local
        historyMapScale = defaults.string(forKey: Key.historyMapScale).flatMap(MapScale.init) ?? .local
        targets = Self.loadTargets(defaults)
        uploadMode = defaults.string(forKey: Key.uploadMode).flatMap(UploadMode.init) ?? .manual
        scheduledMinutes = defaults.object(forKey: Key.scheduledMinutes) as? Int ?? 22 * 60
        liveIntervalSeconds = defaults.object(forKey: Key.liveIntervalSeconds) as? Int ?? 10
        minDistance = defaults.object(forKey: Key.minDistance) as? Double ?? 10
        maxAccuracy = defaults.object(forKey: Key.maxAccuracy) as? Double ?? 50
        historyDefaultRange = defaults.string(forKey: Key.historyDefaultRange).flatMap(HistoryRange.init) ?? .hours24
        backupFolderBookmark = defaults.data(forKey: Key.backupFolderBookmark)
        backupFolderName = defaults.string(forKey: Key.backupFolderName)
        lastScheduledRunAt = defaults.object(forKey: Key.lastScheduledRunAt) as? Date
        lastBackupAt = defaults.object(forKey: Key.lastBackupAt) as? Date
        if let id = defaults.string(forKey: Key.deviceID) {
            deviceID = id
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: Key.deviceID)
        }
    }

    /// Vorschlag für den Tracker-Namen: Name des iPhones. Ohne Sonderberechtigung von Apple
    /// liefert iOS hier nur den Modellnamen (z. B. „iPhone“) – dann bitte selbst benennen.
    static var deviceName: String { UIDevice.current.name }

    /// Tracker-Name für die Übertragung (leer → Gerätename).
    var effectiveTrackerName: String {
        let name = trackerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Self.deviceName : name
    }

    var enabledTargets: [ServerTarget] { targets.filter(\.enabled) }

    func target(_ id: Int) -> ServerTarget? { targets.first { $0.id == id } }

    func updateTarget(_ id: Int, _ change: (inout ServerTarget) -> Void) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        change(&targets[index])
    }

    func password(for target: Int) -> String {
        KeychainStore.read(Key.passwordAccount(target)) ?? ""
    }

    func setPassword(_ password: String, for target: Int) {
        KeychainStore.save(password, for: Key.passwordAccount(target))
    }

    /// Gültige Serverkonfiguration oder `nil`, wenn keine http(s)-Adresse eingetragen ist.
    func serverConfig(for target: ServerTarget) -> ServerConfig? {
        guard let url = target.validURL else { return nil }
        return ServerConfig(url: url, account: target.account, password: password(for: target.id),
                            deviceID: deviceID, trackerName: effectiveTrackerName)
    }

    private func saveTargets() {
        defaults.set(try? JSONEncoder().encode(targets), forKey: Key.targets)
    }

    /// Lädt die Ziele; beim ersten Start nach v0.1 wird der bisherige Server zu Ziel 1.
    private static func loadTargets(_ defaults: UserDefaults) -> [ServerTarget] {
        if let data = defaults.data(forKey: Key.targets),
           let stored = try? JSONDecoder().decode([ServerTarget].self, from: data) {
            return normalized(stored)
        }
        var targets = ServerTarget.slots.map(ServerTarget.preset)
        let legacyURL = defaults.string(forKey: Key.legacyServerURL) ?? ""
        if !legacyURL.isEmpty {
            targets[0].url = legacyURL
            targets[0].account = defaults.string(forKey: Key.legacyAccount) ?? ""
            targets[0].enabled = true
            if let password = KeychainStore.read(Key.legacyPasswordAccount) {
                KeychainStore.save(password, for: Key.passwordAccount(1))
                KeychainStore.save("", for: Key.legacyPasswordAccount)
            }
        }
        defaults.removeObject(forKey: Key.legacyServerURL)
        defaults.removeObject(forKey: Key.legacyAccount)
        defaults.removeObject(forKey: "lastUploadAt")
        defaults.set(try? JSONEncoder().encode(targets), forKey: Key.targets)
        return targets
    }

    /// Stellt sicher, dass genau die Ziele 1–4 in dieser Reihenfolge vorhanden sind;
    /// fehlende (z. B. Ziel 4 nach dem Update von ≤ 0.5.0) bekommen ihren Startwert.
    private static func normalized(_ targets: [ServerTarget]) -> [ServerTarget] {
        ServerTarget.slots.map { id in targets.first { $0.id == id } ?? .preset(id) }
    }

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            trackerName: trackerName,
            simulationMode: simulationMode,
            simulationSpeed: simulationSpeed,
            tripCategory: tripCategory,
            mapScale: mapScale,
            historyMapScale: historyMapScale,
            targets: targets.map { var t = $0; t.lastUploadAt = nil; return t },
            uploadMode: uploadMode,
            scheduledMinutes: scheduledMinutes, liveIntervalSeconds: liveIntervalSeconds,
            minDistance: minDistance, maxAccuracy: maxAccuracy,
            historyDefaultRange: historyDefaultRange, deviceID: deviceID
        )
    }

    func apply(_ s: SettingsSnapshot) {
        if let name = s.trackerName { trackerName = name }
        if let mode = s.simulationMode { simulationMode = mode }
        if let speed = s.simulationSpeed { simulationSpeed = speed }
        if let category = s.tripCategory { tripCategory = category }
        if let scale = s.mapScale { mapScale = scale }
        if let scale = s.historyMapScale { historyMapScale = scale }
        if let restored = s.targets {
            targets = Self.normalized(restored).map { target in
                var t = target
                t.lastUploadAt = self.target(t.id)?.lastUploadAt
                return t
            }
        } else if let url = s.serverURL {
            updateTarget(1) {
                $0.url = url
                $0.account = s.account ?? ""
                $0.enabled = !url.isEmpty
            }
        }
        uploadMode = s.uploadMode
        scheduledMinutes = s.scheduledMinutes
        liveIntervalSeconds = s.liveIntervalSeconds
        minDistance = s.minDistance
        maxAccuracy = s.maxAccuracy
        historyDefaultRange = s.historyDefaultRange
        deviceID = s.deviceID
    }
}
