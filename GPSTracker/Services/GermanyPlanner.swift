import Foundation

/// Erzeugt für die Simulations-Betriebsart „Mainz, Paderborn & Deutschland“ fortlaufend zufällige
/// Abschnitte im Ortsnetz (SimulationRoutes.json → `germany`): meist Fahrten oder Spaziergänge zwischen
/// Orten derselben Region, gelegentlich eine Fernfahrt in eine andere Region (Mainz/Wiesbaden,
/// Paderborn/Borchen, Köln/Bonn).
///
/// Ziele werden bevorzugt unter den bisher am seltensten besuchten Orten der Region gewählt; ist für
/// eine Fernfahrt ein anderer Ort der Ausgangspunkt, fährt der Planer zuerst dorthin.
final class GermanyPlanner {
    typealias Network = SimulationRouteSet.GermanyNetwork

    /// Anteil der Fernfahrten an den Abschnitten.
    private static let longDistanceShare = 0.12
    /// Anteil der Spaziergänge (zu einem nahen, selten besuchten Ort), sofern einer zu Fuß erreichbar ist.
    private static let walkShare = 0.3

    private struct Edge {
        let to: String
        let route: SimulationRouteSet.Route
        let forward: Bool
        let mode: String
    }

    private let hubs: [String: Network.Hub]
    private var edges: [String: [Edge]] = [:]
    private var visits: [String: Int] = [:]
    private var pending: [SimulationRouteSet.Route] = []
    private var current: String

    init?(network: Network, routes: SimulationRouteSet) {
        hubs = Dictionary(uniqueKeysWithValues: network.hubs.map { ($0.id, $0) })
        for link in network.links {
            guard let route = routes.route(link.route) else { continue }
            edges[link.from, default: []].append(Edge(to: link.to, route: route, forward: true, mode: link.mode))
            edges[link.to, default: []].append(Edge(to: link.from, route: route, forward: false, mode: link.mode))
        }
        guard let start = network.hubs.first(where: { $0.id == "mz_hbf" }) ?? network.hubs.first,
              edges[start.id] != nil else { return nil }
        current = start.id
        visits[start.id] = 1
    }

    /// Nächster Abschnitt.
    func next() -> SimulationRouteSet.Route {
        if !pending.isEmpty { return pending.removeFirst() }
        if Double.random(in: 0..<1) < Self.longDistanceShare, let trip = longDistance() {
            pending = Array(trip.dropFirst())
            return trip[0]
        }
        return local() ?? longDistance()?.first ?? fallback()
    }

    // MARK: - Abschnitte

    /// Fahrt oder Spaziergang zu einem selten besuchten Ort derselben Region.
    private func local() -> SimulationRouteSet.Route? {
        let options = (edges[current] ?? []).filter { region(of: $0.to) == region(of: current) }
        let walks = options.filter { $0.mode == "foot" }
        if !walks.isEmpty, Double.random(in: 0..<1) < Self.walkShare,
           let goal = leastVisited(Set(walks.map(\.to))), let edge = walks.first(where: { $0.to == goal }) {
            return travel(edge, pause: .random(in: 120...900))
        }
        let drives = options.filter { $0.mode == "car" }
        guard let goal = leastVisited(Set(drives.map(\.to))), let edge = drives.first(where: { $0.to == goal }) else { return nil }
        return travel(edge, pause: .random(in: 300...1800))
    }

    /// Fernfahrt in eine andere Region; liegt der Startpunkt der Fernstrecke woanders, zuerst dorthin.
    private func longDistance() -> [SimulationRouteSet.Route]? {
        let here = region(of: current)
        // alle Fernstrecken, die aus der aktuellen Region hinausführen
        var gates: [(from: String, edge: Edge)] = []
        for (from, list) in edges where region(of: from) == here {
            for e in list where region(of: e.to) != here { gates.append((from, e)) }
        }
        guard !gates.isEmpty else { return nil }
        // bevorzugt in die am seltensten besuchte Region
        let regionVisits = Dictionary(grouping: gates, by: { region(of: $0.edge.to) })
            .mapValues { list in list.map { visits[$0.edge.to, default: 0] }.reduce(0, +) }
        let least = regionVisits.values.min() ?? 0
        let pool = gates.filter { regionVisits[region(of: $0.edge.to)] == least }
        guard let gate = pool.randomElement() else { return nil }
        var trip: [SimulationRouteSet.Route] = []
        if gate.from != current {
            guard let approach = (edges[current] ?? []).first(where: { $0.to == gate.from && $0.mode == "car" }) else { return nil }
            trip.append(travel(approach, pause: .random(in: 120...600)))
        }
        trip.append(travel(gate.edge, pause: .random(in: 600...1800)))
        return trip
    }

    // MARK: - Hilfen

    private func travel(_ edge: Edge, pause: Double) -> SimulationRouteSet.Route {
        let from = hubs[current]?.name ?? current, to = hubs[edge.to]?.name ?? edge.to
        let label = edge.mode == "foot" ? "Zu Fuß" : (region(of: current) == region(of: edge.to) ? "Fahrt" : "Fernfahrt")
        let name = "\(label): \(from) → \(to)"
        current = edge.to
        visits[edge.to, default: 0] += 1
        if edge.forward {
            let r = edge.route
            return SimulationRouteSet.Route(id: r.id, name: name, pauseAfterSeconds: pause, points: r.points)
        }
        return edge.route.reversed(name: name, pause: pause)
    }

    private func leastVisited(_ ids: Set<String>) -> String? {
        let least = ids.map { visits[$0, default: 0] }.min()
        return ids.filter { visits[$0, default: 0] == least }.randomElement()
    }

    private func region(of id: String) -> String { hubs[id]?.region ?? "" }

    private func fallback() -> SimulationRouteSet.Route {
        let edge = edges[current]?.randomElement()
        return edge.map { travel($0, pause: 300) } ?? .generated(name: "Deutschland", points: [], pause: 60)
    }
}
