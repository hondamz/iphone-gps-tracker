import MapKit
import SwiftData
import SwiftUI

/// Verlauf: Bewegung in einem wählbaren Zeitraum als Linie, mit Zeit-Slider zum Abspielen.
struct HistoryView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var range: HistoryRange?
    @State private var customFrom = Date.now.addingTimeInterval(-86_400)
    @State private var customTo = Date.now
    @State private var reference = Date.now

    private var interval: DateInterval {
        let selected = range ?? settings.historyDefaultRange
        if let duration = selected.duration {
            return DateInterval(start: reference.addingTimeInterval(-duration), end: reference)
        }
        return DateInterval(start: min(customFrom, customTo), end: max(customFrom, customTo))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Picker("Zeitraum", selection: Binding(
                        get: { range ?? settings.historyDefaultRange },
                        set: { range = $0; reference = .now }
                    )) {
                        ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if (range ?? settings.historyDefaultRange) == .custom {
                        DatePicker("Von", selection: $customFrom)
                        DatePicker("Bis", selection: $customTo)
                    }
                }
                .padding([.horizontal, .bottom])
                HistoryTrackView(interval: interval)
                    .id(interval)
            }
            .navigationTitle("Verlauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Aktualisieren", systemImage: "arrow.clockwise") { reference = .now }
            }
        }
    }
}

/// Karte + Zeit-Slider für ein festes Zeitintervall.
/// Kartenausschnitt: lokal = automatisch auf die ganze Spur, sonst feste Breite um den Slider-Punkt.
private struct HistoryTrackView: View {
    @Environment(SettingsStore.self) private var settings
    @Query private var points: [TrackPoint]
    @State private var progress: Double = 1
    @State private var position: MapCameraPosition = .automatic
    /// Mittelpunkt des zuletzt gesetzten festen Ausschnitts.
    @State private var lastCenter: CLLocation?

    /// Ab dieser Punktzahl wird die Linie für die Darstellung ausgedünnt.
    private static let maxDrawnPoints = 4000

    init(interval: DateInterval) {
        let from = interval.start
        let to = interval.end
        _points = Query(filter: #Predicate<TrackPoint> { $0.timestamp >= from && $0.timestamp <= to },
                        sort: \.timestamp)
    }

    private var sliderTime: Date? {
        guard let first = points.first, let last = points.last else { return nil }
        return first.timestamp.addingTimeInterval(last.timestamp.timeIntervalSince(first.timestamp) * progress)
    }

    /// Index des letzten Punktes bis zur Slider-Zeit (binäre Suche).
    private var currentIndex: Int? {
        guard let time = sliderTime else { return nil }
        var low = 0, high = points.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].timestamp <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func thinned(_ slice: ArraySlice<TrackPoint>) -> [CLLocationCoordinate2D] {
        let step = max(1, slice.count / Self.maxDrawnPoints)
        var coords = stride(from: slice.startIndex, to: slice.endIndex, by: step).map { slice[$0].coordinate }
        if let last = slice.last, step > 1 { coords.append(last.coordinate) }
        return coords
    }

    var body: some View {
        let index = currentIndex
        let current = index.map { points[$0] }
        Map(position: $position) {
            ForEach(Array(TrackSegments.split(points[...]).enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: thinned(segment))
                    .stroke(.gray.opacity(0.5), lineWidth: 3)
            }
            if let index {
                ForEach(Array(TrackSegments.split(points[...index]).enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: thinned(segment))
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            if let first = points.first {
                Marker("Start", systemImage: "flag.fill", coordinate: first.coordinate).tint(.green)
            }
            if let current {
                Annotation(current.timestamp.formatted(date: .omitted, time: .shortened),
                           coordinate: current.coordinate) {
                    Circle()
                        .fill(.blue)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 18, height: 18)
                        .shadow(radius: 2)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) {
            if !points.isEmpty { scaleBar }
        }
        .onAppear { recenter(on: current, animated: false) }
        .onChange(of: settings.historyMapScale) { recenter(on: current, animated: true) }
        .onChange(of: index) {
            // Fester Ausschnitt folgt dem Slider, sobald der Punkt > 10 % der Breite aus der Mitte ist.
            guard let meters = settings.historyMapScale.meters, let current else { return }
            if let center = lastCenter, current.location.distance(from: center) < meters * 0.1 { return }
            recenter(on: current, animated: true)
        }
        .overlay {
            if points.isEmpty {
                ContentUnavailableView("Keine Daten", systemImage: "map",
                                       description: Text("Im gewählten Zeitraum wurden keine Punkte aufgezeichnet."))
                    .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let current, let index {
                sliderPanel(current: current, index: index)
            }
        }
    }

    private var scaleBar: some View {
        @Bindable var settings = settings
        return HStack(spacing: 8) {
            Picker("Kartenausschnitt", selection: $settings.historyMapScale) {
                ForEach(MapScale.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                recenter(on: currentIndex.map { points[$0] }, animated: true)
            } label: {
                Image(systemName: "scope").frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Ausschnitt neu setzen")
        }
        .padding(6)
        .background(.regularMaterial, in: .capsule)
        .padding(.horizontal)
    }

    /// Lokal: ganze Spur einpassen; feste Breite: auf den Slider-Punkt zentrieren.
    private func recenter(on current: TrackPoint?, animated: Bool) {
        let target: MapCameraPosition
        if let meters = settings.historyMapScale.meters, let current {
            lastCenter = current.location
            target = .region(MKCoordinateRegion(center: current.coordinate,
                                                latitudinalMeters: meters, longitudinalMeters: meters))
        } else {
            lastCenter = nil
            target = .automatic
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { position = target }
        } else {
            position = target
        }
    }

    private func sliderPanel(current: TrackPoint, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(current.timestamp.formatted(date: .abbreviated, time: .standard)).font(.headline)
                Spacer()
                Text("\(index + 1) / \(points.count)").font(.caption).foregroundStyle(.secondary)
            }
            if let category = current.tripCategory.flatMap(TripCategory.init) {
                Label(category.title, systemImage: category.systemImage)
                    .font(.caption)
                    .foregroundStyle(category == .business ? Color.orange : Color.green)
            }
            Slider(value: $progress, in: 0...1)
            HStack {
                Label(Format.speed(current.speed), systemImage: "speedometer")
                Spacer()
                Label(Format.meters(current.horizontalAccuracy, plusMinus: true), systemImage: "scope")
                Spacer()
                Label(Format.distance(distance(upTo: index)), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func distance(upTo index: Int) -> Double {
        guard index > 0 else { return 0 }
        var total = 0.0
        for i in 1...index where !TrackSegments.isGap(points[i - 1], points[i]) {
            total += points[i].location.distance(from: points[i - 1].location)
        }
        return total
    }
}
