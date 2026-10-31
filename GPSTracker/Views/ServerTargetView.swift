import SwiftUI

/// Zeile in der Zielliste: Tippen öffnet die Details, der Schalter aktiviert/deaktiviert das Ziel.
struct ServerTargetRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UploadService.self) private var uploads
    let target: ServerTarget

    var body: some View {
        let status = uploads.status(for: target.id)
        HStack {
            NavigationLink {
                ServerTargetView(targetID: target.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                    Group {
                        if target.url.isEmpty {
                            Text("nicht eingerichtet")
                        } else if status.lastError != nil && target.enabled {
                            Text("Fehler · \(status.pendingCount) offen").foregroundStyle(.red)
                        } else {
                            Text("\(target.validURL?.host() ?? target.url) · \(status.pendingCount) offen")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            Toggle("Aktiv", isOn: Binding(
                get: { target.enabled },
                set: { on in settings.updateTarget(target.id) { $0.enabled = on } }
            ))
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// Detailansicht eines Serverziels.
struct ServerTargetView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UploadService.self) private var uploads
    let targetID: Int

    @State private var password = ""
    @State private var confirmDiscard = false
    @State private var confirmResend = false
    // Weitergeben per E-Mail / Teilen
    @State private var sharePassword = false
    @State private var mailFile: (url: URL, data: Data)?
    @State private var shareMessage: String?

    private func binding<T>(_ keyPath: WritableKeyPath<ServerTarget, T>, default value: T) -> Binding<T> {
        Binding(
            get: { settings.target(targetID)?[keyPath: keyPath] ?? value },
            set: { newValue in settings.updateTarget(targetID) { $0[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        let target = settings.target(targetID) ?? .preset(targetID)
        let status = uploads.status(for: targetID)
        Form {
            Section {
                Toggle("Aktiv", isOn: binding(\.enabled, default: false))
                TextField("Name", text: binding(\.name, default: ""))
            }
            Section {
                TextField("https://server.example/api/track", text: binding(\.url, default: ""))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Benutzer", text: binding(\.account, default: ""))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Passwort", text: $password)
                    .textContentType(.password)
                    .onChange(of: password) { settings.setPassword(password, for: targetID) }
            } header: {
                Text("Zugang")
            } footer: {
                if !target.url.isEmpty && !target.hasValidURL {
                    Text("Ungültige Adresse – erwartet wird eine http(s)-URL.").foregroundStyle(.red)
                } else if let warning = target.transportWarning {
                    Text(warning).foregroundStyle(.orange)
                } else if targetID == 4, let preset = ServerTarget.presetTarget4, target.url == preset.url {
                    Text("Vorbelegt aus den privaten Voreinstellungen (\(preset.name)).")
                }
                if targetID == 4, let preset = ServerTarget.presetTarget4, target.url != preset.url {
                    Button("Vorbelegte Adresse eintragen („\(preset.name)“)") {
                        settings.updateTarget(targetID) { $0.url = preset.url }
                    }
                }
            }
            Section("Status") {
                LabeledContent("Nicht übertragen", value: "\(status.pendingCount) Punkte")
                LabeledContent("Letzte Übertragung",
                               value: target.lastUploadAt?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                if let error = status.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Button {
                    Task { await uploads.upload(to: targetID) }
                } label: {
                    HStack {
                        Text("Jetzt an dieses Ziel übertragen")
                        Spacer()
                        if status.isUploading { ProgressView() }
                    }
                }
                .disabled(status.isUploading || !target.hasValidURL)
            }
            Section {
                Button("Rückstand verwerfen …") { confirmDiscard = true }
                    .confirmationDialog("Rückstand verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                        Button("\(status.pendingCount) Punkte als übertragen markieren", role: .destructive) {
                            uploads.setAllUploaded(true, target: targetID)
                        }
                    }
                Button("Alle Punkte erneut senden …") { confirmResend = true }
                    .confirmationDialog("Alle Punkte erneut senden?", isPresented: $confirmResend, titleVisibility: .visible) {
                        Button("Alle Punkte als offen markieren") {
                            uploads.setAllUploaded(false, target: targetID)
                        }
                    } message: {
                        Text("Beim nächsten Lauf wird der komplette Verlauf an dieses Ziel übertragen.")
                    }
            } header: {
                Text("Rückstand")
            } footer: {
                Text("Ein neu aktiviertes Ziel erhält zunächst alle bisher gespeicherten Punkte. „Rückstand verwerfen“ markiert sie für dieses Ziel als übertragen, sodass nur noch neue Punkte gesendet werden.")
            }
            shareSection(target)
        }
        .sheet(isPresented: Binding(get: { mailFile != nil }, set: { if !$0 { mailFile = nil } })) {
            if let file = mailFile {
                MailComposer(
                    subject: "GPS-Tracker-Serverziel „\(target.name)“",
                    body: "Im Anhang das Serverziel „\(target.name)“ für die GPS-Tracker-App.\n\n"
                        + "Übernehmen: Anhang antippen und mit „GPS Tracker“ öffnen – oder speichern und in der App unter "
                        + "Einstellungen → Serverziele importieren auswählen."
                        + (sharePassword ? "\n\nAchtung: Das Passwort ist im Anhang enthalten." : ""),
                    attachment: file.data, mimeType: "application/vnd.gpstracker.servertarget+json",
                    fileName: file.url.lastPathComponent
                ) { result in
                    shareMessage = result == .sent ? "E-Mail gesendet." : result == .saved ? "Als Entwurf gespeichert." : nil
                }
                .ignoresSafeArea()
            }
        }
        .navigationTitle(target.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { password = settings.password(for: targetID) }
    }

    private func shareSection(_ target: ServerTarget) -> some View {
        Section {
            Toggle("Passwort mitsenden", isOn: $sharePassword)
            Button("Per E-Mail senden …") {
                if let file = try? SettingsTransfer.singleTargetFile(target, password: sharePassword ? password : nil) {
                    mailFile = file
                }
            }
            .disabled(!MailComposer.canSend || target.url.isEmpty)
            if let file = try? SettingsTransfer.singleTargetFile(target, password: sharePassword ? password : nil) {
                ShareLink("Teilen …", item: file.url)
                    .disabled(target.url.isEmpty)
            }
            if let message = shareMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Weitergeben")
        } footer: {
            if !MailComposer.canSend {
                Text("Auf diesem Gerät ist kein Mail-Konto eingerichtet – bitte „Teilen …“ verwenden (dort ist auch Mail auswählbar).")
            } else if sharePassword {
                Text("Achtung: Das Passwort steht im Klartext im Anhang.").foregroundStyle(.orange)
            } else {
                Text("Erstellt eine E-Mail mit dem Ziel als Anhang (.gpsziel); den Empfänger trägst du ein. Der Empfänger öffnet den Anhang mit der GPS-Tracker-App.")
            }
        }
    }
}
