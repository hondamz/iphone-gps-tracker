# Bedienung

Stand: v0.5.0 (04.10.2026)

## 1. Installation
1. `GPSTracker.xcodeproj` in Xcode öffnen.
2. Target *GPSTracker* → *Signing & Capabilities* → eigenes Team wählen.
3. iPhone per Kabel/WLAN verbinden, als Ziel wählen, ▶︎ starten.
   Beim ersten Mal auf dem iPhone ggf. *Einstellungen → Allgemein → VPN & Geräteverwaltung* dem Entwickler vertrauen
   und den Entwicklermodus aktivieren.

## 2. Erster Start
1. Tab **Live** → **Start** tippen.
2. Standortzugriff erlauben – „Beim Verwenden der App“ reicht; für genaue Daten „Genauer Standort“ eingeschaltet lassen.
3. Optional in **Einstellungen → Aufzeichnung** „Immer erlauben“ anfragen.

## 2a. Tracker benennen
**Einstellungen → Tracker**: Namen eintragen (z. B. „Mein iPhone“). Der Server unterscheidet die
Tracker an diesem Namen (und an der Geräte-ID). iOS liefert Apps als Vorschlag meist nur „iPhone“ –
dann bitte selbst benennen.

## 2b. Kartenausschnitt
Oben auf der Live-Karte: **Lokal** zeigt die nähere Umgebung (wie Apple Karten),
**30 km / 100 km / 500 km** einen festen, größeren Ausschnitt um den Tracker – z. B. 500 km für eine
Fahrt quer durch Deutschland. Der Knopf rechts schaltet das automatische Mitführen ein/aus; mit den
Fingern verschieben/zoomen geht immer, ein Tipp auf einen Ausschnitt zentriert wieder.

## 2c. Privat oder geschäftlich
Auf der Live-Karte unter dem runden Positionsbutton: Ein Tipp wechselt zwischen **Privat** (Haus, grün) und
**Geschäftlich** (Koffer, orange). Die Wahl gilt ab sofort für alle neuen Punkte, auch mitten in einer Fahrt, und
bleibt nach einem Neustart erhalten. Bereits aufgezeichnete Punkte ändern sich nicht. Die Art wird mit übertragen;
im Viewer lässt sich unter *Streckenart* danach filtern.

## 3. Aufzeichnen
- Solange die Aufzeichnung läuft, wird bei Bewegung alle *Mindestabstand* Meter ein Punkt gespeichert.
- Die App darf in den Hintergrund; die blaue Anzeige oben zeigt die aktive Ortung.
- Mehr Detail = kleinerer Mindestabstand (mehr Daten, etwas mehr Akku). Zu Fuß 5–10 m, Auto 25–50 m.
- Messungen schlechter als *max. Ungenauigkeit* (z. B. in Gebäuden) werden verworfen.

## 4. Verlauf ansehen
- Tab **Verlauf** → Zeitraum wählen; mit dem Slider die Fahrt „abspielen“.
- Den Standard-Zeitraum stellst du in den Einstellungen ein.
- Über der Karte wählst du den Ausschnitt: *Lokal* zeigt die ganze Spur, *30/100/500 km* einen festen
  Ausschnitt um den Slider-Punkt, der beim Abspielen mitwandert.

## 5. Server-Übertragung einrichten
1. **Einstellungen → Serverziele** → Ziel antippen (Server 1, 2 oder 3):
   Name, Adresse (z. B. `https://tracker.example.de/api/track`), Benutzer, Passwort eintragen.
2. Mit dem Schalter in der Zielliste (oder „Aktiv“ in den Details) das Ziel ein- bzw. ausschalten.
   Alle aktiven Ziele erhalten dieselben Daten, jedes mit eigenem Rückstand.
   - Ein neu aktiviertes Ziel bekommt zunächst den kompletten bisherigen Verlauf.
     Soll es nur neue Punkte erhalten: Details → **Rückstand verwerfen …**
   - **Alle Punkte erneut senden …** schickt den gesamten Verlauf noch einmal an dieses Ziel.
3. **Übertragung → Modus** (gilt für alle aktiven Ziele):
   - *Live*: sendet neue Punkte gesammelt alle *Sammelintervall* Sekunden.
   - *Zeitgesteuert*: einmal täglich ab der eingestellten Uhrzeit.
   - *Nur manuell*: nur über **Jetzt übertragen**.
4. Die Zielliste zeigt je Ziel die offenen Punkte; Fehler erscheinen rot (Details zeigen die Meldung).
   Nichts geht verloren – offene Punkte werden beim nächsten Lauf gesendet. Fällt ein Ziel aus,
   werden die anderen trotzdem bedient.

> Test-Server: `http://192.168.x.y:8085/api/v1/ingest`, Benutzer `<benutzer>`, Passwort aus der Server-`.env`
> (`INGEST_USERS`). Schnittstelle: [server-schnittstelle.md](server-schnittstelle.md).

### Server 4: eigener Server (vorbelegt)
Liegt beim Bauen `GPSTracker/Resources/PrivateDefaults.json` vor (nicht im Git, Vorlage
`Config/PrivateDefaults.example.json`), ist Ziel 4 damit vorbelegt – bei uns der eigene Viewer über
Tailscale (`http://<rechner>.<tailnet>.ts.net:8085/api/v1/ingest`, Benutzer `<benutzer>`). Nur noch das
Passwort eintragen und das Ziel einschalten. Ohne die Datei ist Ziel 4 leer. Voraussetzung: Tailscale-App
auf dem iPhone verbunden. Bitte immer den Namen `….ts.net` verwenden, nicht die Tailscale-IP `100.x.x.x` –
diese blockiert iOS bei http („App Transport Security …“).

## 5a. Simulation (Testbetrieb)
1. **Einstellungen → Simulation → Betriebsart**:
   - *Mainz, Paderborn & Deutschland*: endlos zufällige Fahrten und Spaziergänge zwischen 26 Orten in
     Mainz/Wiesbaden (Hbf, Dom, Uni, Stadtteile, Wiesbaden), Paderborn/Borchen (Hbf, Dom, Uni, Schloss Neuhaus,
     Borchen, Bad Lippspringe, Flughafen …) und Köln/Bonn; gelegentlich eine Fernfahrt in eine andere Region.
     Der Banner zeigt z. B. „Fahrt: Mainz Hbf → Mainz-Gonsenheim“ oder „Fernfahrt: Köln Messe/Deutz → Paderborn Hbf“.
   - *Flughafen Köln/Bonn*: endlos zufällige Abschnitte auf dem ganzen Gelände – zu Fuß (Terminals,
     Bahnhof, Vorfelder, Betriebshof …), mit dem Fahrzeug (Servicestraßen, Frachtbereich, Parkplätze),
     Follow-me-Fahrten auf den Rollwegen, gelegentlich Startlauf/Landung. Ziele werden bevorzugt dort
     gewählt, wo die Simulation bisher am seltensten war – mit der Zeit kommen alle Bereiche vor.
     Ab und zu (ca. 7 % der Abschnitte) ein **Ausflug**: zu Fuß zum Bahnhof bzw. mit dem Auto vom
     Terminal 1, dann
     *Köln (Bahn)* über Messe/Deutz zum Hbf, *Köln (Auto)* zum Dom, *Bonn (Bahn)* S-Bahn bis Troisdorf,
     Umstieg, RE über Menden nach Bonn-Beuel, *Bonn (Auto)* zum Markt – jeweils Stadtrundgang und zurück.
     Der Banner zeigt den aktuellen Abschnitt, z. B. „Fahrt → DHL Frachthalle“.
2. **Zeitraffer** wählen (1× = Echtzeit; 60× fährt die Strecke 60-mal so schnell – angezeigte Geschwindigkeit
   und Linienführung werden entsprechend grob).
3. Aufzeichnung starten (Live → Start). Auf der Karte erscheint ein lila Marker und das Simulations-Banner.
4. Simulierte Punkte werden wie echte gespeichert und übertragen, tragen aber `source = simulation-…` –
   der Server kann sie so herausfiltern. Für echte Aufzeichnung Betriebsart wieder auf **Aus** stellen.

## 6. Backup & Wiederherstellung
1. **Einstellungen → Backup → Speicherziel** – einen Ordner in der Dateien-App wählen
   (iCloud Drive, „Auf meinem iPhone“, verbundener SMB-Server wie die Synology).
2. **Backup jetzt erstellen** schreibt `GPSTracker-Backup-<Datum>-<Zeit>.json` (Einstellungen inkl. der drei Ziele, ohne Passwörter, + alle Punkte).
3. **Backup wiederherstellen …** liest eine solche Datei ein. Vorhandene Punkte werden nicht doppelt angelegt.
   Mit dem Schalter darüber werden auch die Einstellungen übernommen (Passwort danach neu eingeben).

## 6a. Einstellungen und Serverziele übertragen
- **Sichern:** Einstellungen → *Einstellungen & Serverziele übertragen* → **Einstellungen exportieren …**
  (alles inkl. Ziele) oder **Serverziele exportieren …** (nur Ziele) und Speicherort wählen.
  Passwörter sind nur enthalten, wenn **Passwörter einschließen** an ist – sie stehen dann im Klartext in der Datei.
- **Ein Ziel per E-Mail weitergeben:** Serverziel antippen → *Weitergeben* → **Per E-Mail senden …**, Empfänger
  eintragen, senden. Das Passwort geht nur mit, wenn **Passwort mitsenden** an ist. Ohne Mail-Konto auf dem
  iPhone: **Teilen …** verwenden.
- **Empfangenes Ziel übernehmen:** Anhang `.gpsziel` in Mail antippen → *Teilen* → **GPS Tracker** (oder Datei in der
  Dateien-App antippen). Alternativ speichern und über **Serverziele importieren …** auswählen.
- **Beim Import** je Ziel festlegen, ob es übernommen wird und auf welchen Platz (Ziel 1–4); orange steht, welches
  vorhandene Ziel ersetzt wird. Ohne Passwort in der Datei bleibt das bisherige Passwort des Platzes erhalten.
  Danach ggf. beim Ziel unter *Rückstand* festlegen, ob der alte Verlauf an den neuen Server soll.

## 6b. Umzug auf die neue App-Kennung (nur bei Installationen vor v0.11.0)
Seit v0.11.0 heißt die Kennung `io.github.hondamz.gpstracker`. iOS installiert die App deshalb als **neue App** neben der
alten (beide heißen „GPS Tracker“); die neue startet leer.
1. In der **alten** App: *Backup → Speicherziel* wählen, und zwar **außerhalb des App-Ordners** (z. B. iCloud Drive).
   Der Ordner „Auf meinem iPhone → GPS Tracker“ wird mit der App gelöscht! Dann *Backup jetzt erstellen*.
2. In der **neuen** App: *Beim Wiederherstellen auch Einstellungen übernehmen* einschalten und
   *Backup wiederherstellen …* wählen. So bleibt die Geräte-ID gleich und es bleibt im Server derselbe Tracker.
3. Passwörter sind nicht im Backup: bei den Serverzielen neu eintragen.
4. Prüfen, dann die alte App löschen.

## 7. Daten löschen
**Einstellungen → Daten → Alle GPS-Daten löschen** entfernt alle lokalen Punkte (vorher Backup machen).

## Test im Simulator
- *Features → Location → Freeway Drive / City Run* in der Simulator-App.
- oder per Terminal eine Route abfahren:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl location booted start --speed=15 50.0000,8.2580 50.0045,8.2650 50.0110,8.2780
```

- Einfache Einstellungen für einen Testlauf per Startargument setzen (gilt nur für diesen Start), z. B.
  `-trackingEnabled YES -uploadMode live -liveIntervalSeconds 5`.
- Serverziele für Tests vorbelegen (App vorher beenden; JSON hex-kodiert):

```bash
xcrun simctl spawn booted defaults write io.github.hondamz.gpstracker serverTargets -data "$(printf '%s' '[{"id":1,"name":"Test","enabled":true,"url":"http://127.0.0.1:8101/track","account":""}]' | xxd -p | tr -d '\n')"
```
