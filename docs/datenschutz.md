# Datenschutzerklärung – GPS Tracker

Stand: 31.10.2026

*English summary at the end of this page.*

## Das Wichtigste in Kürze

- Die App zeichnet deinen Standort auf und speichert ihn **auf deinem iPhone**.
- Der Entwickler betreibt für die App keinen Server und erhält über die App **keine Standort- oder Gerätedaten**.
- Daten verlassen das Gerät nur, wenn **du** das auslöst oder einrichtest: Übertragung an einen selbst eingetragenen
  Server, Backup, Export oder E-Mail.
- Die App enthält keine Werbung, kein Tracking, keine Analysewerkzeuge und keine Fremd-SDKs.

## Anbieter und Kontakt

Die App wird vom Inhaber des GitHub-Kontos [hondamz](https://github.com/hondamz) bereitgestellt. Fragen zum Datenschutz
kannst du über die [Issues dieses Repos](https://github.com/hondamz/iphone-gps-tracker/issues) stellen oder als
TestFlight-Tester über die Feedback-Funktion von TestFlight. Issues sind öffentlich; schreibe dort bitte keine
persönlichen Daten hinein.

## Welche Daten die App auf dem Gerät speichert

| Daten | Zweck | Speicherort |
|---|---|---|
| GPS-Punkte: Zeit, Position, Höhe, Geschwindigkeit, Richtung, Genauigkeit, Herkunft (GPS oder Simulation), Streckenart (privat/geschäftlich), App-Version, Übertragungsstand | Karte, Verlauf, GPS-Daten, Übertragung | App-Datenbank |
| Einstellungen: Tracker-Name (voreingestellt der von iOS gemeldete Gerätename), zufällig erzeugte Geräte-ID der Installation, Serverziele mit Adresse und Benutzername | Betrieb der App | App-Einstellungen |
| Passwörter der Serverziele | Anmeldung am jeweiligen Server | iOS-Schlüsselbund, nur auf diesem Gerät |

Der Standort wird nur mit deiner Erlaubnis verwendet, bei erteilter Erlaubnis „Immer“ auch im Hintergrund, damit eine
Aufzeichnung bei gesperrtem Gerät weiterläuft. Die Erlaubnis kannst du jederzeit in den iOS-Einstellungen ändern.

## Wann Daten das Gerät verlassen

**Übertragung an Server (optional).** Ist ein Serverziel eingetragen und aktiv, sendet die App an dessen Adresse die
GPS-Punkte samt ihren Messwerten, die Geräte-ID, den Tracker-Namen, den Gerätetyp und die App-Version, außerdem
Benutzername und Passwort zur Anmeldung. Für diese Server ist derjenige verantwortlich, der sie betreibt, also du selbst
oder die Person, deren Adresse du einträgst. Der Entwickler hat darauf keinen Zugriff. Trägst du eine `http`-Adresse ein,
werden die Daten unverschlüsselt übertragen; verwende nach Möglichkeit `https`.

**Backup, Export und E-Mail (optional).** Backups enthalten Einstellungen und alle GPS-Punkte und werden in dem von dir
gewählten Ordner abgelegt, zum Beispiel in iCloud Drive oder auf einem eigenen Netzlaufwerk. Exporte von Einstellungen
und Serverzielen kannst du speichern oder per E-Mail und Teilen-Funktion weitergeben; Passwörter sind nur enthalten, wenn
du das beim Export ausdrücklich wählst. Solche Dateien sind nicht verschlüsselt.

**Karten von Apple.** Die Karten stammen von Apple (MapKit). Zum Laden der Karte werden Anfragen an Apple gesendet, aus
denen sich der angezeigte Kartenausschnitt ergibt. Es gilt die
[Datenschutzrichtlinie von Apple](https://www.apple.com/legal/privacy/).

**iOS-Sicherungen.** Je nach deinen iOS-Einstellungen können App-Daten in iCloud- oder Computer-Sicherungen des iPhones
enthalten sein. Das steuert iOS, nicht die App.

## TestFlight

Beim Test über TestFlight verarbeitet Apple Daten nach eigenen Bedingungen. Dem Entwickler stellt Apple dabei Angaben wie
die Einladungs-E-Mail-Adresse oder den Namen, Installations- und Nutzungsdaten, Absturzberichte und von dir gesendetes
Feedback zur Verfügung. Sie werden nur zur Durchführung des Tests und zur Fehlerbehebung verwendet und nicht
weitergegeben.

## Speicherdauer und Löschen

Daten bleiben auf dem Gerät, bis du sie löschst. Es gibt keine automatische Löschfrist.

- **Alle GPS-Daten löschen:** Einstellungen → „Alle GPS-Daten löschen …“.
- **App löschen:** entfernt Datenbank und Einstellungen. Passwörter im iOS-Schlüsselbund können dabei erhalten bleiben,
  bis du sie vorher in der App entfernst oder das Gerät zurücksetzt.
- **Server und Backups:** Bereits übertragene Daten und angelegte Dateien bleiben davon unberührt und müssen beim
  jeweiligen Server oder Speicherort gelöscht werden.

## Deine Rechte

Nach der DSGVO hast du das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit
und Widerspruch sowie das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu beschweren. Die Daten in der App verwaltest
du direkt selbst. Für übertragene Daten wende dich an den Betreiber des jeweiligen Servers.

## Änderungen

Ändert sich der Umgang der App mit Daten, wird diese Seite angepasst. Frühere Fassungen stehen im Verlauf dieses Repos.

---

## English summary

GPS Tracker records your location and stores it on your iPhone. The developer runs no server for the app and receives no
location or device data through it. The app contains no advertising, tracking, analytics or third-party SDKs. Data leaves
the device only when you set it up or trigger it: uploads to a server you enter yourself (track points, device ID, tracker
name, device type, app version and that server's login), backups, exports and e-mail. Maps are provided by Apple (MapKit).
During TestFlight testing Apple provides the developer with tester details, usage data, crash reports and feedback, used
only to run the test and fix bugs. You can delete all track data in the app's settings. Questions:
[GitHub Issues](https://github.com/hondamz/iphone-gps-tracker/issues).
