# Server-Schnittstelle

**Status: abgestimmt mit dem Positions-Tracking-Viewer** (Server-Repo
[`positions-tracking-viewer`](positions-tracking-viewer),
dort `docs/schnittstelle.md`). Beide Dokumente beschreiben dieselbe Schnittstelle und werden gemeinsam
aktuell gehalten. Stand: App 0.5.0 / Server 0.2.0 (04.10.2026).

Die App kann bis zu **vier Serverziele** bedienen; jedes aktive Ziel erhält dieselben Pakete
(eigene URL und Zugangsdaten je Ziel, eigener Rückstand). Implementierung: `Services/TrackUploader.swift`.

## Ziele

| Ziel | Adresse | Benutzer | Hinweis |
|---|---|---|---|
| Ziel 4 (vorbelegt): Viewer über Tailscale | `http://<rechner>.<tailnet>.ts.net:8085/api/v1/ingest` | `<benutzer>` | von unterwegs; Tailscale auf dem iPhone muss aktiv sein. **Nicht** die Tailscale-IP `100.x.y.z` verwenden – iOS blockiert http dorthin |
| Test-Server (Positions-Tracking-Viewer auf <server>) | `http://192.168.x.y:8085/api/v1/ingest` | `<benutzer>` | nur im LAN bzw. über Tailscale; Benutzer/Passwort werden im Viewer unter **Einstellungen** verwaltet (seit Viewer 0.3.0) |

Weboberfläche des Test-Servers: `http://192.168.x.y:8085/`.

## Anfrage

- `POST <Server-URL>` mit `Content-Type: application/json`
- `Authorization: Basic base64(benutzer:passwort)` – beim Positions-Tracking-Viewer **Pflicht** (seit Viewer 0.3.0);
  die App sendet den Header, sobald im Ziel ein Benutzer eingetragen ist
- Pakete mit bis zu 500 Punkten, ältester zuerst (Server erlaubt bis 5000)

```json
{
  "formatVersion": 2,
  "deviceID": "00000000-0000-0000-0000-000000000000",
  "trackerName": "Mein iPhone",
  "deviceName": "Mein iPhone",
  "deviceType": "iPhone",
  "appVersion": "0.10.0",
  "appBuild": 15,
  "sentAt": "2026-10-04T13:33:40Z",
  "points": [
    {
      "id": "B8C58D4A-6DA9-4DA5-8F03-144E6CD3A713",
      "timestamp": "2026-10-04T13:31:18Z",
      "latitude": 50.0,
      "longitude": 8.258,
      "altitude": 110,
      "ellipsoidalAltitude": 158,
      "horizontalAccuracy": 5,
      "verticalAccuracy": 6,
      "speed": 15,
      "speedAccuracy": 0.5,
      "course": 63.43,
      "courseAccuracy": 5,
      "appVersion": "0.10.0",
      "source": "gps",
      "simulated": false,
      "tripCategory": "business"
    }
  ]
}
```

| Feld | Bedeutung | Server speichert |
|---|---|---|
| `deviceID` | stabile ID der Installation (bleibt bei Umbenennung gleich); unbekannt → Server legt Tracker an | `trackers.device_id` |
| `trackerName` / `deviceName` | Name aus Einstellungen → Tracker (beide Felder gleich, `deviceName` = Feldname des Servers) | Name neuer Tracker (später im Server änderbar) |
| `deviceType` | immer `iPhone` | `trackers.kind` |
| `appVersion`, `appBuild` | Software-Version des Senders zum Sendezeitpunkt | `trackers.app_version`, `ingest_log.app_version` als „0.5.0 (5)“ |
| `points[].id` | UUID des Punkts, Deduplizierung | `points.point_id` |
| `points[].timestamp` | Messzeit ISO 8601 UTC | `points.ts` |
| `latitude`, `longitude`, `altitude` | WGS84 / Meter über Meeresspiegel | `lat`, `lon`, `alt` |
| `horizontalAccuracy`, `verticalAccuracy` | Fehlerradius in m | `h_acc`, `v_acc` |
| `speed`, `course` | m/s, Grad | `speed`, `course` |
| `ellipsoidalAltitude`, `speedAccuracy`, `courseAccuracy` | Zusatzwerte | ignoriert |
| `points[].appVersion` | Version bei der Aufzeichnung; `null` = vor 0.3.0 | `points.app_version` |
| `points[].source` | `gps`, `simulation-germany`, `simulation-cgnAirport` | `points.origin` |
| `points[].simulated` | `true` = durch Simulation erzeugt, `false` = echt gemessen (ab App 0.6.0) | `points.simulated`; im Viewer ab 0.6.0 gestrichelt dargestellt und über „Datenherkunft“ filterbar |
| `points[].tripCategory` | `private` oder `business`; `null` = vor App 0.10.0 aufgezeichnet | `points.trip_category`; im Viewer ab 0.9.0 über „Streckenart“ filterbar |

Werte < 0 bedeuten „ungültig/unbekannt“ (CoreLocation-Konvention). Zeiten in ISO 8601 (UTC).

## Antwort des Servers

`200` mit Zusammenfassung – **auch wenn einzelne Punkte verworfen wurden** (dann nicht erneut senden):

```json
{"tracker": "Mein iPhone", "received": 500, "accepted": 497, "duplicates": 1,
 "flagged": 1, "rejected": 2, "reasons": {"Koordinate 0/0": 1, "markiert: sprung": 1}}
```

| Status | Bedeutung | App-Verhalten (0.5.0) |
|---|---|---|
| 2xx | angenommen (ggf. teilweise) | Paket als übertragen markieren |
| 400 | Paket unbrauchbar (z. B. unbekannte `formatVersion`) | Fehler anzeigen, Punkte bleiben offen ⚠️ |
| 401 | Anmeldung fehlt (`Anmeldung erforderlich`) oder falsch (`Benutzer oder Passwort falsch`) | Fehler anzeigen – Benutzer/Passwort prüfen |
| 403 | Benutzer im Viewer **deaktiviert** (`Benutzer „x“ ist deaktiviert – Datenübertragung nicht erlaubt`) | Fehler anzeigen, Punkte bleiben offen; nach Aktivierung wird nachgesendet |
| 413 | zu viele Punkte | (kommt bei 500er-Paketen nicht vor) |
| 5xx / keine Antwort | Server-/Netzproblem | später automatisch erneut senden |

Fehlerantworten haben die Form `{"detail": "<Meldung>"}` – der Text eignet sich zur Anzeige im Zielstatus.

⚠️ Offen: Bei 400 sollte die App das Paket nicht endlos wiederholen (Server-Empfehlung) – noch umzusetzen.
⚠️ Offen: Die App zeigt bei 401/403 bisher nur „HTTP 401/403“; schöner wäre der `detail`-Text des Servers.

Der Server prüft die Plausibilität (Sprünge, Genauigkeit > 100 m, Tempo > 500 km/h) und markiert solche
Punkte nur. Simulierte Punkte (`simulated: true`) sind davon ab Viewer 0.7.0 ausgenommen – Zeitraffer-Fahrten
erscheinen dort also vollständig.

## Versionsverlauf

| formatVersion | App | Server | Änderung |
|---|---|---|---|
| 1 | 0.1.0 | – | Grundformat (enthielt fälschlich `uploadedAt`) |
| 1 | 0.2.0 | 0.1.x | `uploadedAt` entfernt; Server 0.1.x übernimmt dieses Format |
| 2 | 0.3.0 | ab 0.2.0 | `trackerName`, `appVersion`, `appBuild`; je Punkt `appVersion`, `source` (Server 0.1.x lehnte das mit 400 ab) |
| 2 | 0.5.0 | 0.2.0 | zusätzlich `deviceName`, `deviceType` (Feldnamen des Servers) |
| 2 | 0.6.0 | 0.5.0 | je Punkt `simulated` (boolean) |
| 2 | 0.10.0 | 0.9.0 | je Punkt `tripCategory` |
