import CoreLocation
import Foundation

/// Wegenetz des Flughafens Köln/Bonn (Resources/AirportGraph.json, erzeugt mit
/// tools/build_simulation_routes.py aus OpenStreetMap-Daten innerhalb der Flughafengrenze).
nonisolated struct AirportGraph: Decodable, Sendable {
    struct Masks: Decodable, Sendable {
        let foot, car, plane, steps, runway: Int
    }

    /// Kante: Knoten a, Knoten b, Bitmaske der Verkehrsarten, Kfz-Tempo in m/s.
    struct Edge: Decodable, Sendable {
        let a, b, mask: Int
        let carSpeed: Double

        init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            a = try c.decode(Int.self)
            b = try c.decode(Int.self)
            mask = try c.decode(Int.self)
            carSpeed = try c.decode(Double.self)
        }
    }

    /// Benanntes Ziel (Terminal, Vorfeld, Halle …) für die Streckennamen.
    struct POI: Decodable, Sendable {
        let name: String
        let lat, lon: Double

        init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            name = try c.decode(String.self)
            lat = try c.decode(Double.self)
            lon = try c.decode(Double.self)
        }
    }

    let masks: Masks
    /// [Breite, Länge]
    let nodes: [[Double]]
    let edges: [Edge]
    let pois: [POI]

    static let shared: AirportGraph? = {
        guard let url = Bundle.main.url(forResource: "AirportGraph", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AirportGraph.self, from: data)
    }()
}

/// Erzeugt für die Simulations-Betriebsart „Flughafen Köln/Bonn“ fortlaufend neue Abschnitte:
/// zufällige Wege zu Fuß und mit dem Fahrzeug über das ganze Gelände, Follow-me-Fahrten auf den
/// Rollwegen, gelegentlich Start/Landung und ab und zu einen Ausflug nach Köln oder Bonn.
///
/// Damit mit der Zeit alle Bereiche vorkommen, wird das Gelände in Zellen (~220 m) geteilt und
/// das Ziel bevorzugt in den bisher am seltensten besuchten Zellen gewählt.
///
/// Wechselt die Verkehrsart (z. B. Fahrt → zu Fuß) und liegt das neue Netz nicht in der Nähe, geht
/// bzw. fährt der Abschnitt zuerst mit der bisherigen Art zu einem Umstiegspunkt, an dem beide Netze
/// nah beieinanderliegen – so entstehen keine Sprünge.
final class AirportPlanner {
    enum Kind: CaseIterable {
        case foot, car, followMe

        var label: String {
            switch self {
            case .foot: "Zu Fuß"
            case .car: "Fahrt"
            case .followMe: "Follow-me-Fahrzeug"
            }
        }
    }

    private struct Arc {
        let to: Int
        let length: Double
        let speed: Double
    }

    /// Anteile der Abschnittsarten (Summe 1).
    private static let weights: [(Choice, Double)] = [
        (.walk, 0.42), (.drive, 0.36), (.followMe, 0.10), (.aircraft, 0.05), (.cityTrip, 0.07),
    ]
    private enum Choice { case walk, drive, followMe, aircraft, cityTrip }

    /// Zellgröße für die Abdeckung (Grad Breite/Länge ≈ 220 m × 210 m).
    private static let cellLat = 0.002, cellLon = 0.003
    /// Längster gerader Übergang zwischen Netzen (z. B. vom Parkplatz zum Fußweg).
    private static let maxConnector = 300.0
    /// Umstiegspunkt: Knoten eines Netzes, von dem ein Knoten des anderen Netzes so nah ist.
    private static let transferRadius = 40.0
    /// Start der festen Rollroute (Flugzeug am Vorfeld C, Terminal 1) – Abschnitt „cgn_taxi_out“.
    private static let aircraftRoutes = ["cgn_taxi_out", "cgn_takeoff", "cgn_landing", "cgn_taxi_back"]
    /// Maximale Luftlinie für Fußwege.
    private static let maxWalk = 1800.0

    private let graph: AirportGraph
    private let routes: SimulationRouteSet
    private var adjacency: [Kind: [[Arc]]] = [:]
    private var cells: [Kind: [Int: [Int]]] = [:]
    private var visits: [Int: Int] = [:]
    /// Umstiegspunkte: transfers[A][B] = Knoten im Netz A mit einem Knoten des Netzes B in der Nähe.
    private var transfers: [Kind: [Kind: [Int]]] = [:]
    private var pending: [SimulationRouteSet.Route] = []
    private var position: (lat: Double, lon: Double)
    /// Verkehrsart, mit der die aktuelle Position erreicht wurde.
    private var current: Kind = .foot

    init(graph: AirportGraph, routes: SimulationRouteSet) {
        self.graph = graph
        self.routes = routes
        position = (50.87871, 7.12267)   // Terminal 1
        for kind in Kind.allCases {
            var adj = Array(repeating: [Arc](), count: graph.nodes.count)
            for e in graph.edges where e.mask & mask(of: kind) != 0 {
                let length = distance(graph.nodes[e.a], graph.nodes[e.b])
                let speed: Double
                switch kind {
                case .foot: speed = e.mask & graph.masks.steps != 0 ? 0.6 : 1.4
                case .car: speed = max(3, e.carSpeed)
                case .followMe: speed = e.mask & graph.masks.runway != 0 ? 12 : 8
                }
                adj[e.a].append(Arc(to: e.b, length: length, speed: speed))
                adj[e.b].append(Arc(to: e.a, length: length, speed: speed))
            }
            adjacency[kind] = adj
            var c: [Int: [Int]] = [:]
            for (i, arcs) in adj.enumerated() where !arcs.isEmpty {
                c[cell(graph.nodes[i]), default: []].append(i)
            }
            cells[kind] = c
        }
        for a in Kind.allCases {
            for b in Kind.allCases where a != b {
                transfers[a, default: [:]][b] = (cells[a] ?? [:]).values.joined().filter { node in
                    neighbours(of: graph.nodes[node], kind: b).contains {
                        distance(graph.nodes[$0], graph.nodes[node]) <= Self.transferRadius
                    }
                }
            }
        }
    }

    /// Nächster Abschnitt. Mehrteilige Abläufe (Start/Landung, Ausflug) werden nacheinander geliefert.
    func next() -> SimulationRouteSet.Route {
        if !pending.isEmpty { return take(pending.removeFirst()) }
        switch choose() {
        case .walk: return leg(.foot) ?? fallback()
        case .drive: return leg(.car) ?? fallback()
        case .followMe: return leg(.followMe) ?? fallback()
        case .aircraft:
            pending = Self.aircraftRoutes.compactMap(routes.route)
            guard let board = pending.first?.points.first else { return fallback() }
            // zu Fuß zum Flugzeug; nach der Landung steht es wieder am Vorfeld C (Netz der Rollwege)
            let approach = travel(to: (board[0], board[1]), kind: .foot, name: "Zu Fuß → Flugzeug am Vorfeld C", pause: 120)
            current = .followMe
            return approach ?? take(pending.removeFirst())
        case .cityTrip:
            guard let trip = routes.cityTrips?.randomElement() else { return fallback() }
            let kind: Kind = trip.startMode == "car" ? .car : .foot
            pending = trip.routes.compactMap(routes.route)
            let place = trip.startMode == "car" ? "Terminal 1" : "Bahnhof"
            let approach = travel(to: (trip.start[0], trip.start[1]), kind: kind,
                                  name: "\(kind.label) → \(place) (\(trip.name))", pause: 60)
            current = kind      // der Ausflug endet wieder am Abfahrtspunkt
            return approach ?? (pending.isEmpty ? fallback() : take(pending.removeFirst()))
        }
    }

    // MARK: - Auswahl

    private func choose() -> Choice {
        var r = Double.random(in: 0..<1)
        for (choice, weight) in Self.weights {
            if r < weight { return choice }
            r -= weight
        }
        return .walk
    }

    /// Zufälliger Abschnitt einer Verkehrsart zu einem Ziel in einer wenig besuchten Zelle.
    private func leg(_ kind: Kind) -> SimulationRouteSet.Route? {
        guard let goal = target(kind) else { return nil }
        let pause: Double = switch kind {
        case .foot: .random(in: 30...240)
        case .car: .random(in: 60...300)
        case .followMe: .random(in: 30...120)
        }
        return route(kind: kind, to: goal, name: "\(kind.label) → \(placeName(near: graph.nodes[goal]))", pause: pause)
    }

    private func target(_ kind: Kind) -> Int? {
        guard let c = cells[kind], !c.isEmpty else { return nil }
        let here = [position.lat, position.lon]
        var candidates = Array(c.keys)
        if kind == .foot {
            let near = candidates.filter { key in c[key]!.contains { distance(graph.nodes[$0], here) < Self.maxWalk } }
            if !near.isEmpty { candidates = near }
        }
        let least = candidates.map { visits[$0, default: 0] }.min() ?? 0
        let pool = candidates.filter { visits[$0, default: 0] == least }
        for _ in 0..<20 {
            guard let key = pool.randomElement(), let node = c[key]?.randomElement() else { continue }
            let d = distance(graph.nodes[node], here)
            if d > 250, kind != .foot || d < Self.maxWalk { return node }
        }
        return c.values.randomElement()?.randomElement()
    }

    // MARK: - Wegsuche

    /// Abschnitt zum Zielknoten im Netz der Verkehrsart. Liegt dieses Netz nicht in der Nähe der aktuellen
    /// Position, führt der Abschnitt zuerst mit der bisherigen Verkehrsart zu einem Umstiegspunkt.
    private func route(kind: Kind, to goal: Int, name: String, pause: Double) -> SimulationRouteSet.Route? {
        var points: [[Double]] = []
        if kind != current, let start = nearest(to: position, kind: kind),
           distance(graph.nodes[start], [position.lat, position.lon]) > Self.maxConnector,
           let hub = transferNode(from: current, to: kind, towards: graph.nodes[goal]),
           let first = segment(kind: current, from: position, to: hub) {
            points = first
            position = (first.last![0], first.last![1])
        }
        guard let second = segment(kind: kind, from: position, to: goal) else { return nil }
        // das erste Teilstück endet genau dort, wo das zweite beginnt: dessen Endpunkt (Tempo 0) entfällt
        points = points.dropLast() + second
        current = kind
        guard points.count > 1 else { return nil }
        return take(.generated(name: name, points: points, pause: pause))
    }

    /// Weg zu einem festen Punkt (Abfahrt eines Ausflugs, Flugzeug). `nil`, wenn man schon dort ist.
    private func travel(to p: (lat: Double, lon: Double), kind: Kind, name: String, pause: Double) -> SimulationRouteSet.Route? {
        guard let goal = nearest(to: p, kind: kind),
              distance(graph.nodes[goal], [position.lat, position.lon]) > 30 else { return nil }
        return route(kind: kind, to: goal, name: name, pause: pause)
    }

    /// Umstiegspunkt im Netz `from` zum Netz `to`: möglichst nah an der aktuellen Position und
    /// in Richtung Ziel (Luftlinie Position → Umstieg → Ziel minimal).
    private func transferNode(from: Kind, to: Kind, towards goal: [Double]) -> Int? {
        let here = [position.lat, position.lon]
        return transfers[from]?[to]?.min { a, b in
            distance(here, graph.nodes[a]) + distance(graph.nodes[a], goal)
                < distance(here, graph.nodes[b]) + distance(graph.nodes[b], goal)
        }
    }

    /// Punkte `[lat, lon, m/s]` von `p` zum Zielknoten im Netz der Verkehrsart (Dijkstra nach Fahrzeit).
    /// Liegt der nächste Netzknoten bis 300 m entfernt, wird er auf gerader Linie erreicht.
    private func segment(kind: Kind, from p: (lat: Double, lon: Double), to goal: Int) -> [[Double]]? {
        guard let adj = adjacency[kind], let start = nearest(to: p, kind: kind) else { return nil }
        let runwayPenalty = kind == .followMe
        var best = [Double](repeating: .infinity, count: adj.count)
        var previous = [Int](repeating: -1, count: adj.count)
        var heap = MinHeap()
        best[start] = 0
        heap.push(0, start)
        while let (cost, node) = heap.pop() {
            if node == goal { break }
            if cost > best[node] { continue }
            for arc in adj[node] {
                let penalty = runwayPenalty && arc.speed > 10 ? 4.0 : 1.0
                let c = cost + arc.length / arc.speed * penalty
                if c < best[arc.to] {
                    best[arc.to] = c
                    previous[arc.to] = node
                    heap.push(c, arc.to)
                }
            }
        }
        guard best[goal].isFinite else { return nil }
        var nodes = [goal]
        while let last = nodes.last, last != start { nodes.append(previous[last]) }
        nodes.reverse()

        // Tempo je Abschnitt; zu Fuß mit persönlichem Gehtempo, Fahrzeuge mit etwas Streuung
        let factor = kind == .foot ? Double.random(in: 0.85...1.1) : Double.random(in: 0.8...1.05)
        var points: [[Double]] = []
        let gap = distance([p.lat, p.lon], graph.nodes[start])
        if gap > 5, gap <= Self.maxConnector {
            points.append([p.lat, p.lon, kind == .foot ? 1.3 : 4])
        }
        for (i, node) in nodes.enumerated() {
            let q = graph.nodes[node]
            var speed = 0.0
            if i + 1 < nodes.count, let arc = adj[node].first(where: { $0.to == nodes[i + 1] }) {
                speed = arc.speed * factor
            }
            points.append([q[0], q[1], speed])
        }
        for key in Set(nodes.map { cell(graph.nodes[$0]) }) { visits[key, default: 0] += 1 }
        return points
    }

    /// Knoten eines Netzes in derselben und den angrenzenden Zellen.
    private func neighbours(of p: [Double], kind: Kind) -> [Int] {
        guard let c = cells[kind] else { return [] }
        let la = Int((p[0] / Self.cellLat).rounded(.down)), lo = Int((p[1] / Self.cellLon).rounded(.down))
        var result: [Int] = []
        for dla in -1...1 {
            for dlo in -1...1 { result += c[(la + dla) * 100_000 + lo + dlo] ?? [] }
        }
        return result
    }

    private func nearest(to p: (lat: Double, lon: Double), kind: Kind) -> Int? {
        guard let adj = adjacency[kind] else { return nil }
        let here = [p.lat, p.lon]
        var best: (Int, Double)?
        for (i, arcs) in adj.enumerated() where !arcs.isEmpty {
            let d = distance(graph.nodes[i], here)
            if best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    // MARK: - Hilfen

    /// Merkt sich das Ende des Abschnitts als neue Position.
    private func take(_ route: SimulationRouteSet.Route) -> SimulationRouteSet.Route {
        if let last = route.points.last { position = (last[0], last[1]) }
        return route
    }

    private func fallback() -> SimulationRouteSet.Route {
        take(routes.routes(for: .cgnAirport).randomElement()
             ?? .generated(name: "Flughafen", points: [[position.lat, position.lon, 0]], pause: 60))
    }

    private func mask(of kind: Kind) -> Int {
        switch kind {
        case .foot: graph.masks.foot
        case .car: graph.masks.car
        case .followMe: graph.masks.plane
        }
    }

    private func cell(_ p: [Double]) -> Int {
        Int((p[0] / Self.cellLat).rounded(.down)) * 100_000 + Int((p[1] / Self.cellLon).rounded(.down))
    }

    /// Name des nächstgelegenen benannten Ziels (bis 400 m), sonst „Flughafengelände“.
    private func placeName(near p: [Double]) -> String {
        let poi = graph.pois.min { distance([$0.lat, $0.lon], p) < distance([$1.lat, $1.lon], p) }
        guard let poi, distance([poi.lat, poi.lon], p) < 400 else { return "Flughafengelände" }
        return poi.name
    }

    private func distance(_ a: [Double], _ b: [Double]) -> Double {
        let dLat = (a[0] - b[0]) * 111_320
        let dLon = (a[1] - b[1]) * 111_320 * cos(a[0] * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}

/// Einfacher Binär-Heap (Kosten, Knoten) für die Wegsuche.
private nonisolated struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ cost: Double, _ node: Int) {
        items.append((cost, node))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].0 <= items[i].0 { break }
            items.swapAt(parent, i)
            i = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}
