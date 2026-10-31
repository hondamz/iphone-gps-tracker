import CoreLocation
import Foundation
import SwiftData

/// Ein gespeicherter GPS-Messpunkt. Werte < 0 bei Genauigkeit/Geschwindigkeit/Kurs bedeuten
/// „ungültig“ (CoreLocation-Konvention) und werden unverändert übernommen.
@Model
final class TrackPoint {
    #Index<TrackPoint>([\.timestamp])

    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var ellipsoidalAltitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var speed: Double
    var speedAccuracy: Double
    var course: Double
    var courseAccuracy: Double
    /// Zeitpunkt der erfolgreichen Übertragung je Serverziel (1–4); `nil` = noch nicht übertragen.
    /// Ziel 1 übernimmt den Status aus v0.1 (Feld `uploadedAt`).
    @Attribute(originalName: "uploadedAt") var uploadedAt1: Date?
    var uploadedAt2: Date?
    var uploadedAt3: Date?
    var uploadedAt4: Date?
    /// Software-Version, mit der der Punkt aufgezeichnet wurde (`nil` = vor v0.3.0).
    var appVersion: String?
    /// Herkunft: "gps" oder "simulation-<betriebsart>".
    var source: String = TrackPoint.gpsSource
    /// Art der Strecke: "private" oder "business" (`nil` = vor v0.10.0 aufgezeichnet).
    var tripCategory: String?

    static let gpsSource = "gps"

    init(location: CLLocation, source: String = TrackPoint.gpsSource, tripCategory: TripCategory? = nil,
         appVersion: String = AppInfo.version) {
        id = UUID()
        timestamp = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        ellipsoidalAltitude = location.ellipsoidalAltitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        course = location.course
        courseAccuracy = location.courseAccuracy
        self.appVersion = appVersion
        self.source = source
        self.tripCategory = tripCategory?.rawValue
    }

    init(record: TrackPointRecord) {
        id = record.id
        timestamp = record.timestamp
        latitude = record.latitude
        longitude = record.longitude
        altitude = record.altitude
        ellipsoidalAltitude = record.ellipsoidalAltitude
        horizontalAccuracy = record.horizontalAccuracy
        verticalAccuracy = record.verticalAccuracy
        speed = record.speed
        speedAccuracy = record.speedAccuracy
        course = record.course
        courseAccuracy = record.courseAccuracy
        uploadedAt1 = record.uploadedAt1
        uploadedAt2 = record.uploadedAt2
        uploadedAt3 = record.uploadedAt3
        uploadedAt4 = record.uploadedAt4
        appVersion = record.appVersion
        source = record.source ?? TrackPoint.gpsSource
        tripCategory = record.tripCategory
    }

    var isSimulated: Bool { source != TrackPoint.gpsSource }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    func uploadedAt(target: Int) -> Date? {
        switch target {
        case 1: uploadedAt1
        case 2: uploadedAt2
        case 3: uploadedAt3
        default: uploadedAt4
        }
    }

    func setUploadedAt(_ date: Date?, target: Int) {
        switch target {
        case 1: uploadedAt1 = date
        case 2: uploadedAt2 = date
        case 3: uploadedAt3 = date
        default: uploadedAt4 = date
        }
    }

    /// Punkte, die an das Serverziel noch nicht übertragen wurden.
    static func pending(target: Int) -> Predicate<TrackPoint> {
        switch target {
        case 1: return #Predicate { $0.uploadedAt1 == nil }
        case 2: return #Predicate { $0.uploadedAt2 == nil }
        case 3: return #Predicate { $0.uploadedAt3 == nil }
        default: return #Predicate { $0.uploadedAt4 == nil }
        }
    }
}

/// Austauschformat für Backup und Server-Übertragung (entkoppelt vom SwiftData-Modell).
nonisolated struct TrackPointRecord: Codable, Sendable, Hashable {
    var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var ellipsoidalAltitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var speed: Double
    var speedAccuracy: Double
    var course: Double
    var courseAccuracy: Double
    var uploadedAt1: Date?
    var uploadedAt2: Date?
    var uploadedAt3: Date?
    var uploadedAt4: Date?
    var appVersion: String?
    var source: String?
    var tripCategory: String?
}

nonisolated extension TrackPointRecord {
    private enum LegacyKeys: String, CodingKey { case uploadedAt }

    /// Liest auch Backups aus v0.1 (ein einziges Feld `uploadedAt` → Ziel 1).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        altitude = try c.decode(Double.self, forKey: .altitude)
        ellipsoidalAltitude = try c.decode(Double.self, forKey: .ellipsoidalAltitude)
        horizontalAccuracy = try c.decode(Double.self, forKey: .horizontalAccuracy)
        verticalAccuracy = try c.decode(Double.self, forKey: .verticalAccuracy)
        speed = try c.decode(Double.self, forKey: .speed)
        speedAccuracy = try c.decode(Double.self, forKey: .speedAccuracy)
        course = try c.decode(Double.self, forKey: .course)
        courseAccuracy = try c.decode(Double.self, forKey: .courseAccuracy)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        uploadedAt1 = try c.decodeIfPresent(Date.self, forKey: .uploadedAt1)
            ?? legacy.decodeIfPresent(Date.self, forKey: .uploadedAt)
        uploadedAt2 = try c.decodeIfPresent(Date.self, forKey: .uploadedAt2)
        uploadedAt3 = try c.decodeIfPresent(Date.self, forKey: .uploadedAt3)
        uploadedAt4 = try c.decodeIfPresent(Date.self, forKey: .uploadedAt4)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        tripCategory = try c.decodeIfPresent(String.self, forKey: .tripCategory)
    }
}

extension TrackPointRecord {

    init(_ point: TrackPoint) {
        self.init(
            id: point.id,
            timestamp: point.timestamp,
            latitude: point.latitude,
            longitude: point.longitude,
            altitude: point.altitude,
            ellipsoidalAltitude: point.ellipsoidalAltitude,
            horizontalAccuracy: point.horizontalAccuracy,
            verticalAccuracy: point.verticalAccuracy,
            speed: point.speed,
            speedAccuracy: point.speedAccuracy,
            course: point.course,
            courseAccuracy: point.courseAccuracy,
            uploadedAt1: point.uploadedAt1,
            uploadedAt2: point.uploadedAt2,
            uploadedAt3: point.uploadedAt3,
            uploadedAt4: point.uploadedAt4,
            appVersion: point.appVersion,
            source: point.source,
            tripCategory: point.tripCategory
        )
    }
}
