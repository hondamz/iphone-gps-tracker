import CoreLocation
import Foundation

/// Hinterlegte Simulationsrouten (Resources/SimulationRoutes.json, erzeugt mit
/// tools/build_simulation_routes.py aus OpenStreetMap-Daten).
nonisolated struct SimulationRouteSet: Decodable, Sendable {
    struct Route: Decodable, Sendable {
        let id: String
        let name: String
        let pauseAfterSeconds: Double
        /// [Breite, Länge, Geschwindigkeit m/s des folgenden Abschnitts]
        let points: [[Double]]
    }

    /// Ausflug vom Flughafen (Köln/Bonn): Abfahrtspunkt am Flughafen und Folge von Routen-IDs.
    struct CityTrip: Decodable, Sendable {
        let id: String
        let name: String
        /// [Breite, Länge] – dort beginnt und endet der Ausflug
        let start: [Double]
        /// „foot“ (Bahn: zu Fuß zum Bahnhof) oder „car“ (mit dem Auto vom Terminal)
        let startMode: String
        let routes: [String]
    }

    /// Ortsnetz der Deutschland-Simulation: Orte je Region und Routen zwischen ihnen.
    struct GermanyNetwork: Decodable, Sendable {
        struct Hub: Decodable, Sendable {
            let id, name, region: String
            let lat, lon: Double
        }

        /// Verbindung zweier Orte; nutzbar in beide Richtungen (Rückweg = umgekehrte Route).
        struct Link: Decodable, Sendable {
            let from, to, route, mode: String
        }

        let hubs: [Hub]
        let links: [Link]
    }

    let attribution: String
    let modes: [String: [String]]
    let routes: [Route]
    let cityTrips: [CityTrip]?
    let germany: GermanyNetwork?

    static let shared: SimulationRouteSet? = {
        guard let url = Bundle.main.url(forResource: "SimulationRoutes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SimulationRouteSet.self, from: data)
    }()

    func routes(for mode: SimulationMode) -> [Route] {
        (modes[mode.rawValue] ?? []).compactMap { id in routes.first { $0.id == id } }
    }

    func route(_ id: String) -> Route? { routes.first { $0.id == id } }
}

extension SimulationRouteSet.Route {
    /// Zur Laufzeit erzeugte Route (z. B. vom AirportPlanner).
    static func generated(name: String, points: [[Double]], pause: Double) -> Self {
        Self(id: "generated", name: name, pauseAfterSeconds: pause, points: points)
    }

    /// Dieselbe Strecke rückwärts; das Tempo bleibt dem jeweiligen Abschnitt zugeordnet.
    func reversed(name: String, pause: Double) -> Self {
        let pts = Array(points.reversed())
        let speeds = points.dropLast().map { $0[2] }.reversed() + [0]
        let result = zip(pts, speeds).map { p, v in [p[0], p[1], v] }
        return Self(id: id + "_rev", name: name, pauseAfterSeconds: pause, points: result)
    }
}

/// Erzeugt simulierte Positionen entlang der Routen einer Betriebsart (Endlosschleife).
/// Pro Sekunde eine Messung; mit Zeitraffer > 1 wird die Strecke entsprechend schneller
/// abgefahren (Zeitstempel bleiben echt, Geschwindigkeit = tatsächliche Verschiebung).
final class LocationSimulator {
    /// Name der gerade gefahrenen Route (für die Anzeige).
    private(set) var currentRouteName: String?

    private var task: Task<Void, Never>?

    func start(mode: SimulationMode, speedFactor: Int,
               onRoute: @escaping (String?) -> Void,
               onLocation: @escaping (CLLocation) -> Void) {
        stop()
        guard let next = Self.routeSource(for: mode) else {
            onRoute(nil)
            return
        }
        let factor = Double(max(1, speedFactor))
        let profile = NoiseProfile(mode: mode)
        task = Task { [weak self] in
            var current = next()
            while !Task.isCancelled {
                self?.currentRouteName = current.name
                onRoute(current.name)
                await Self.drive(current, factor: factor, profile: profile, onLocation: onLocation)
                if Task.isCancelled { return }
                let following = next()
                try? await Task.sleep(for: .seconds(Self.pause(after: current, before: following, factor: factor)))
                current = following
            }
        }
    }

    /// Liefert endlos die nächste Route: Flughafen über den AirportPlanner (zufällige Strecken),
    /// sonst die hinterlegten Routen der Betriebsart der Reihe nach.
    private static func routeSource(for mode: SimulationMode) -> (() -> SimulationRouteSet.Route)? {
        guard let set = SimulationRouteSet.shared else { return nil }
        if mode == .cgnAirport, let graph = AirportGraph.shared {
            let planner = AirportPlanner(graph: graph, routes: set)
            return { planner.next() }
        }
        if mode == .germany, let network = set.germany, let planner = GermanyPlanner(network: network, routes: set) {
            return { planner.next() }
        }
        let routes = set.routes(for: mode)
        guard !routes.isEmpty else { return nil }
        var index = -1
        return {
            index = (index + 1) % routes.count
            return routes[index]
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        currentRouteName = nil
    }

    /// Fährt eine Route ab: jede Sekunde um `Geschwindigkeit × Zeitraffer` Meter weiter.
    private static func drive(_ route: SimulationRouteSet.Route, factor: Double, profile: NoiseProfile,
                              onLocation: (CLLocation) -> Void) async {
        let pts = route.points
        guard pts.count > 1 else { return }
        var index = 0          // Startpunkt des aktuellen Abschnitts
        var offset = 0.0       // bereits gefahrene Meter im Abschnitt
        while index < pts.count - 1, !Task.isCancelled {
            let speed = max(0.5, pts[index][2]) * factor
            var remaining = speed      // Meter in dieser Sekunde
            while remaining > 0, index < pts.count - 1 {
                let length = segmentLength(pts[index], pts[index + 1])
                if offset + remaining < length {
                    offset += remaining
                    remaining = 0
                } else {
                    remaining -= length - offset
                    offset = 0
                    index += 1
                }
            }
            let a = pts[min(index, pts.count - 1)]
            let b = pts[min(index + 1, pts.count - 1)]
            let length = segmentLength(a, b)
            let frac = length > 0 ? offset / length : 0
            let coordinate = CLLocationCoordinate2D(latitude: a[0] + (b[0] - a[0]) * frac,
                                                    longitude: a[1] + (b[1] - a[1]) * frac)
            onLocation(profile.location(at: coordinate, course: bearing(a, b), speed: speed))
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Pause zwischen zwei Routen. Beginnt die nächste Route woanders (z. B. Landung nach dem
    /// Start), bleibt die Pause echt und länger als `TrackSegments.maxGap`, damit die Karte
    /// den Sprung nicht als Linie verbindet. Sonst wird sie mit dem Zeitraffer verkürzt.
    private static func pause(after route: SimulationRouteSet.Route, before next: SimulationRouteSet.Route,
                              factor: Double) -> Double {
        guard let end = route.points.last, let start = next.points.first else { return 0 }
        let isJump = segmentLength(end, start) > 200
        return isJump ? max(route.pauseAfterSeconds, TrackSegments.maxGap + 30) : route.pauseAfterSeconds / factor
    }

    private static func segmentLength(_ a: [Double], _ b: [Double]) -> Double {
        CLLocation(latitude: a[0], longitude: a[1]).distance(from: CLLocation(latitude: b[0], longitude: b[1]))
    }

    private static func bearing(_ a: [Double], _ b: [Double]) -> Double {
        let lat1 = a[0] * .pi / 180, lat2 = b[0] * .pi / 180
        let dLon = (b[1] - a[1]) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Realistische Streuung der simulierten Messwerte.
private nonisolated struct NoiseProfile: Sendable {
    let accuracyRange: ClosedRange<Double>
    let baseAltitude: Double

    init(mode: SimulationMode) {
        switch mode {
        case .cgnAirport:
            accuracyRange = 3...8          // freies Gelände
            baseAltitude = 92
        default:
            accuracyRange = 4...15         // Stadt und Autobahn
            baseAltitude = 120
        }
    }

    func location(at coordinate: CLLocationCoordinate2D, course: Double, speed: Double) -> CLLocation {
        let accuracy = Double.random(in: accuracyRange)
        // Versatz innerhalb etwa eines Drittels der angegebenen Genauigkeit
        let jitter = accuracy / 3
        let dLat = Double.random(in: -jitter...jitter) / 111_320
        let dLon = Double.random(in: -jitter...jitter) / (111_320 * cos(coordinate.latitude * .pi / 180))
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude + dLat,
                                               longitude: coordinate.longitude + dLon),
            altitude: baseAltitude + Double.random(in: -2...2),
            horizontalAccuracy: accuracy,
            verticalAccuracy: accuracy * 1.5,
            course: course,
            courseAccuracy: speed > 2 ? 5 : 30,
            speed: speed,
            speedAccuracy: 0.5,
            timestamp: .now,
            sourceInfo: CLLocationSourceInformation(softwareSimulationState: true, andExternalAccessoryState: false)
        )
    }
}
