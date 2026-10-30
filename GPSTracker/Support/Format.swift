import CoreLocation
import SwiftUI

/// Einheitliche Formatierung der Messwerte.
enum Format {
    static func coordinate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(6)))
    }

    static func meters(_ value: Double, plusMinus: Bool = false) -> String {
        guard value >= 0 || !plusMinus else { return "–" }
        let text = value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " m"
        return plusMinus ? "± " + text : text
    }

    static func speed(_ metersPerSecond: Double) -> String {
        guard metersPerSecond >= 0 else { return "–" }
        return (metersPerSecond * 3.6).formatted(.number.precision(.fractionLength(1))) + " km/h"
    }

    static func course(_ degrees: Double) -> String {
        guard degrees >= 0 else { return "–" }
        return degrees.formatted(.number.precision(.fractionLength(0))) + "°"
    }

    static func distance(_ meters: Double) -> String {
        meters < 1000
            ? meters.formatted(.number.precision(.fractionLength(0))) + " m"
            : (meters / 1000).formatted(.number.precision(.fractionLength(2))) + " km"
    }
}

/// Bewertung der horizontalen Genauigkeit für Farbe und Text.
enum AccuracyQuality {
    case invalid, excellent, good, fair, poor

    init(_ horizontalAccuracy: Double) {
        switch horizontalAccuracy {
        case ..<0: self = .invalid
        case ...5: self = .excellent
        case ...15: self = .good
        case ...50: self = .fair
        default: self = .poor
        }
    }

    var title: String {
        switch self {
        case .invalid: "ungültig"
        case .excellent: "sehr gut"
        case .good: "gut"
        case .fair: "mäßig"
        case .poor: "schlecht"
        }
    }

    var color: Color {
        switch self {
        case .invalid: .gray
        case .excellent: .green
        case .good: .mint
        case .fair: .orange
        case .poor: .red
        }
    }
}

extension CLAuthorizationStatus {
    var title: String {
        switch self {
        case .notDetermined: "nicht festgelegt"
        case .restricted: "eingeschränkt"
        case .denied: "verweigert"
        case .authorizedAlways: "immer"
        case .authorizedWhenInUse: "beim Verwenden"
        @unknown default: "unbekannt"
        }
    }
}
