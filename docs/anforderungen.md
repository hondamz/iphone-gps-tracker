# Anforderungen

Stand: 30.10.2026 (v0.10.0) · Quelle: Projektauftrag (04.10.2026), Erweiterungen Serverziele sowie Tracker-Name/Version/Simulation (04.10.2026)

Status: ✅ umgesetzt · 🟡 teilweise/vorläufig · ⬜ offen

## Erfassung

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| A-01 | GPS-Daten über die offizielle Apple-API erfassen | ✅ | CoreLocation `CLLocationUpdate.liveUpdates` |
| A-02 | Protokollierung nur bei Bewegung | ✅ | Mindestabstand (Standard 10 m) zum letzten Punkt; iOS pausiert bei Stillstand |
| A-03 | Aufzeichnung auch im Hintergrund | ✅ | `CLBackgroundActivitySession`, `UIBackgroundModes: location` – auf Gerät noch zu testen |
| A-04 | Ungenaue Messungen verwerfen | ✅ | Max. Ungenauigkeit (Standard 50 m) einstellbar |
| A-05 | Daten lokal protokollieren | ✅ | SwiftData-Datenbank im App-Container |

## Darstellung

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| D-01 | Live-Darstellung der Position auf einer Karte | ✅ | Tab „Live“, MapKit, folgt der Position |
| D-02 | Historische Bewegung über konfigurierbaren Zeitraum | ✅ | Tab „Verlauf“, Presets + eigener Zeitraum, Standard in Einstellungen |
| D-03 | Zeit-Slider im Verlauf | ✅ | Slider über die Zeitachse, Marker + Zeit/Geschwindigkeit/Strecke |
| D-04 | Bewegung als Linie auf der Karte | ✅ | `MapPolyline` (Live: heutiger Tag; Verlauf: Zeitraum, bis Slider-Zeit hervorgehoben) |
| D-05 | Live-Anzeige der GPS-Daten | ✅ | Tab „GPS-Daten“ |
| D-07 | Kartenausschnitt wählbar: lokal automatisch oder 30 / 100 / 500 km | ✅ | Leiste auf der Live-Karte, gespeichert (v0.4.0) |
| D-08 | Kartenausschnitt auch im Verlauf | ✅ | Lokal = ganze Spur, sonst feste Breite um den Slider-Punkt (v0.5.0) |
| D-09 | Über der Karte unter dem Positionsbutton einstellen, ob die Strecke privat oder geschäftlich ist | ✅ | Runder Umschalter, gilt je Punkt ab dem Umschalten (v0.10.0) |
| D-06 | Anzeige der Messgenauigkeit | ✅ | Horizontal/vertikal/Geschwindigkeit/Kurs, Farbbewertung, Genauigkeitskreis auf der Karte |

## Übertragung

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| U-01 | Übertragung an eine Server-App im Internet | ✅ | abgestimmt mit dem Positions-Tracking-Viewer (→ [server-schnittstelle.md](server-schnittstelle.md)) |
| U-02 | Modus „live“ (nahezu Echtzeit) | ✅ | Sammelintervall 1–300 s (Standard 10 s) |
| U-03 | Modus „zu konfigurierbarem Zeitpunkt“ | ✅ | tägliche Uhrzeit; Ausführung per BGAppRefresh, bei App-Aktivierung oder neuem Punkt |
| U-04 | Automatik aus, nur manuell | ✅ | Modus „Nur manuell“ + Button „Jetzt übertragen“ (in allen Modi) |
| U-05 | Keine Daten verlieren bei Netzausfall | ✅ | Punkte bleiben „nicht übertragen“ markiert, nächster Lauf sendet sie nach |
| U-06 | Drei verschiedene Serverziele konfigurierbar | ✅ | Ziele 1–3 mit Name, Adresse, Benutzer, Passwort (v0.2.0) |
| U-07 | Jedes Serverziel einzeln an-/abschaltbar | ✅ | Schalter in der Zielliste und in der Detailansicht |
| U-09 | Viertes Ziel mit Viewer über Tailscale vorkonfiguriert | ✅ | Ziel 4 „Viewer (Tailscale)“ (v0.6.0) |
| U-10 | Übertragung über Tailscale | ✅ | ATS-Ausnahme `*.ts.net`; Tailscale-IPs werden von iOS blockiert → Warnung |
| U-11 | Streckenart in den Übertragungsdaten, im Server filterbar | ✅ | `tripCategory` je Punkt; Viewer 0.9.0: Filter „Streckenart“ |
| U-08 | Alle aktiven Ziele erhalten dieselben Daten | ✅ | Übertragungsstatus pro Punkt und Ziel; Ziele unabhängig voneinander |

## Tracker-Identität & Versionierung

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| T-01 | Name des Trackers einstellbar | ✅ | Einstellungen → Tracker (v0.3.0) |
| T-02 | Vorschlag = Name des iPhones | 🟡 | `UIDevice.name`; iOS liefert ohne Apple-Sonderfreigabe nur den Modellnamen (z. B. „iPhone“) |
| T-03 | Name in den Übertragungsdaten | ✅ | `trackerName` im Paket |
| T-04 | Software-Version für jede Änderung (je Push) | ✅ | SemVer + Build, Git-Tag, CHANGELOG |
| T-05 | Version zu den GPS-Daten protokollieren | ✅ | `appVersion` je Punkt (ältere Punkte: leer) |
| T-06 | Version an die Server übertragen | ✅ | `appVersion`, `appBuild` im Paket, `appVersion` je Punkt |

## Simulation

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| S-01 | Simulation einstellbar | ✅ | Einstellungen → Simulation, Betriebsart + Zeitraffer |
| S-02 | Fahrten, Paderborn und Deutschland | ✅ | zufällig im Ortsnetz: 26 Orte in 3 Regionen, 141 Stadt-/Fußrouten, 4 Fernstrecken (OSRM), seit v0.8.0 |
| S-03 | Bewegung nur im Bereich Flughafen Köln/Bonn | ✅ | Fußweg, Rollwege (OSM-Graph), Bahnen 13L/31R |
| S-04 | Simulierte Daten erkennbar | ✅ | `source = simulation-…` je Punkt, Banner/Marker in der App |
| S-06 | Flughafen: zufällige Strecken zu Fuß und gefahren, alle Bereiche des Geländes | ✅ | Wegenetz aus OSM (Fuß 75 km, Fahrzeug 94 km, Rollwege 35 km), Ziel bevorzugt in selten besuchten Zellen (v0.7.0) |
| S-07 | Flughafen: gelegentlich Ausflug per Auto oder Bahn nach Köln- oder Bonn-Stadt und zurück | ✅ | 4 Ausflüge (Köln/Bonn × Auto/Bahn) mit Stadtrundgang, Anteil ca. 7 % (v0.7.0) |
| S-05 | Simulationsflag in den Übertragungsdaten | ✅ | `simulated: true/false` je Punkt, Viewer speichert es in `points.simulated` (v0.6.0) |

## Verteilung an Tester

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| V-01 | App anderen zum Test bereitstellen, ohne private Daten | 🟡 | Release-Build frei von privaten Voreinstellungen, Build-Sperre, Manifest, Icon (v0.9.2); App-Eintrag und Upload stehen aus |
| V-02 | Tester entscheiden selbst über einen eigenen Server | ✅ | Release startet mit leeren Serverzielen, Eintrag frei konfigurierbar |

## Einstellungen & Backup

| ID | Anforderung | Status | Umsetzung |
|---|---|---|---|
| E-01 | Account für den Server | ✅ | Benutzer + Passwort je Ziel (Passwort in der Keychain) |
| E-02 | Zieladresse des Servers | ✅ | http(s)-URL je Ziel mit Prüfung |
| E-03 | Backup der Einstellungen | ✅ | JSON-Backup (ohne Passwort) |
| E-04 | Backup der historischen GPS-Daten | ✅ | im selben JSON-Backup |
| E-05 | Speicherziel im Dateisystem konfigurierbar | ✅ | Ordnerwahl über Dateien-App (iCloud, lokal, SMB, …), dauerhaft gemerkt |
| E-06 | Wiederherstellung aus Backup | ✅ | Zusammenführung über Punkt-ID, Einstellungen optional |
| E-07 | Sicherung (Export) der App-Einstellungen inkl. Serverziele | ✅ | „Einstellungen exportieren …“, Passwörter optional (v0.9.0) |
| E-08 | Serverziele exportieren und importieren, beim Import Auswahl der Ziele | ✅ | Auswahl je Ziel + Zielplatz, Konfliktsperre (v0.9.0) |
| E-09 | Einzelnes Serverziel per E-Mail versenden (Empfänger frei) | ✅ | Mail mit `.gpsziel`-Anhang, Fallback Teilen-Menü (v0.9.0) |
| E-10 | Empfangenes Serverziel aus Datei importieren | ✅ | Öffnen mit „GPS Tracker“ oder über „Serverziele importieren“ (v0.9.0) |

## Projekt

| ID | Anforderung | Status |
|---|---|---|
| P-01 | Neues Git-Repository | ✅ privater Git-Server `iphone-gps-tracker` |
| P-02 | Eigener Ordner im lokalen Entwicklungsordner | ✅ `iphone-gps-tracker` |
| P-03 | Anforderungen, Architektur, Funktionen, Anwendung und Änderungen dokumentieren und beide Orte aktuell halten | ✅ `docs/`, `CHANGELOG.md`, jede Änderung wird committet und gepusht |

## Offen / Ideen

- ⬜ HTTP 400 vom Server: Paket nicht endlos wiederholen
- ⬜ Test auf echtem Gerät: Hintergrund über Stunden, Akkuverbrauch, Neustart nach Beenden durch iOS
- ⬜ GPX-/CSV-Export
- ⬜ Automatisches, regelmäßiges Backup
- ⬜ Aufzeichnungsprofile (zu Fuß / Fahrrad / Auto) → `LiveConfiguration`
- ⬜ Aufbewahrungsfrist / automatisches Löschen übertragener Punkte
- ⬜ Übertragungsmodus pro Ziel (derzeit gilt ein Modus für alle aktiven Ziele)
- ⬜ Echten Gerätenamen als Vorschlag (Entitlement `user-assigned-device-name` bei Apple beantragen)
- ✅ Deutschland-Simulation zufällig (v0.8.0)
