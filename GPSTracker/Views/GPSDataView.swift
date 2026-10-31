import CoreLocation
import SwiftData
import SwiftUI

/// Rohdaten der aktuellen Messung inkl. Genauigkeit, Status und Speicherstand.
struct GPSDataView: View {
    @Environment(LocationTracker.self) private var tracker
    @Environment(UploadService.self) private var uploads
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var totalCount = 0

    var body: some View {
        NavigationStack {
            List {
                if let location = tracker.lastLocation {
                    measurementSections(location)
                } else {
                    Section {
                        Text(tracker.diagnostic ?? (tracker.isRunning ? "Warte auf Position …" : "Aufzeichnung ist ausgeschaltet."))
                            .foregroundStyle(.secondary)
                    }
                }
                statusSection
                storageSection
            }
            .navigationTitle("GPS-Daten")
            .onAppear(perform: refreshCounts)
            .onChange(of: tracker.storedSinceLaunch) { refreshCounts() }
        }
    }

    @ViewBuilder
    private func measurementSections(_ location: CLLocation) -> some View {
        let quality = AccuracyQuality(location.horizontalAccuracy)
        Section("Position") {
            LabeledContent("Breite", value: Format.coordinate(location.coordinate.latitude))
            LabeledContent("Länge", value: Format.coordinate(location.coordinate.longitude))
            LabeledContent("Höhe (Meeresspiegel)", value: Format.meters(location.altitude))
            LabeledContent("Höhe (Ellipsoid)", value: Format.meters(location.ellipsoidalAltitude))
            if let floor = location.floor {
                LabeledContent("Stockwerk", value: "\(floor.level)")
            }
        }
        Section("Genauigkeit") {
            LabeledContent("Horizontal") {
                Text("\(Format.meters(location.horizontalAccuracy, plusMinus: true)) · \(quality.title)")
                    .foregroundStyle(quality.color)
            }
            LabeledContent("Vertikal", value: Format.meters(location.verticalAccuracy, plusMinus: true))
            LabeledContent("Geschwindigkeit", value: location.speedAccuracy >= 0 ? "± " + Format.speed(location.speedAccuracy) : "–")
            LabeledContent("Kurs", value: location.courseAccuracy >= 0 ? "± " + Format.course(location.courseAccuracy) : "–")
            LabeledContent("Freigabe", value: tracker.accuracyAuthorization == .fullAccuracy ? "genau" : "ungefähr")
        }
        Section("Bewegung") {
            LabeledContent("Geschwindigkeit", value: Format.speed(location.speed))
            LabeledContent("Kurs", value: Format.course(location.course))
            LabeledContent("Status", value: tracker.isStationary ? "Stillstand" : "in Bewegung")
        }
        Section {
            LabeledContent("Messzeit", value: location.timestamp.formatted(date: .omitted, time: .standard))
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LabeledContent("Alter",
                               value: "\(max(0, Int(timeline.date.timeIntervalSince(location.timestamp)))) s")
            }
            if tracker.isSimulating {
                LabeledContent("Quelle", value: "Simulation – \(tracker.activeSimulation.title)")
                if let route = tracker.simulationRouteName {
                    LabeledContent("Route", value: route)
                }
            } else if let info = location.sourceInformation {
                LabeledContent("Quelle", value: info.isSimulatedBySoftware ? "simuliert" : "Gerät")
            }
        } header: {
            Text("Zeit")
        } footer: {
            Text("Apple stellt keine Satellitenanzahl oder Rohdaten des GPS-Empfängers bereit; die Genauigkeit ist der von iOS geschätzte Radius (68 % Wahrscheinlichkeit).")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Aufzeichnung", value: tracker.isRunning ? "läuft" : "aus")
            LabeledContent("Tracker", value: settings.effectiveTrackerName)
            LabeledContent("Software-Version", value: AppInfo.fullVersion)
            LabeledContent("Standortzugriff", value: tracker.authorizationStatus.title)
            if let diagnostic = tracker.diagnostic {
                Text(diagnostic).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section("Speicher") {
            LabeledContent("Punkte gesamt", value: "\(totalCount)")
        }
        Section("Übertragung") {
            if settings.enabledTargets.isEmpty {
                Text("Kein Serverziel aktiv").foregroundStyle(.secondary)
            }
            ForEach(settings.enabledTargets) { target in
                let status = uploads.status(for: target.id)
                LabeledContent {
                    Text("\(status.pendingCount) offen")
                        .foregroundStyle(status.lastError == nil ? Color.secondary : Color.red)
                } label: {
                    Text(target.name)
                    Text(target.lastUploadAt.map { "zuletzt " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "noch nie übertragen")
                }
            }
        }
    }

    private func refreshCounts() {
        totalCount = (try? context.fetchCount(FetchDescriptor<TrackPoint>())) ?? 0
        uploads.refreshPendingCount()
    }
}
