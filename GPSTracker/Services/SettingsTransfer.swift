import Foundation
import MessageUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Einzelnes oder mehrere Serverziele zum Weitergeben (Endung `.gpsziel`, Inhalt JSON).
    static let gpsServerTarget = UTType(exportedAs: "io.github.hondamz.gpstracker.servertarget", conformingTo: .json)
}

/// Export-Datei für Einstellungen und Serverziele (JSON).
/// `kind` = "settings" (alle Einstellungen inkl. Ziele) oder "serverTargets" (nur Ziele).
nonisolated struct SettingsExport: Codable, Sendable {
    /// Serverziel im Export; `password` nur, wenn beim Export ausdrücklich gewählt.
    struct Target: Codable, Sendable, Identifiable {
        var id: Int
        var name: String
        var enabled: Bool
        var url: String
        var account: String
        var password: String?
    }

    var formatVersion = 1
    var kind: String
    var exportedAt: Date
    var appVersion: String
    /// Übrige Einstellungen (nur bei kind = "settings"; Ziele stehen in `targets`).
    var settings: SettingsSnapshot?
    var targets: [Target]

    static let fileType = UTType.json
}

/// Erstellen und Einlesen der Export-Dateien.
enum SettingsTransfer {
    enum Kind { case settings, serverTargets }

    static func makeExport(_ kind: Kind, settings: SettingsStore, includePasswords: Bool) -> SettingsExport {
        let targets = settings.targets.map { t in
            SettingsExport.Target(id: t.id, name: t.name, enabled: t.enabled, url: t.url, account: t.account,
                                  password: includePasswords ? nonEmpty(settings.password(for: t.id)) : nil)
        }
        var snapshot: SettingsSnapshot?
        if kind == .settings {
            snapshot = settings.snapshot
            snapshot?.targets = nil          // Ziele stehen (mit optionalem Passwort) in `targets`
        }
        return SettingsExport(kind: kind == .settings ? "settings" : "serverTargets", exportedAt: .now,
                              appVersion: AppInfo.fullVersion, settings: snapshot, targets: targets)
    }

    static func encode(_ export: SettingsExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    static func fileName(_ kind: Kind) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return (kind == .settings ? "GPSTracker-Einstellungen-" : "GPSTracker-Serverziele-") + f.string(from: .now)
    }

    /// Liest Serverziele aus einer Export-Datei (Einstellungen oder Ziele) oder aus einem Backup.
    static func readTargets(from url: URL) throws -> [SettingsExport.Target] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let export = try? decoder.decode(SettingsExport.self, from: data) {
            return export.targets
        }
        if let backup = try? decoder.decode(BackupFile.self, from: data), let targets = backup.settings.targets {
            return targets.map { .init(id: $0.id, name: $0.name, enabled: $0.enabled, url: $0.url, account: $0.account) }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    /// Ein einzelnes Ziel als `.gpsziel`-Datei (für E-Mail/Teilen); Passwort nur auf Wunsch.
    static func singleTargetFile(_ target: ServerTarget, password: String?) throws -> (url: URL, data: Data) {
        let export = SettingsExport(kind: "serverTargets", exportedAt: .now, appVersion: AppInfo.fullVersion,
                                    settings: nil,
                                    targets: [.init(id: target.id, name: target.name, enabled: target.enabled,
                                                    url: target.url, account: target.account,
                                                    password: password.flatMap(nonEmpty))])
        let data = try encode(export)
        let safeName = target.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "Serverziel \(safeName).gpsziel")
        try data.write(to: url, options: .atomic)
        return (url, data)
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}

/// E-Mail-Fenster des Systems mit Anhang; Empfänger trägt der Nutzer ein.
struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachment: Data
    let mimeType: String
    let fileName: String
    let onFinish: (MFMailComposeResult) -> Void

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.addAttachmentData(attachment, mimeType: mimeType, fileName: fileName)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, @MainActor MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}

/// Datei-Dokument für `fileExporter`.
struct JSONFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Auswahl beim Import: welche Ziele übernommen werden und auf welchen Platz (Ziel 1–4).
struct TargetImportView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let candidates: [SettingsExport.Target]
    let onDone: (String) -> Void

    @State private var selected: Set<Int> = []
    @State private var slot: [Int: Int] = [:]

    private var conflict: Bool {
        let slots = selected.compactMap { slot[$0] }
        return Set(slots).count != slots.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(candidates.indices, id: \.self) { i in
                        row(i)
                    }
                } footer: {
                    Text("Übernommene Ziele ersetzen den gewählten Platz. Passwörter werden nur übernommen, wenn sie in der Datei enthalten sind – sonst bleibt das vorhandene Passwort des Platzes erhalten. Der Übertragungsstand des Platzes bleibt; bei neuem Server ggf. unter „Rückstand“ anpassen.")
                }
                if conflict {
                    Text("Mehrere Ziele sind demselben Platz zugeordnet.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Serverziele importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen", action: apply).disabled(selected.isEmpty || conflict)
                }
            }
            .onAppear {
                for (i, c) in candidates.enumerated() {
                    slot[i] = ServerTarget.slots.contains(c.id) ? c.id : ServerTarget.slots[min(i, 3)]
                    if !c.url.isEmpty { selected.insert(i) }
                }
            }
        }
    }

    private func row(_ i: Int) -> some View {
        let c = candidates[i]
        let target = slot[i] ?? c.id
        let existing = settings.target(target)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { selected.contains(i) },
                                 set: { if $0 { selected.insert(i) } else { selected.remove(i) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name)
                    Text(c.url.isEmpty ? "keine Adresse" : c.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text([c.account.isEmpty ? nil : "Benutzer \(c.account)", c.password == nil ? nil : "mit Passwort",
                          c.enabled ? "aktiv" : "inaktiv"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if selected.contains(i) {
                Picker("Platz", selection: Binding(get: { target }, set: { slot[i] = $0 })) {
                    ForEach(ServerTarget.slots, id: \.self) { Text("Ziel \($0)").tag($0) }
                }
                if let existing, !existing.url.isEmpty {
                    Text("ersetzt „\(existing.name)“ (\(existing.url))").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func apply() {
        for i in selected.sorted() {
            let c = candidates[i]
            guard let target = slot[i] else { continue }
            settings.updateTarget(target) {
                $0.name = c.name
                $0.url = c.url
                $0.account = c.account
                $0.enabled = c.enabled
            }
            if let password = c.password { settings.setPassword(password, for: target) }
        }
        onDone("\(selected.count) Serverziel(e) übernommen")
        dismiss()
    }
}
