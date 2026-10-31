# iPhone GPS-Tracker

iOS-App, die die Position über die offiziellen Apple-APIs (CoreLocation) bei Bewegung protokolliert,
live und historisch auf einer Karte darstellt, lokal speichert und an bis zu vier Serverziele überträgt
(live, zeitgesteuert oder manuell; jedes Ziel einzeln an-/abschaltbar). Für Tests gibt es zwei
Simulations-Betriebsarten (Mainz/Paderborn/Deutschland und Flughafen Köln/Bonn).

| | |
|---|---|
| **Status** | v0.11.1 (Build 17) – Datenschutzerklärung ergänzt; Build 0.11.0 (16) in TestFlight hochgeladen (31.10.2026) |
| **Plattform** | iPhone, iOS 18+ · Swift 6 · SwiftUI · SwiftData · MapKit |
| **Repository** | `<privates Git-Repo>` (privater Git-Server, privat) |
| **Lokaler Ordner** | `iphone-gps-tracker` (Git-Arbeitskopie, Synology Drive) |

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [docs/anforderungen.md](docs/anforderungen.md) | Anforderungen mit IDs und Umsetzungsstand |
| [docs/architektur.md](docs/architektur.md) | Komponenten, Datenmodell, Abläufe, Entscheidungen |
| [docs/funktionen.md](docs/funktionen.md) | Funktionsbeschreibung je Bildschirm/Dienst |
| [docs/bedienung.md](docs/bedienung.md) | Anwendung: Einrichtung, Aufzeichnung, Übertragung, Backup |
| [docs/server-schnittstelle.md](docs/server-schnittstelle.md) | Server-Schnittstelle, abgestimmt mit dem [Positions-Tracking-Viewer](positions-tracking-viewer) |
| [docs/datenschutz.md](docs/datenschutz.md) | Datenschutzerklärung (öffentlich, verlinkt in App Store Connect) |
| [CHANGELOG.md](CHANGELOG.md) | Änderungen je Version |

## Bauen & Starten

Voraussetzung: Xcode 27 (getestet mit 27.0, iOS-27-SDK). Projekt öffnen:

```bash
open GPSTracker.xcodeproj
```

- Für ein echtes iPhone die eigene Apple-Team-ID in `Config/Local.xcconfig` eintragen (Vorlage
  `Config/Local.example.xcconfig`, nicht im Git). Wird das Team in Xcode unter *Signing & Capabilities*
  gewählt, schreibt Xcode es ins Projekt – dann vor dem Commit wieder entfernen.
- Private Voreinstellungen (Server 4 mit eigener Adresse/Benutzer): `Config/PrivateDefaults.example.json`
  nach `GPSTracker/Resources/PrivateDefaults.json` kopieren und anpassen (nicht im Git). Ohne die Datei
  startet die App ohne Vorbelegung.
- Bundle-ID: `io.github.hondamz.gpstracker`.
- Simulator: *Features → Location* (z. B. „Freeway Drive“) simuliert eine Fahrt.

Build auf der Kommandozeile (ohne `xcode-select` umzustellen):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project GPSTracker.xcodeproj -scheme GPSTracker -destination 'generic/platform=iOS Simulator' build
```

## Versionierung

Jeder Push mit Änderungen an der App bekommt eine eigene Software-Version:

- `MARKETING_VERSION` (SemVer): Minor bei neuen Funktionen, Patch bei reinen Fehlerbehebungen.
- `CURRENT_PROJECT_VERSION` (Build): bei jedem Push um 1 erhöht.
- Git-Tag `vX.Y.Z` auf den Commit, Eintrag in [CHANGELOG.md](CHANGELOG.md).
- Die Version wird zu jedem GPS-Punkt gespeichert (`appVersion`) und mit jeder Übertragung gesendet
  (`appVersion`, `appBuild` im Paket, `appVersion` je Punkt).

| Version | Build | Tag | Inhalt |
|---|---|---|---|
| 0.1.0 | 1 | `v0.1.0` | Projektstart |
| 0.2.0 | 1¹ | `v0.2.0` | Drei Serverziele |
| 0.3.0 | 3 | `v0.3.0` | Tracker-Name, Versionierung, Simulation |
| 0.4.0 | 4 | `v0.4.0` | Kartenausschnitt Lokal / 30 / 100 / 500 km |
| 0.5.0 | 5 | `v0.5.0` | Kartenausschnitt im Verlauf, `deviceName`/`deviceType`, Test-Server |
| 0.6.0 | 6 | `v0.6.0` | Simulationsflag, Server 4 (Viewer über Tailscale), ATS-Freigabe `*.ts.net` |
| 0.7.0 | 7 | `v0.7.0` | Flughafen-Simulation: zufällige Strecken übers ganze Gelände, Ausflüge Köln/Bonn |
| 0.8.0 | 8 | `v0.8.0` | Deutschland-Simulation zufällig im Ortsnetz Mainz/Paderborn/Köln-Bonn |
| 0.8.1 | 9 | `v0.8.1` | Private Voreinstellungen/Team-ID aus dem Code gelöst, GitHub-Export-Skript |
| 0.8.2 | 10 | `v0.8.2` | GitHub-Export verfeinert (Sperrliste, Platzhalter) |
| 0.8.3 | 11 | `v0.8.3` | Scheme-Datei im Xcode-27.1-Format |
| 0.9.0 | 12 | `v0.9.0` | Export/Import Einstellungen & Serverziele, Ziel per E-Mail, Dateityp .gpsziel |
| 0.9.1 | 13 | `v0.9.1` | Doku zu Export/Import und E-Mail-Versand |
| 0.9.2 | 14 | `v0.9.2` | Release ohne private Daten mit Build-Sperre, Datenschutz-Manifest, Icon ohne Transparenz |
| 0.10.0 | 15 | `v0.10.0` | Umschalter privat/geschäftlich, Feld `tripCategory` in Übertragung und Backup |
| 0.11.0 | 16 | `v0.11.0` | Neue Bundle-ID `io.github.hondamz.gpstracker` |
| 0.11.1 | 17 | `v0.11.1` | Datenschutzerklärung `docs/datenschutz.md` (nur Doku) |

¹ Build-Nummer wurde vor v0.3.0 noch nicht hochgezählt.

## Test-Builds (TestFlight)

Verteilt wird der Release-Build (Xcode: *Product → Archive*, danach *Distribute App → TestFlight*). Er enthält
keine privaten Voreinstellungen, Tester starten mit vier leeren Serverzielen und können selbst einen Server eintragen:

- `PrivateDefaults.json` ist in der Release-Konfiguration ausgeschlossen (`EXCLUDED_SOURCE_FILE_NAMES`), der Code
  liest sie nur in Debug-Builds. Vom iPhone per Xcode gestartete Debug-Builds behalten die Vorbelegung.
- Die Build-Phase `tools/check_release_bundle.sh` lässt jeden Release-Build scheitern, wenn die Datei, ein konkreter
  Tailnet-Name oder eine Tailscale-/LAN-Adresse im App-Paket steht.
- `GPSTracker/PrivacyInfo.xcprivacy` (Datenschutz-Manifest): kein Tracking, keine vom Entwickler erhobenen Daten,
  UserDefaults mit Grund `CA92.1`. Das App-Icon hat keinen Transparenzkanal (Vorgabe von Apple).

Datenschutzerklärung für App Store Connect:
<https://github.com/hondamz/iphone-gps-tracker/blob/main/docs/datenschutz.md>. Sie liegt in `docs/datenschutz.md` und
muss angepasst werden, wenn sich der Umgang der App mit Daten ändert.

## GitHub-Export

Hauptrepo ist der private Git-Server. Auf GitHub (`hondamz/iphone-gps-tracker`) liegt ein
bereinigter Stand mit eigener Historie:

```bash
tools/export_github.sh --push
```

Das Skript nimmt den gepushten Stand von `main`, lässt interne Dateien weg (`CLAUDE.md`, private Dateien sind
ohnehin nicht versioniert), ersetzt Adressen/Benutzernamen in der Doku durch Platzhalter und bricht ab, sobald
die Sperrliste (Tailscale-Namen/-IPs, LAN-Adressen, Server-/Benutzernamen, Team-ID, E-Mail) einen Treffer
findet. Commits auf GitHub laufen unter der GitHub-noreply-Adresse. Ohne `--push` nur bauen und prüfen
(Ergebnis in `build/github-export`).

## Projektstruktur

```
GPSTracker.xcodeproj      Xcode-Projekt (Ordner GPSTracker/ wird automatisch synchronisiert)
Config/Info.plist         Hintergrundmodi, BGTask-ID, ATS (lokales Netz), Dateifreigabe
Config/Base.xcconfig      bindet die private Config/Local.xcconfig ein (Team-ID); Vorlagen *.example.*
GPSTracker/
  App/                    App-Einstieg, Tab-Struktur
  Model/                  SwiftData-Modell TrackPoint + Austauschformat TrackPointRecord
  Services/               LocationTracker, UploadService (pro Ziel), TrackUploader, BackupService,
                          SettingsStore, KeychainStore
  Views/                  Live-Karte, Verlauf, GPS-Daten, Einstellungen, Serverziel-Details
  Support/                Formatierung, Genauigkeitsbewertung, Segmentierung der Spur
  Resources/              SimulationRoutes.json (Routen, Ausflüge), AirportGraph.json (Flughafen-Wegenetz)
tools/                    build_simulation_routes.py (Routen/Wegenetz aus OSM/OSRM/BRouter),
                          export_github.sh (bereinigter Export nach GitHub)
docs/                     Projektdokumentation
```

Neue Swift-Dateien einfach im Ordner `GPSTracker/` anlegen – Xcode nimmt sie automatisch ins Target auf.

## Offene Punkte

- Bei HTTP 400 nicht endlos wiederholen (Server-Empfehlung)
- Test auf echtem iPhone (Hintergrundbetrieb, Akkuverbrauch, Upload bei gesperrtem Gerät)
- Ideen: GPX-Export, automatisches Backup, Aufzeichnungsprofil (Fuß/Rad/Auto), Unit-Tests

Weitere Details siehe [docs/anforderungen.md](docs/anforderungen.md).

---

*Öffentlicher Export (Version 0.11.1). Private Voreinstellungen: `Config/PrivateDefaults.example.json` nach
`GPSTracker/Resources/PrivateDefaults.json` kopieren, Signatur: `Config/Local.example.xcconfig` nach
`Config/Local.xcconfig`.*
