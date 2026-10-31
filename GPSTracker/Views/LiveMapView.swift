import MapKit
import SwiftData
import SwiftUI

/// Live-Karte: aktuelle Position mit Genauigkeitskreis und der heutige Weg als Linie.
/// Der Ausschnitt ist wählbar: lokal (automatisch auf die Umgebung) oder 30/100/500 km breit.
struct LiveMapView: View {
    @Environment(LocationTracker.self) private var tracker
    @Environment(SettingsStore.self) private var settings
    @Query private var todayPoints: [TrackPoint]
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    /// Karte folgt der Position des Trackers.
    @State private var follow = true
    /// Mittelpunkt des zuletzt gesetzten festen Ausschnitts (zum Nachführen erst bei Bedarf).
    @State private var lastCenter: CLLocation?
    /// Verbindet die eigene Button-Spalte mit der Karte.
    @Namespace private var mapScope

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        _todayPoints = Query(filter: #Predicate<TrackPoint> { $0.timestamp >= start }, sort: \.timestamp)
    }

    var body: some View {
        Map(position: $position, scope: mapScope) {
            if tracker.isSimulating {
                if let location = tracker.lastLocation {
                    Annotation("Simulation", coordinate: location.coordinate) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .purple)
                            .rotationEffect(.degrees(max(0, location.course)))
                            .shadow(radius: 2)
                    }
                }
            } else {
                UserAnnotation()
            }
            ForEach(Array(TrackSegments.split(todayPoints[...]).enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let location = tracker.lastLocation, location.horizontalAccuracy > 0 {
                MapCircle(center: location.coordinate, radius: location.horizontalAccuracy)
                    .foregroundStyle(AccuracyQuality(location.horizontalAccuracy).color.opacity(0.15))
                    .stroke(AccuracyQuality(location.horizontalAccuracy).color.opacity(0.6), lineWidth: 1)
            }
        }
        .mapControls {
            MapScaleView()
        }
        // Eigene Spalte, damit der Kategorie-Button direkt unter dem Positionsbutton sitzt
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                MapUserLocationButton(scope: mapScope)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: .circle)
                    .shadow(radius: 2)
                categoryButton
                MapCompass(scope: mapScope)
            }
            .padding(.top, 8)
            .padding(.trailing, 10)
        }
        .mapScope(mapScope)
        .safeAreaInset(edge: .bottom) { statusBar }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 6) {
                if tracker.isSimulating {
                    Label("Simulation: \(tracker.simulationRouteName ?? tracker.activeSimulation.title)",
                          systemImage: "play.circle.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(.purple.gradient, in: .capsule)
                }
                scaleBar
            }
            .padding(.horizontal)
        }
        .onAppear { recenter(animated: false) }
        .onChange(of: settings.mapScale) {
            follow = true
            recenter(animated: true)
        }
        .onChange(of: tracker.isSimulating) { recenter(animated: true) }
        .onChange(of: tracker.lastLocation) {
            // Bei echtem GPS im Modus „Lokal“ folgt MapKit selbst (`.userLocation`).
            guard follow, tracker.isSimulating || settings.mapScale.meters != nil else { return }
            // Große Ausschnitte erst nachführen, wenn der Tracker > 10 % der Breite aus der Mitte ist.
            if let meters = settings.mapScale.meters, let center = lastCenter, let location = tracker.lastLocation,
               location.distance(from: center) < meters * 0.1 {
                return
            }
            recenter(animated: true)
        }
    }

    /// Runder Umschalter privat/geschäftlich; gilt für alle Punkte ab jetzt.
    private var categoryButton: some View {
        let category = settings.tripCategory
        return Button {
            settings.tripCategory = category.toggled
        } label: {
            Image(systemName: category.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(category == .business ? Color.orange : Color.green, in: .circle)
                .shadow(radius: 2)
        }
        .sensoryFeedback(.selection, trigger: category)
        .accessibilityLabel("Strecke: \(category.title)")
        .accessibilityHint("Wechselt zu \(category.toggled.title)")
    }

    /// Auswahl des Kartenausschnitts und Schalter „Folgen“.
    private var scaleBar: some View {
        @Bindable var settings = settings
        return HStack(spacing: 8) {
            Picker("Kartenausschnitt", selection: $settings.mapScale) {
                ForEach(MapScale.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                follow.toggle()
                if follow { recenter(animated: true) }
            } label: {
                Image(systemName: follow ? "location.fill" : "location.slash")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(follow ? "Folgen aus" : "Folgen an")
        }
        .padding(6)
        .background(.regularMaterial, in: .capsule)
    }

    /// Setzt den Ausschnitt auf die aktuelle Position mit der gewählten Breite.
    private func recenter(animated: Bool) {
        let target: MapCameraPosition
        lastCenter = nil
        if let meters = settings.mapScale.meters, let location = tracker.lastLocation {
            lastCenter = location
            target = .region(MKCoordinateRegion(center: location.coordinate,
                                                latitudinalMeters: meters, longitudinalMeters: meters))
        } else if tracker.isSimulating, let location = tracker.lastLocation {
            target = .camera(MapCamera(centerCoordinate: location.coordinate,
                                       distance: tracker.activeSimulation == .cgnAirport ? 2500 : 4000))
        } else if settings.mapScale.meters == nil {
            target = .userLocation(followsHeading: false, fallback: .automatic)
        } else {
            return      // feste Breite, aber noch keine Position bekannt
        }
        if animated {
            withAnimation(.linear(duration: 0.8)) { position = target }
        } else {
            position = target
        }
    }

    private var categoryLabel: some View {
        let category = settings.tripCategory
        return Label("Strecke: \(category.title)", systemImage: category.systemImage)
            .font(.caption)
            .foregroundStyle(category == .business ? Color.orange : Color.green)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Button {
                settings.trackingEnabled.toggle()
                settings.trackingEnabled ? tracker.start() : tracker.stop()
            } label: {
                Label(tracker.isRunning ? "Stopp" : "Start",
                      systemImage: tracker.isRunning ? "stop.circle.fill" : "record.circle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isRunning ? .red : .blue)

            VStack(alignment: .leading, spacing: 2) {
                if let location = tracker.lastLocation {
                    let quality = AccuracyQuality(location.horizontalAccuracy)
                    Label("\(Format.meters(location.horizontalAccuracy, plusMinus: true)) (\(quality.title))",
                          systemImage: "scope")
                        .foregroundStyle(quality.color)
                    Text("\(Format.speed(location.speed)) · heute \(todayPoints.count) Punkte")
                        .foregroundStyle(.secondary)
                    categoryLabel
                } else {
                    Text(tracker.diagnostic ?? (tracker.isRunning ? "Warte auf Position …" : "Aufzeichnung aus"))
                        .foregroundStyle(.secondary)
                    categoryLabel
                }
                if tracker.isStationary {
                    Text("Stillstand – keine neuen Punkte").font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
