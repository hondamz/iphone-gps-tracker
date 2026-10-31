import Foundation

/// Teilt eine Punktfolge an Aufzeichnungspausen in Segmente, damit getrennte Fahrten
/// auf der Karte nicht mit einer geraden Linie verbunden werden.
enum TrackSegments {
    /// Zeitlücke, ab der zwei aufeinanderfolgende Punkte nicht mehr verbunden werden.
    static let maxGap: TimeInterval = 5 * 60

    static func isGap(_ previous: TrackPoint, _ next: TrackPoint) -> Bool {
        next.timestamp.timeIntervalSince(previous.timestamp) > maxGap
    }

    static func split(_ points: ArraySlice<TrackPoint>) -> [ArraySlice<TrackPoint>] {
        guard !points.isEmpty else { return [] }
        var segments: [ArraySlice<TrackPoint>] = []
        var start = points.startIndex
        for index in points.indices.dropFirst() where isGap(points[index - 1], points[index]) {
            segments.append(points[start..<index])
            start = index
        }
        segments.append(points[start..<points.endIndex])
        return segments
    }
}
