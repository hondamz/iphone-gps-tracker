# Changelog

Format angelehnt an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Versionen nach SemVer.

## [Unreleased]

## [0.11.2] – 2026-10-31 · Build 18

### Neu
- **Screenshots** der Hauptfunktionen in `docs/funktionen.md` (Bilder in `docs/bilder/`), aufgenommen mit dem
  Release-Build in einem leeren Simulator. Nur Doku, App unverändert.

### Geändert
- `docs/funktionen.md` auf aktuellen Stand gebracht: vier Serverziele, Vorbelegung von Ziel 4 nur in Debug-Builds.


## [0.11.1] – 2026-10-31 · Build 17

### Neu
- **Datenschutzerklärung** `docs/datenschutz.md` für App Store Connect und TestFlight (nur Doku, App unverändert).


## [0.11.0] – 2026-10-30 · Build 16

### Geändert
- **Neue Bundle-ID `io.github.hondamz.gpstracker`** ohne Personennamen, ebenso Hintergrund-Upload, Keychain-Kennung und
  Dateityp `.gpsziel`. Bestehende Installationen gelten als neue App; Umzug per Backup: `docs/bedienung.md`, Abschnitt 6b.
- GitHub-Export: Sperrliste um Personennamen erweitert, Ortsangaben zum Server entfernt.

### Getestet
- Umzug im Simulator: Backup der alten App in die neue eingespielt; 2.046 Punkte, Streckenarten, Übertragungsstand,
  Geräte-ID und Serverziele identisch. Beide Apps laufen nebeneinander.


## [0.10.0] – 2026-10-30 · Build 15

### Neu
- **Privat/geschäftlich:** runder Umschalter auf der Live-Karte direkt unter dem Positionsbutton (Haus/Koffer).
  Jeder neue Punkt speichert die aktuelle Wahl (`tripCategory`), sie bleibt nach einem Neustart erhalten und ist im
  Backup sowie in Einstellungs-Exporten enthalten. Anzeige in Statusleiste und Verlauf.
- Übertragung: `tripCategory` je Punkt. Der Viewer (0.9.0) speichert das Feld und filtert danach.

### Getestet
- Simulator: Umschalten während der Fahrt (Punkte wechseln ab dem Tipp, ältere bleiben unverändert).
- Übertragung an den Viewer: 570 + 1.000 Punkte angenommen, 14 privat, 138 geschäftlich, Rest ohne Angabe.
- Viewer-Oberfläche: Filter liefert 14 / 138 / 536, Summe = 688 Punkte unter „alle“.


## [0.9.2] – 2026-10-30 · Build 14

### Neu
- **Vorbereitung für Tester (TestFlight):** Release-Builds enthalten keine privaten Voreinstellungen mehr – Datei im
  Release ausgeschlossen, Code liest sie nur in Debug-Builds, Build-Phase `tools/check_release_bundle.sh` lässt den
  Build scheitern, falls die Datei, ein konkreter Tailnet-Name oder eine Tailscale-/LAN-Adresse im Paket steht.
- Datenschutz-Manifest `PrivacyInfo.xcprivacy` (UserDefaults, kein Tracking, keine vom Entwickler erhobenen Daten).

### Geändert
- App-Icon ohne Transparenzkanal (Vorgabe von Apple für den Upload).
- Hinweis auf private Voreinstellungen unter „Serverziele“ erscheint nur noch, wenn welche vorhanden sind.

### Getestet
- Release-Build: Paket ohne `PrivateDefaults.json`, mit Manifest; auf frischem Simulator vier leere Serverziele.
- Gegenprobe: erzwungene Datei lässt den Build scheitern; konkrete Adressen werden erkannt, Platzhalter nicht.
- Lokales Geräte-Archiv baut. Im Paket steht nur noch die Team-ID in der Apple-Signatur. Kein Upload erfolgt.


## [0.9.1] – 2026-10-28 · Build 13

### Doku
- `docs/` um Export/Import von Einstellungen und Serverzielen, E-Mail-Versand und Dateityp `.gpsziel` ergänzt
  (Funktionen, Bedienung, Architektur, Anforderungen E-07 bis E-10).

### Getestet (Simulator)
- Import einer gespeicherten `.gpsziel`-Datei über „Serverziele importieren …“ (Dateidialog bietet sie an,
  Auswahl und Übernahme funktionieren).


## [0.9.0] – 2026-10-28 · Build 12

### Neu
- **Einstellungen exportieren** (alle Einstellungen inkl. Serverziele) und **Serverziele exportieren** als JSON;
  Passwörter nur mit Schalter „Passwörter einschließen“ (Warnhinweis: Klartext).
- **Serverziele importieren** mit Auswahl: je Ziel an/aus und Zielplatz (1–4), Hinweis auf das ersetzte Ziel,
  Sperre bei doppelter Platzbelegung. Liest Einstellungs-, Ziel- und Backup-Dateien sowie `.gpsziel`.
- **Einzelnes Ziel per E-Mail senden** (Details eines Ziels → Weitergeben): E-Mail mit `.gpsziel`-Anhang,
  Empfänger gibt der Nutzer ein; Passwort optional. Ohne Mail-Konto: „Teilen …“.
- Eigener Dateityp `.gpsziel` (`io.github.hondamz.gpstracker.servertarget`): Anhang/Datei mit „GPS Tracker“ öffnen →
  Import-Auswahl erscheint direkt.

### Getestet (Simulator)
- Export mit/ohne Passwort, Import mit Platzwahl und Konfliktsperre, Passwort-Übernahme,
  Öffnen einer `.gpsziel`-Datei über das Teilen-Menü. Nicht testbar im Simulator: Mail-Fenster (kein Mail-Konto).


## [0.8.3] – 2026-10-28 · Build 11

### Geändert
- Scheme-Datei im Format von Xcode 27.1 übernommen (von Xcode beim Öffnen neu geschrieben, inhaltlich gleich).


## [0.8.2] – 2026-10-28 · Build 10

### Geändert
- GitHub-Export: Exportskript selbst wird nicht mitexportiert; Kontopfade, lokale Ordnerpfade und
  Beispielnamen werden ersetzt und stehen in der Sperrliste; erlaubter allgemeiner Adressbereich
  `100.64.0.0/10` löst keinen Fehlalarm mehr aus.


## [0.8.1] – 2026-10-28 · Build 9

### Geändert
- **Private Voreinstellungen aus dem Code gelöst:** Vorbelegung von Ziel 4 (Adresse, Benutzer) kommt aus
  `GPSTracker/Resources/PrivateDefaults.json`, die Apple-Team-ID aus `Config/Local.xcconfig` – beide nicht im
  Git, Vorlagen `*.example.*`. Ohne die Dateien startet die App ohne Vorbelegung.
- Hinweis- und Fehlertexte nennen keine konkrete Tailscale-Adresse mehr (`<rechner>.<tailnet>.ts.net`).

### Neu
- `tools/export_github.sh`: bereinigter Export nach GitHub (`hondamz/iphone-gps-tracker`, privat) mit eigener
  Historie, Platzhaltern in der Doku und Sperrliste, die bei privaten Angaben abbricht.


## [0.8.0] – 2026-10-28 · Build 8

### Neu
- **Deutschland-Simulation zufällig:** statt der festen Schleife Mainz → Paderborn → Köln/Bonn → Mainz wählt der
  neue `GermanyPlanner` endlos Fahrten und Spaziergänge zwischen 26 Orten/Wiesbaden, Paderborn/Borchen
  und Köln/Bonn – bevorzugt zu selten besuchten Orten – und gelegentlich (12 %) eine Fernfahrt in eine andere
  Region. Banner zeigt Start und Ziel („Fahrt: Mainz Hbf → Mainz-Gonsenheim“).
- Ortsnetz im Generator: 141 Stadt-/Fußrouten und 4 Fernstrecken (OSRM), Routen in beide Richtungen nutzbar.

### Geändert
- Die vier festen Deutschland-Routen entfallen (durch das Ortsnetz ersetzt).
- Generator: Endpunkt einer Route wird beim Zusammenfassen naher Punkte nicht mehr verschluckt.

### Getestet
- Mac-Testprogramm: 3 000 Abschnitte (≈ 97 Tage) ohne Sprünge, alle 26 Orte und alle Regionen angefahren.
- Simulator (60×): zufällige Abschnitte, Banner mit Start/Ziel.


## [0.7.0] – 2026-10-28 · Build 7

### Neu
- **Flughafen-Simulation mit zufälligen Strecken:** Statt einer festen Schleife erzeugt der neue
  `AirportPlanner` endlos Abschnitte im OSM-Wegenetz des Flughafens – zu Fuß, mit dem Fahrzeug und als
  Follow-me-Fahrzeug auf den Rollwegen, gelegentlich Start/Landung. Ziele bevorzugt in den bisher am
  seltensten besuchten Bereichen, damit mit der Zeit das ganze Gelände vorkommt. Banner zeigt das Ziel
  („Zu Fuß → Terminal 2“, „Fahrt → DHL Frachthalle“).
- **Ausflüge nach Köln und Bonn** (ca. 7 % der Abschnitte): Köln per Bahn (Messe/Deutz → Hbf) oder Auto (Dom),
  Bonn per Bahn (S-Bahn bis Troisdorf, Umstieg, RE über Menden nach Bonn-Beuel) oder Auto (Markt),
  jeweils mit Stadtrundgang und Rückfahrt. Bahn mit Anfahr-/Bremsprofil und Halten.
- Neue Datei `Resources/AirportGraph.json` (Wegenetz, ~200 KB); Generator erweitert (BRouter für Bahn).
- Wechsel der Verkehrsart über Umstiegspunkte (z. B. Fahrt zum Parkplatz, dann zu Fuß) – keine Sprünge;
  vor Start/Landung Fußweg zum Flugzeug.

### Getestet
- Mac-Testprogramm mit 2 000 Abschnitten: alle Abschnittsarten und alle vier Ausflüge kommen vor, außer dem
  Flug keine Sprünge > 200 m, alle 217 Zellen des Wegenetzes nach 300 Abschnitten besucht (96 % nach 100).
- Simulator (60×): zufällige Abschnitte mit Zielnamen im Banner, Spur folgt den Wegen.


### Repository
- privater Git-Server-Schutzregel für `main` (28.10.2026): Force-Push und Löschen werden vom Server abgelehnt.
  CLAUDE.md: verbindliche Regeln für parallele Sitzungen.

### Doku
- `docs/server-schnittstelle.md`: Der Positions-Tracking-Viewer (ab 0.3.0) verlangt immer Benutzer/Passwort;
  die Zugänge werden dort unter *Einstellungen* gepflegt. Neuer Status **403** = Benutzer deaktiviert
  (Punkte bleiben offen). Offener Punkt: `detail`-Text des Servers statt „HTTP 401/403“ anzeigen.

## [0.6.0] – 2026-10-10 · Build 6

### Neu
- **Simulationsflag:** Jeder übertragene Punkt enthält `simulated` (`true` bei Punkten aus einer
  Simulations-Betriebsart, sonst `false`) – der Viewer unterscheidet damit Simulations- und Echtdaten.
- **Server 4** „Viewer (Tailscale)“: vorbelegt mit `http://<rechner>.<tailnet>.ts.net:8085/api/v1/ingest`,
  Benutzer `<benutzer>`, ausgeschaltet bis das Passwort eingetragen ist. Eigener Übertragungsstatus
  (`uploadedAt4`). Wird beim Update automatisch ergänzt; Knopf zum Wiederherstellen der Adresse.
- **Tailscale-Namen per http erlaubt:** ATS-Ausnahme für `*.ts.net` (die Verbindung ist durch Tailscale
  verschlüsselt). Vorher blockierte iOS die Übertragung mit „App Transport Security policy requires …“.

### Behoben / verbessert
- Verständliche deutsche Fehlermeldung, wenn iOS unverschlüsseltes http blockiert, und orange Warnung
  schon bei der Eingabe einer Tailscale-IP (100.64.0.0/10), die iOS nicht als lokales Netz zulässt.

### Getestet (Simulator)
- Update von 0.5.0: Ziel 4 erscheint vorbelegt und aus; bestehende Ziele/Rückstände bleiben erhalten.
- Übertragung: lokaler Empfänger erhält `formatVersion` 2, App 0.6.0 (6), 407 Punkte mit `simulated: true`;
  Tailscale-IP → neue ATS-Meldung; Tailscale-Name → Server erreicht (401, weil ohne Passwort).

### Server (positions-tracking-viewer 0.5.0)
- Spalte `points.simulated`, gesetzt aus `simulated` oder `source`; Altbestand rückwirkend gekennzeichnet.

## [0.5.0] – 2026-10-04 · Build 5

### Neu
- **Kartenausschnitt im Verlauf**: Leiste über der Karte mit *Lokal* (ganze Spur einpassen, wie bisher)
  und *30 / 100 / 500 km* (feste Breite, zentriert auf den Slider-Punkt; folgt dem Slider ab 10 % Versatz).
  Eigene, gespeicherte Einstellung; Knopf zum Neuzentrieren.
- Server-Paket enthält zusätzlich `deviceName` (= Tracker-Name) und `deviceType` = `iPhone` –
  die Feldnamen des Positions-Tracking-Viewers.
- Schnittstellendoku mit dem Server abgestimmt (`docs/server-schnittstelle.md`), Test-Server eingetragen.

### Server (positions-tracking-viewer 0.2.0)
- Nimmt jetzt `formatVersion` 2 an (vorher HTTP 400 → App ab 0.3.0 konnte nicht liefern),
  speichert `appVersion` und `source` je Punkt sowie die App-Version je Tracker.

### Getestet (Simulator)
- Verlauf: Lokal ↔ 30 km, Ausschnitt folgt dem Slider.
- Test-Server `http://192.168.x.y:8085/api/v1/ingest` als Ziel 1 (Benutzer `<benutzer>`) eingetragen;
  ohne Passwort antwortet der Server 401 – Passwort muss noch eingetragen werden.

## [0.4.0] – 2026-10-04 · Build 4

### Neu
- **Kartenausschnitt der Live-Karte wählbar**: Leiste oben mit *Lokal* (automatisch auf die Umgebung
  des Trackers, wie bisher), *30 km*, *100 km*, *500 km* (Breite des Ausschnitts, zentriert auf den Tracker).
  Die Wahl wird gespeichert (auch im Backup).
- Schalter **Folgen** (für echtes GPS und Simulation): an = Karte führt nach, aus = Karte bleibt stehen.
  Bei festen Ausschnitten wird erst nachgeführt, wenn der Tracker mehr als 10 % der Breite aus der Mitte ist.

### Geändert
- Der bisherige Folgen-Knopf im Simulationsbanner ist in die neue Leiste gewandert.

### Getestet (Simulator iPhone 17 Pro, iOS 26.5, Deutschland-Simulation)
- Umschalten Lokal → 100 km → 500 km → Lokal; Ausschnitt zentriert auf den Tracker, Breiten plausibel
  (100 km ≈ Koblenz–Frankfurt, 500 km ≈ Amsterdam–Nürnberg).
- Auswahl bleibt nach App-Neustart erhalten; „Folgen aus“ lässt die Karte stehen.

## [0.3.0] – 2026-10-04 · Build 3

### Neu
- **Tracker-Name** in den Einstellungen (Vorschlag: Name des iPhones); wird mit jeder Übertragung
  als `trackerName` gesendet und im Backup gesichert.
- **Software-Version je Push**: Version + Build werden bei jedem Push erhöht und getaggt
  (nachträglich `v0.1.0`, `v0.2.0`). Jeder GPS-Punkt speichert seine `appVersion`;
  Übertragungen enthalten `appVersion` und `appBuild` (Paket) sowie `appVersion` je Punkt.
- **Herkunft je Punkt** (`source`: `gps` oder `simulation-<betriebsart>`), gespeichert und übertragen.
- **Simulations-Betriebsarten** (Einstellungen → Simulation) mit Zeitraffer 1×/5×/20×/60×:
  - *Mainz, Paderborn & Deutschland*: Stadtfahrt Mainz (17 km), A3/A45/A44 nach Paderborn (284 km),
    Paderborn und Borchen (34 km), zurück über Köln/Bonn nach Mainz (353 km) – auf echten Straßen
    mit realistischen Geschwindigkeiten je Abschnitt.
  - *Flughafen Köln/Bonn*: nur auf dem Gelände – Fußweg Bahnhof ↔ Terminal 1/2, Rollen vom Vorfeld C
    zur Bahn 13L, Startlauf, Landung auf 31R, Rollen zum Frachtvorfeld W und zurück.
  - Live-Karte mit lila Simulationsmarker, Banner mit Routenname und „Folgen“-Schalter.
- Routen-Generator `tools/build_simulation_routes.py` (OSRM + OpenStreetMap-Rollweggraph).

### Geändert
- Server-Paket `formatVersion` 2, Backup `formatVersion` 2 (ältere Backups bleiben einlesbar).
- Versionsanzeige „0.3.0 (3)“ in Einstellungen und GPS-Daten.

### Getestet (Simulator iPhone 17 Pro, iOS 26.5)
- Flughafen-Simulation (5× und 60×): Fußweg, Rollwege, Bahnen; Karte folgt, Banner zeigt Route.
- Deutschland-Simulation (60×): Wechsel der Betriebsart im laufenden Betrieb-Runde, Autobahn.
- Übertragung an Test-Server: Paket mit `trackerName`, `appVersion` 0.3.0, `appBuild` 3,
  Punkte mit `appVersion` und `source`.
- Migration: vorhandene Punkte erhalten `source = gps`, `appVersion` leer („vor 0.3.0“).

## [0.2.0] – 2026-10-04

### Neu
- **Drei Serverziele** statt eines Servers: je Name, Adresse, Benutzer, Passwort (Keychain) und
  Schalter „Aktiv“. Alle aktiven Ziele erhalten dieselben Daten.
- Übertragungsstatus **pro Ziel** (eigener Rückstand, eigene Fehlermeldung, letzte Übertragung);
  ein ausgefallenes Ziel blockiert die anderen nicht.
- Detailansicht je Ziel mit „Jetzt an dieses Ziel übertragen“, „Rückstand verwerfen“ und
  „Alle Punkte erneut senden“.
- GPS-Daten-Tab zeigt offene Punkte je aktivem Ziel.
- Spur wird bei Aufzeichnungspausen > 5 min in getrennte Linien geteilt (Live und Verlauf);
  die Streckenangabe zählt Sprünge zwischen Fahrten nicht mehr mit.

### Geändert
- Datenmodell: `uploadedAt` → `uploadedAt1/2/3` (automatische Migration, bisheriger Status gilt für Ziel 1).
- Einstellungen: bisheriger Server wird beim ersten Start automatisch zu „Server 1“ (aktiv).
- Server-Nutzdaten enthalten keine app-internen Übertragungsfelder mehr.
- Backup enthält alle drei Ziele (ohne Passwörter); Backups aus v0.1 bleiben einlesbar.

### Behoben
- Ordnerwahl für Backup und „Backup wiederherstellen“ hatten keine Wirkung
  (Dialog-Modus wurde vor dem Ergebnis-Handler zurückgesetzt).
- GPS-Daten: „Messzeit“ und „Alter“ standen in einer Zeile; „–/s“ bei unbekannter Geschwindigkeitsgenauigkeit.
- Bestätigungsdialoge erscheinen jetzt am auslösenden Button.
- „Rückstand verwerfen“ entfernt auch die alte Fehlermeldung des Ziels.

### Getestet (Simulator iPhone 17 Pro, iOS 26.5)
- Alle vier Tabs inkl. Zeit-Slider, eigenem Zeitraum, Serverziel-Details und Dialogen.
- Migration einer v0.1-Datenbank (Status bleibt bei Ziel 1) und der v0.1-Einstellungen.
- Drei lokale Test-Server: Ziel 1 und 2 HTTP 200, Ziel 3 HTTP 500 – Ziele 1/2 laufen unabhängig weiter,
  Ziel 3 zeigt Fehler und behält seinen Rückstand; neu aktiviertes Ziel erhält die komplette Historie.
- Backup in „Auf meinem iPhone“, Löschen aller Daten, Wiederherstellen (223 Punkte, Status je Ziel erhalten),
  Einlesen eines Backups im v0.1-Format.

## [0.1.0] – 2026-10-04

### Neu
- Projekt angelegt (lokal, privater Git-Server `iphone-gps-tracker`).
- Xcode-Projekt (iOS 18+, Swift 6, SwiftUI, SwiftData, MapKit) mit vier Tabs.
- Positionserfassung über `CLLocationUpdate.liveUpdates` mit `CLBackgroundActivitySession`
  (Hintergrundbetrieb), Speicherung nur bei Bewegung (Mindestabstand + Genauigkeitsfilter).
- Live-Karte mit Position, Genauigkeitskreis und heutigem Weg als Linie; Start/Stopp.
- Verlauf mit Zeitraumwahl (1 Std./24 Std./7/30 Tage/eigener) und Zeit-Slider.
- GPS-Datenansicht: Koordinaten, Höhe, Genauigkeiten, Geschwindigkeit, Kurs, Status, Speicher.
- Einstellungen: Aufzeichnungsfilter, Server (URL, Benutzer, Passwort in Keychain),
  Übertragungsmodus live/zeitgesteuert/manuell, Standard-Zeitraum, Backup/Wiederherstellung, Daten löschen.
- Vorläufige Server-Übertragung: JSON per HTTP POST, Basic Auth, Pakete à 500 Punkte.
- Backup als JSON in frei wählbaren Ordner der Dateien-App.

### Getestet
- Build ohne Warnungen (Xcode 27.0, iOS-27-SDK); Laufzeittest im Simulator iPhone 17 Pro mit iOS 26.5.
- Simulierte Fahrt durch Mainz: Punkte werden gespeichert, Linie auf der Live-Karte.
- Live-Übertragung gegen lokalen Test-Server: Rückstand in einem Paket, danach alle ~6 s, HTTP 200.
