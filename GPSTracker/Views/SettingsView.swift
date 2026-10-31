import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Einstellungen: Aufzeichnung, Server, Übertragung, Verlauf, Backup und Datenpflege.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationTracker.self) private var tracker
    @Environment(UploadService.self) private var uploads
    @Environment(BackupService.self) private var backup
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    private enum ImportTarget { case folder, restore, serverTargets }
    /// Modus des Dateidialogs. Bleibt nach dem Schließen erhalten, denn SwiftUI setzt
    /// `showImporter` zurück, bevor der Ergebnis-Handler läuft.
    @State private var importTarget: ImportTarget = .folder
    @State private var showImporter = false
    // Export/Import von Einstellungen und Serverzielen
    @State private var exportPasswords = false
    @State private var exportDocument: JSONFileDocument?
    @State private var exportName = ""
    @State private var showExporter = false
    @State private var importCandidates: [SettingsExport.Target]?
    @State private var transferMessage: String?
    @State private var transferError: String?
    @State private var restoreSettings = false
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                trackerSection(settings)
                recordingSection(settings)
                simulationSection(settings)
                serverSection
                uploadSection(settings)
                Section("Verlauf") {
                    Picker("Standard-Zeitraum", selection: $settings.historyDefaultRange) {
                        ForEach(HistoryRange.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
                    }
                }
                backupSection
                transferSection
                dataSection
                Section {
                    LabeledContent("Software-Version", value: AppInfo.fullVersion)
                    LabeledContent("Geräte-ID", value: settings.deviceID).font(.caption)
                } header: {
                    Text("Info")
                } footer: {
                    Text(SimulationRouteSet.shared?.attribution ?? "")
                }
            }
            .navigationTitle("Einstellungen")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importTarget == .folder ? [.folder]
                    : importTarget == .serverTargets ? [.gpsServerTarget, .json] : [.json]
            ) { result in
                guard case .success(let url) = result else { return }
                switch importTarget {
                case .folder: backup.setFolder(url)
                case .restore:
                    backup.restore(from: url, includeSettings: restoreSettings)
                    tracker.reloadLastStored()
                    uploads.refreshPendingCount()
                case .serverTargets:
                    do {
                        let targets = try SettingsTransfer.readTargets(from: url)
                        if targets.isEmpty { transferError = "Die Datei enthält keine Serverziele." }
                        else { importCandidates = targets; transferError = nil }
                    } catch {
                        transferError = "Datei konnte nicht gelesen werden (keine Einstellungs-, Serverziel- oder Backup-Datei)."
                    }
                }
            }
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                          defaultFilename: exportName) { result in
                switch result {
                case .success(let url): transferMessage = "Gespeichert: \(url.lastPathComponent)"; transferError = nil
                case .failure(let error): transferError = "Export fehlgeschlagen: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: Binding(get: { importCandidates != nil }, set: { if !$0 { importCandidates = nil } })) {
                TargetImportView(candidates: importCandidates ?? []) { message in
                    transferMessage = message
                    uploads.refreshPendingCount()
                }
            }
        }
    }

    private func trackerSection(_ settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            TextField("Name des Trackers", text: $settings.trackerName)
                .autocorrectionDisabled()
            if settings.trackerName != SettingsStore.deviceName {
                Button("Gerätenamen übernehmen („\(SettingsStore.deviceName)“)") {
                    settings.trackerName = SettingsStore.deviceName
                }
            }
        } header: {
            Text("Tracker")
        } footer: {
            Text("Wird mit jeder Übertragung gesendet, damit der Server die Tracker unterscheiden kann. iOS gibt Apps ohne Sonderfreigabe nur den Modellnamen (z. B. „iPhone“) heraus – dann bitte einen eigenen Namen vergeben.")
        }
    }

    private func simulationSection(_ settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker("Betriebsart", selection: $settings.simulationMode) {
                ForEach(SimulationMode.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: settings.simulationMode) { tracker.restartIfRunning() }
            if settings.simulationMode != .off {
                Picker("Zeitraffer", selection: $settings.simulationSpeed) {
                    ForEach([1, 5, 20, 60], id: \.self) { Text("\($0)×").tag($0) }
                }
                .onChange(of: settings.simulationSpeed) { tracker.restartIfRunning() }
                if let route = tracker.simulationRouteName {
                    LabeledContent("Aktuelle Route", value: route)
                } else if !tracker.isRunning {
                    Text("Startet mit der Aufzeichnung.").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Simulation")
        } footer: {
            Text(settings.simulationMode.explanation + (settings.simulationMode == .off ? "" : " Simulierte Punkte werden gespeichert und übertragen, aber als „\(settings.simulationMode.source)“ gekennzeichnet. Beim Zeitraffer wird die Strecke schneller abgefahren; die Geschwindigkeit zeigt dann die tatsächliche Verschiebung."))
        }
    }

    private func recordingSection(_ settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Aufzeichnung aktiv", isOn: Binding(
                get: { settings.trackingEnabled },
                set: { on in
                    settings.trackingEnabled = on
                    on ? tracker.start() : tracker.stop()
                }
            ))
            Stepper("Mindestabstand: \(Int(settings.minDistance)) m", value: $settings.minDistance, in: 1...500, step: 5)
            Stepper("Max. Ungenauigkeit: \(Int(settings.maxAccuracy)) m", value: $settings.maxAccuracy, in: 5...500, step: 5)
            LabeledContent("Standortzugriff", value: tracker.authorizationStatus.title)
            if tracker.authorizationStatus == .authorizedWhenInUse {
                Button("„Immer“ erlauben anfragen") { tracker.requestAlwaysAuthorization() }
            }
            if tracker.authorizationStatus == .denied || tracker.accuracyAuthorization == .reducedAccuracy {
                Button("iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Aufzeichnung")
        } footer: {
            Text("Gespeichert wird nur bei Bewegung: ein neuer Punkt, sobald er den Mindestabstand zum letzten Punkt überschreitet und genauer als die maximale Ungenauigkeit ist.")
        }
    }

    private var serverSection: some View {
        Section {
            ForEach(settings.targets) { target in
                ServerTargetRow(target: target)
            }
        } header: {
            Text("Serverziele")
        } footer: {
            Text("Alle aktiven Ziele erhalten dieselben Daten; jedes Ziel hat seinen eigenen Rückstand."
                 + (ServerTarget.presetTarget4 == nil ? "" : " Ziel 4 ist über die privaten Voreinstellungen vorbelegt – nur Passwort eintragen und einschalten."))
        }
    }

    private func uploadSection(_ settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return Section {
            Picker("Modus", selection: $settings.uploadMode) {
                ForEach(UploadMode.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: settings.uploadMode) { uploads.scheduleBackgroundRefresh() }
            switch settings.uploadMode {
            case .live:
                Stepper("Sammelintervall: \(settings.liveIntervalSeconds) s",
                        value: $settings.liveIntervalSeconds, in: 1...300)
            case .scheduled:
                DatePicker("Uhrzeit", selection: scheduledTime, displayedComponents: .hourAndMinute)
                LabeledContent("Nächster Lauf",
                               value: uploads.nextScheduledRun.formatted(date: .abbreviated, time: .shortened))
            case .manual:
                EmptyView()
            }
            Button {
                Task { await uploads.uploadPending() }
            } label: {
                HStack {
                    Text("Jetzt an alle aktiven Ziele übertragen")
                    Spacer()
                    if uploads.isUploading { ProgressView() }
                }
            }
            .disabled(uploads.isUploading || settings.enabledTargets.isEmpty)
            LabeledContent("Nicht übertragen (aktive Ziele)", value: "\(uploads.pendingCountEnabled) Punkte")
            if let error = uploads.generalError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        } header: {
            Text("Übertragung")
        } footer: {
            Text(settings.uploadMode.explanation)
        }
    }

    private var scheduledTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings.scheduledMinutes * 60))
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.scheduledMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                uploads.scheduleBackgroundRefresh()
            }
        )
    }

    private var backupSection: some View {
        Section {
            Button {
                importTarget = .folder
                showImporter = true
            } label: {
                LabeledContent("Speicherziel", value: settings.backupFolderName ?? "nicht gewählt")
            }
            Button {
                backup.createBackup()
            } label: {
                HStack {
                    Text("Backup jetzt erstellen")
                    Spacer()
                    if backup.isWorking { ProgressView() }
                }
            }
            .disabled(settings.backupFolderBookmark == nil || backup.isWorking)
            LabeledContent("Letztes Backup",
                           value: settings.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "–")
            Toggle("Beim Wiederherstellen auch Einstellungen übernehmen", isOn: $restoreSettings)
            Button("Backup wiederherstellen …") {
                importTarget = .restore
                showImporter = true
            }
            if let message = backup.lastMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if let error = backup.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Gesichert werden Einstellungen (ohne Passwort) und alle GPS-Punkte als JSON-Datei. Als Ziel eignet sich jeder Ordner der Dateien-App, z. B. iCloud Drive, „Auf meinem iPhone“ oder ein verbundener Server.")
        }
    }

    private var transferSection: some View {
        Section {
            Toggle("Passwörter einschließen", isOn: $exportPasswords)
            Button("Einstellungen exportieren …") { export(.settings) }
            Button("Serverziele exportieren …") { export(.serverTargets) }
            Button("Serverziele importieren …") {
                importTarget = .serverTargets
                showImporter = true
            }
            if let message = transferMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if let error = transferError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Einstellungen & Serverziele übertragen")
        } footer: {
            if exportPasswords {
                Text("Achtung: Die Passwörter stehen im Klartext in der Datei. Nur an einem sicheren Ort speichern.")
                    .foregroundStyle(.orange)
            } else {
                Text("Export als JSON-Datei (Ziel frei wählbar). Beim Import wählst du, welche Ziele auf welchen Platz übernommen werden; lesbar sind auch Backup-Dateien.")
            }
        }
    }

    private func export(_ kind: SettingsTransfer.Kind) {
        do {
            let file = SettingsTransfer.makeExport(kind, settings: settings, includePasswords: exportPasswords)
            exportDocument = JSONFileDocument(data: try SettingsTransfer.encode(file))
            exportName = SettingsTransfer.fileName(kind)
            showExporter = true
        } catch {
            transferError = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private var dataSection: some View {
        Section("Daten") {
            Button("Alle GPS-Daten löschen …", role: .destructive) { confirmDelete = true }
                .confirmationDialog("Alle GPS-Daten löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Endgültig löschen", role: .destructive, action: deleteAll)
                } message: {
                    Text("Alle lokal gespeicherten Punkte werden entfernt. Erstelle vorher ein Backup.")
                }
        }
    }

    private func deleteAll() {
        try? context.delete(model: TrackPoint.self)
        try? context.save()
        tracker.reloadLastStored()
        uploads.refreshPendingCount()
    }
}
