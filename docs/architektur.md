# Architektur

Stand: v0.5.0 (04.10.2026)

## Überblick

```
┌──────────────────────── SwiftUI (TabView) ────────────────────────┐
│ LiveMapView   HistoryView   GPSDataView   SettingsView            │
└──────┬─────────────┬────────────┬──────────────┬──────────────────┘
       │ @Environment (Observable-Objekte)  @Query (SwiftData)
┌──────▼──────────┐ ┌▼─────────────┐ ┌──────────▼──────┐ ┌──────────────┐
│ LocationTracker │ │ UploadService│ │ BackupService   │ │ SettingsStore│
│ CoreLocation    │ │ BGTask, Modi │ │ JSON, Bookmarks │ │ UserDefaults │
└──────┬──────────┘ └──┬────────┬──┘ └────────┬────────┘ │ + Keychain   │
       │ insert        │ fetch  │ TrackUploader (Protokoll)└──────────────┘
┌──────▼───────────────▼──┐  ┌──▼───────────────────────┐
│ SwiftData: TrackPoint    │  │ ProvisionalJSONUploader  │──► Ziel 1 / 2 / 3 (aktive)
└──────────────────────────┘  └──────────────────────────┘
```

- **Swift 6** mit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: der App-Code läuft auf dem MainActor,
  reine Datentypen (`TrackPointRecord`, `SettingsSnapshot`, …) sind `nonisolated` + `Sendable`.
- Die Dienste werden einmal in `GPSTrackerApp.init()` erzeugt und per `.environment(_:)` an die Views gegeben.
- Das Xcode-Projekt nutzt einen *synchronisierten Ordner* (`GPSTracker/`) – keine Dateiliste im `project.pbxproj`.

## Komponenten

| Komponente | Datei | Aufgabe |
|---|---|---|
| `GPSTrackerApp` | App/GPSTrackerApp.swift | Container + Dienste erzeugen, Aufzeichnung fortsetzen, Szenenwechsel, BGAppRefresh |
| `LocationTracker` | Services/LocationTracker.swift | Standort-Updates, Filter, Speichern, Berechtigungen, Diagnose |
| `UploadService` | Services/UploadService.swift | offene Punkte je aktivem Ziel paketweise senden, Status pro Ziel, Live-Bündelung, Zeitplan, BGTask |
| `TrackUploader` | Services/TrackUploader.swift | Protokoll der Server-Schnittstelle + vorläufige JSON-Implementierung |
| `BackupService` | Services/BackupService.swift | Backup schreiben/einlesen, Ordner-Bookmark |
| `SettingsStore` | Services/SettingsStore.swift | alle Einstellungen, drei `ServerTarget`s, Migration aus v0.1, Snapshot fürs Backup |
| `ServerTargetView` | Views/ServerTargetView.swift | Zielzeile mit Schalter + Detailansicht (Zugang, Status, Rückstand) |
| `AirportPlanner` | Services/AirportPlanner.swift | erzeugt am Flughafen fortlaufend zufällige Abschnitte (Wegsuche im OSM-Wegenetz, Abdeckung, Ausflüge) |
| `LocationSimulator` | Services/LocationSimulator.swift | fährt Routen aus `SimulationRoutes.json` ab (1 Hz, Zeitraffer, Messrauschen) |
| `AppInfo` | Support/AppInfo.swift | Software-Version und Build aus dem Bundle |
| `TrackSegments` | Support/TrackSegments.swift | teilt die Spur an Pausen > 5 min (Darstellung, Streckenberechnung) |
| `KeychainStore` | Services/KeychainStore.swift | Passwort (`AfterFirstUnlockThisDeviceOnly`) |

## Datenmodell

`TrackPoint` (SwiftData, Index auf `timestamp`):

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | UUID (unique) | stabile ID, für Backup-Merge und Server-Deduplizierung |
| `timestamp` | Date | Messzeit laut CoreLocation |
| `latitude`, `longitude` | Double | WGS84 in Grad |
| `altitude` / `ellipsoidalAltitude` | Double | Höhe über Meeresspiegel / über WGS84-Ellipsoid (m) |
| `horizontalAccuracy`, `verticalAccuracy` | Double | geschätzter Fehlerradius (m), < 0 = ungültig |
| `speed`, `speedAccuracy` | Double | m/s, < 0 = ungültig |
| `course`, `courseAccuracy` | Double | Grad (0 = Nord), < 0 = ungültig |
| `appVersion` | String? | Software-Version bei der Aufzeichnung (`nil` = vor v0.3.0) |
| `tripCategory` | String? | `private` oder `business`; `nil` = vor v0.10.0 aufgezeichnet. Wird beim Speichern aus `SettingsStore.tripCategory` übernommen und danach nicht mehr geändert |
| `source` | String | `gps` oder `simulation-germany` / `simulation-cgnAirport` (Standard `gps`, auch für Altbestand) |
| `uploadedAt1`, `uploadedAt2`, `uploadedAt3` | Date? | Zeitpunkt der Übertragung an Ziel 1/2/3, `nil` = offen. `uploadedAt1` hieß in v0.1 `uploadedAt` (`@Attribute(originalName:)` → automatische Migration) |

`TrackPointRecord` ist die gleiche Struktur als `Codable`-Wert für das Backup (liest auch das v0.1-Feld
`uploadedAt` als Ziel 1). An den Server geht eine schlanke Variante ohne die Übertragungsfelder.

`ServerTarget` (in UserDefaults als JSON unter `serverTargets`, immer genau IDs 1–4; Ziel 4 mit `ServerTarget.preset(4)` = Viewer über Tailscale vorbelegt):
`id`, `name`, `enabled`, `url`, `account`, `lastUploadAt`. Passwörter liegen in der Keychain
(`server-password-1…3`). Beim ersten Start nach v0.1 wird der alte Einzelserver zu Ziel 1 (aktiv).

## Abläufe

### Aufzeichnung
1. `start()` erzeugt `CLServiceSession(.whenInUse)` + `CLBackgroundActivitySession` und iteriert
   `CLLocationUpdate.liveUpdates(.otherNavigation)`.
2. Jedes Update aktualisiert `lastLocation` (Live-Anzeige). Gespeichert wird nur, wenn
   `0 ≤ horizontalAccuracy ≤ maxAccuracy` **und** Abstand zum zuletzt gespeicherten Punkt ≥ `minDistance`.
3. Bei Stillstand liefert iOS automatisch keine bzw. seltene Updates (`stationary`).
4. Ist die Aufzeichnung eingeschaltet, startet `GPSTrackerApp.init()` sie bei jedem App-Start neu –
   auch wenn iOS die App im Hintergrund neu startet.

### Simulation
- `LocationTracker.start()` startet bei aktiver Betriebsart den `LocationSimulator`; dessen Positionen
  laufen durch denselben Filter/Speicherweg wie echte GPS-Daten, mit `source = simulation-…`.
- Die echten CoreLocation-Updates laufen parallel weiter (werden verworfen), damit iOS die App
  im Hintergrund aktiv hält.
- Routen: `Resources/SimulationRoutes.json` = Liste von Routen (Punkte `[lat, lon, m/s]`, Pause danach)
  und je Betriebsart die Reihenfolge. Erzeugt mit `tools/build_simulation_routes.py`:
  Straßen/Fußwege per OSRM inkl. Segmentdauer, Flughafen-Rollwege per Dijkstra auf dem OSM-Rollweggraphen
  (Bahnen mit Strafgewicht), Start-/Landelauf linear beschleunigt/verzögert.
- Pro Sekunde eine Position; Zeitraffer multipliziert die Strecke je Sekunde. Zeitstempel bleiben echt.
- Der Simulator holt die jeweils nächste Route aus einer Quelle: Deutschland = `GermanyPlanner`,
  Flughafen = `AirportPlanner` (Rückfall ohne Daten: feste Liste aus `modes`).

### Deutschland-Planer (seit 0.8.0)
- Ortsnetz (`germany` in `SimulationRoutes.json`): 26 Orte in drei Regionen – Mainz/Wiesbaden (12),
  Paderborn/Borchen (11), Köln/Bonn (3). Je Region Autorouten zwischen allen Orten (101), Fußwege zwischen
  Orten bis 2,5 km Luftlinie (40), dazu 4 Fernstrecken (Mainz–Paderborn–Köln, Köln–Paderborn,
  Bonn–Mainz). Jede Route ist in beide Richtungen nutzbar (Rückweg = umgekehrte Punktfolge, Tempo je
  Abschnitt mitgenommen); Punkte auf ≥ 25 m (Auto) bzw. ≥ 10 m (Fuß) ausgedünnt, Tempo = Strecke/Fahrzeit.
- Ablauf: 12 % Fernfahrt in die am seltensten besuchte Region (vorher Fahrt zum Startort der Fernstrecke),
  sonst 30 % Spaziergang zu einem nahen, sonst Fahrt zu einem beliebigen Ort der Region – jeweils der
  am seltensten besuchte. Aufenthalt danach 2–15 min (zu Fuß) bzw. 5–30 min (Auto), Fernfahrt 10–30 min.
- Geprüft mit Mac-Testprogramm: 3 000 Abschnitte (≈ 97 Tage Simulationszeit) ohne Sprünge, alle 26 Orte
  angefahren, Zeitanteil Mainz 32 %, Paderborn 47 %, Köln/Bonn 20 %; 15 % Fußwege, 11 % Fernfahrten.

### Flughafen-Planer (seit 0.7.0)
- `Resources/AirportGraph.json`: Wegenetz innerhalb der OSM-Flughafengrenze (Relation 2269304) –
  Knoten `[lat, lon]`, Kanten `[a, b, Maske, Kfz-Tempo m/s]` mit Masken Fuß=1, Fahrzeug=2, Flugzeug=4,
  Treppe=8, Bahn=16; je Verkehrsart nur das größte zusammenhängende Teilnetz (Fuß 75 km, Fahrzeug 94 km,
  Rollwege 35 km) sowie ~100 benannte Ziele (Terminals, Vorfelder, Hallen, Feuerwachen …).
- Abschnittsarten: zu Fuß 42 %, Fahrzeug 36 %, Follow-me auf Rollwegen 10 %, feste Start-/Landefolge 5 %,
  Ausflug 7 %.
- Ziel: Gelände in Zellen ≈ 220 × 210 m; gewählt wird ein Knoten aus einer der am seltensten besuchten
  Zellen (Fußwege höchstens 1,8 km Luftlinie, mindestens 250 m). Weg per Dijkstra nach Fahrzeit
  (Fuß 1,4 m/s, Treppen 0,6 m/s, Kfz nach Straßentyp/`maxspeed`, Follow-me 8 m/s, Bahnen ×4 Strafgewicht),
  persönlicher Tempofaktor je Abschnitt; alle durchfahrenen Zellen zählen als besucht.
- Wechsel der Verkehrsart ohne Sprung: Der Planer merkt sich, womit die Position erreicht wurde. Liegt das
  neue Netz weiter als 300 m entfernt, führt der Abschnitt zuerst mit der bisherigen Art zu einem
  **Umstiegspunkt** (Knoten, an dem ein Knoten des anderen Netzes höchstens 40 m entfernt ist; gewählt nach
  Luftlinie Position → Umstieg → Ziel). Kurze Lücken bis 300 m werden gerade überbrückt.
- Start/Landung: vorher zu Fuß zum Flugzeug am Vorfeld C; danach gilt das Rollwegnetz als aktuelle Art.
  Einziger gewollter Sprung ist der Flug (Startlauf 13L → Landung 31R, echte Pause > 5 min).
- Geprüft mit einem Mac-Testprogramm (Planer + Daten, ohne App): 2 000 Abschnitte in 0,2 s, außer den Flügen
  keine Sprünge > 200 m, keine leeren Abschnitte, Abdeckung aller 217 Zellen nach 300 Abschnitten.
- Ausflüge (`cityTrips` in `SimulationRoutes.json`): erst Weg zum Abfahrtspunkt (Bahnhof zu Fuß bzw.
  Terminal 1 per Auto), dann die vorberechneten Routen. Bahn per BRouter (Profil „rail“) mit Anfahr-/Bremsprofil
  (0,6 m/s², max. 90–100 km/h), Halte als Pausen; in Troisdorf fehlen BRouter 115 m Gleis – mit OSM-Gleisen
  überbrückt. Auto/Fußwege per OSRM.
- Beginnt die nächste Route an anderer Stelle (Landung nach Start, Fußgänger ↔ Flugzeug), bleibt die
  Pause echt und > 5 min, damit `TrackSegments` keine Verbindungslinie zeichnet.
- Messrauschen: Genauigkeit zufällig 4–15 m (Straße) bzw. 3–8 m (Flughafen), Versatz ≈ ⅓ davon.

### Kartenausschnitt (Live-Karte)
- `SettingsStore.mapScale` (`MapScale`: `local`, `km30`, `km100`, `km500`), persistiert und im Backup.
- *Lokal* + echtes GPS: `MapCameraPosition.userLocation` (MapKit folgt selbst).
  *Lokal* + Simulation: Kamera mit 2,5 km (Flughafen) bzw. 4 km Abstand auf die simulierte Position.
  Feste Breiten: `MKCoordinateRegion` mit der Breite in Metern, zentriert auf `lastLocation`.
- Nachführen nur bei `follow == true`; bei festen Breiten erst ab 10 % Versatz (spart Kartenanimationen).
- Verlauf: eigene Einstellung `historyMapScale`; *Lokal* = `MapCameraPosition.automatic` (ganze Spur),
  feste Breiten zentriert auf den Slider-Punkt, Nachführen ab 10 % Versatz.

### Versionierung
- `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` im Xcode-Projekt, gelesen über `AppInfo`.
- Bei jedem Push erhöht, Git-Tag `vX.Y.Z` (siehe README „Versionierung“).

### Übertragung
- **Live:** nach einem neuen Punkt wartet ein Task `liveIntervalSeconds` und sendet dann alle offenen Punkte.
- **Zeitgesteuert:** `nextScheduledRun` = heutige Uhrzeit bzw. morgen, falls heute schon gelaufen.
  Geprüft bei jedem neuen Punkt, beim Aktivieren der App und im BGAppRefresh-Task
  (`io.github.hondamz.gpstracker.upload`, `earliestBeginDate = nextScheduledRun`). iOS garantiert den Zeitpunkt
  nicht exakt – läuft die Aufzeichnung, greift die Prüfung beim nächsten Punkt.
- **Manuell:** nur Button.
- Alle **aktiven** Ziele werden nacheinander bedient; jedes Ziel hat seinen eigenen Rückstand
  (`uploadedAtN == nil`) und Fehlerstatus. Ein fehlerhaftes Ziel blockiert die anderen nicht.
- Gesendet wird in Paketen à 500 Punkten, ältester zuerst; nach 2xx-Antwort wird `uploadedAtN` gesetzt.
  Bei Fehlern bleiben die Punkte offen (nächster Versuch sendet sie erneut → Server sollte über `id` deduplizieren).
- Ein neu aktiviertes Ziel erhält zunächst die komplette Historie; „Rückstand verwerfen“ markiert alle
  Punkte für dieses Ziel als übertragen, „Alle erneut senden“ setzt den Status zurück.
- Der Übertragungsmodus (live/zeitgesteuert/manuell) gilt gemeinsam für alle aktiven Ziele.

### Backup
- Ordner per `fileImporter(.folder)`, gespeichert als Security-Scoped Bookmark.
- Datei `GPSTracker-Backup-YYYYMMDD-HHMMSS.json`: `formatVersion`, `createdAt`, `appVersion`,
  `settings` (ohne Passwort/Ordner), `points`.
- Wiederherstellung fügt Punkte ein; dank `@Attribute(.unique)` auf `id` entstehen keine Duplikate.

### Verteilte Builds (seit 0.9.2)
- Release-Konfiguration des Targets: `EXCLUDED_SOURCE_FILE_NAMES = PrivateDefaults.json`, `PrivateDefaults.shared`
  ist außerhalb von `DEBUG` immer `nil`, Build-Phase `tools/check_release_bundle.sh` prüft das fertige Paket
  (dafür `ENABLE_USER_SCRIPT_SANDBOXING = NO` nur im Target-Release, das Skript braucht Lesezugriff auf das Paket).
- Datenschutz-Manifest `GPSTracker/PrivacyInfo.xcprivacy`. `NSPrivacyCollectedDataTypes` ist leer, weil Standortdaten
  nur lokal liegen und nur an vom Nutzer selbst eingetragene Server gehen; der Entwickler erhält nichts.

### Export/Import von Einstellungen und Serverzielen (seit 0.9.0)
- `Services/SettingsTransfer.swift`: Datei `SettingsExport` (JSON) mit `formatVersion`, `kind` (`settings` |
  `serverTargets`), `exportedAt`, `appVersion`, optional `settings` (`SettingsSnapshot` ohne Ziele) und `targets`
  (je Ziel `id`, `name`, `enabled`, `url`, `account`, optional `password`).
- Speichern per `fileExporter` (`JSONFileDocument`), einzelnes Ziel als Datei `Serverziel <Name>.gpsziel` im
  Temp-Ordner für `MailComposer` (MFMailComposeViewController, MIME `application/vnd.gpstracker.servertarget+json`)
  bzw. `ShareLink`.
- Eigener Dateityp `io.github.hondamz.gpstracker.servertarget` (Endung `.gpsziel`, konform zu `public.json`) als
  `UTExportedTypeDeclarations` + `CFBundleDocumentTypes` (Owner) in `Config/Info.plist`; `ContentView.onOpenURL`
  liest die Datei und zeigt `TargetImportView`.
- `readTargets` liest Export-Dateien und Backups (`settings.targets`); `TargetImportView` schreibt gewählte Ziele per
  `SettingsStore.updateTarget`, Passwort nur wenn vorhanden; Übertragungsstand (`uploadedAtN`) bleibt.

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| iOS 18 als Minimum | `CLServiceSession`, `CLLocationUpdate`-Diagnose, SwiftData `#Index`, neue `Tab`-API |
| `liveUpdates` statt Delegate-API | moderne, offiziell empfohlene API, eingebaute Stillstandserkennung, async/await |
| Berechtigung „Beim Verwenden“ genügt | mit `CLBackgroundActivitySession` läuft die Aufzeichnung im Hintergrund weiter (blaue Statusanzeige); „Immer“ optional |
| SwiftData statt Dateien | Abfragen nach Zeitraum/Upload-Status, `@Query` aktualisiert Karten automatisch |
| Upload-Protokoll `TrackUploader` | Schnittstelle ist noch nicht spezifiziert – später nur neue Implementierung nötig |
| Passwort in Keychain mit `AfterFirstUnlock` | sicher, aber Hintergrund-Upload bei gesperrtem Gerät möglich |
| Feste vier Ziele mit eigenen Feldern `uploadedAt1…4` | einfache, schnelle SwiftData-Abfragen pro Ziel; Anforderung nennt genau drei Ziele |
| Private Werte nicht im Code | Server-Vorbelegung in `Resources/PrivateDefaults.json`, Team-ID in `Config/Local.xcconfig` (beide in `.gitignore`); ermöglicht den bereinigten GitHub-Export (`tools/export_github.sh` mit Sperrliste) |
| ATS-Ausnahme `ts.net` (inkl. Subdomains) | Tailscale verschlüsselt selbst (WireGuard); http zu `*.ts.net` ist daher unkritisch. Tailscale-IPs (100.64/10) lassen sich per ATS nicht freigeben → App warnt |
| `NSAllowsLocalNetworking` | Tests gegen Server im LAN/per IP ohne HTTPS; im Internet HTTPS verwenden |
| Synchronisierter Projektordner | `project.pbxproj` bleibt klein und konfliktarm, kein XcodeGen nötig |
