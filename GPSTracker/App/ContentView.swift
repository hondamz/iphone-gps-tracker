import SwiftUI

struct ContentView: View {
    @Environment(UploadService.self) private var uploads
    /// Ziele aus einer per „Öffnen in …“ übergebenen Datei (.gpsziel/JSON).
    @State private var incoming: [SettingsExport.Target]?
    @State private var incomingError: String?

    var body: some View {
        tabs
            .onOpenURL { url in
                do {
                    let targets = try SettingsTransfer.readTargets(from: url)
                    if targets.isEmpty { incomingError = "Die Datei enthält keine Serverziele." } else { incoming = targets }
                } catch {
                    incomingError = "Die Datei „\(url.lastPathComponent)“ konnte nicht gelesen werden."
                }
            }
            .sheet(isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } })) {
                TargetImportView(candidates: incoming ?? []) { _ in uploads.refreshPendingCount() }
            }
            .alert("Import nicht möglich", isPresented: Binding(get: { incomingError != nil },
                                                               set: { if !$0 { incomingError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(incomingError ?? "")
            }
    }

    private var tabs: some View {
        TabView {
            Tab("Live", systemImage: "location.fill") {
                LiveMapView()
            }
            Tab("Verlauf", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                HistoryView()
            }
            Tab("GPS-Daten", systemImage: "gauge.with.dots.needle.33percent") {
                GPSDataView()
            }
            Tab("Einstellungen", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
