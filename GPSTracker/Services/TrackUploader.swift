import Foundation

/// Schnittstelle zum Server. Die endgültige Spezifikation folgt später
/// (siehe docs/server-schnittstelle.md) – dann wird nur eine neue Implementierung
/// dieses Protokolls benötigt.
protocol TrackUploader {
    func upload(_ points: [TrackPointRecord], to server: ServerConfig) async throws
}

nonisolated enum UploadError: LocalizedError {
    case http(Int)
    case invalidResponse
    /// iOS (App Transport Security) blockiert unverschlüsseltes http zu dieser Adresse.
    case insecureHTTP(String)

    var errorDescription: String? {
        switch self {
        case .http(let status): "Server antwortet mit HTTP \(status)."
        case .invalidResponse: "Ungültige Antwort vom Server."
        case .insecureHTTP(let host): "iOS erlaubt unverschlüsseltes http zu \(host) nicht. Erlaubt sind "
            + "LAN-Adressen (z. B. 192.168.x.x) und Tailscale-Namen (<rechner>.<tailnet>.ts.net) – "
            + "Tailscale-IPs (100.x.x.x) nicht. Alternativ https verwenden."
        }
    }
}

/// VORLÄUFIGE Implementierung: POST eines JSON-Pakets an die konfigurierte URL,
/// optional mit HTTP Basic Auth. Erfolgreich ist jede 2xx-Antwort.
struct ProvisionalJSONUploader: TrackUploader {
    nonisolated struct Payload: Encodable, Sendable {
        let formatVersion = 2
        let deviceID: String
        let trackerName: String
        /// Gleicher Wert wie `trackerName` – so heißt das Feld beim Positions-Tracking-Viewer.
        let deviceName: String
        let deviceType = "iPhone"
        /// Software-Version des sendenden Trackers.
        let appVersion: String
        let appBuild: Int
        let sentAt: Date
        let points: [Point]
    }

    /// Messpunkt ohne den app-internen Übertragungsstatus.
    nonisolated struct Point: Encodable, Sendable {
        let id: UUID
        let timestamp: Date
        let latitude, longitude, altitude, ellipsoidalAltitude: Double
        let horizontalAccuracy, verticalAccuracy, speed, speedAccuracy, course, courseAccuracy: Double
        /// Version, mit der der Punkt aufgezeichnet wurde (`nil` = vor v0.3.0).
        let appVersion: String?
        /// "gps" oder "simulation-<betriebsart>".
        let source: String
        /// `true` = durch eine Simulations-Betriebsart erzeugt, nicht echt gemessen.
        let simulated: Bool
        /// "private" oder "business"; `nil` = vor v0.10.0 aufgezeichnet.
        let tripCategory: String?

        init(_ r: TrackPointRecord) {
            id = r.id
            timestamp = r.timestamp
            latitude = r.latitude
            longitude = r.longitude
            altitude = r.altitude
            ellipsoidalAltitude = r.ellipsoidalAltitude
            horizontalAccuracy = r.horizontalAccuracy
            verticalAccuracy = r.verticalAccuracy
            speed = r.speed
            speedAccuracy = r.speedAccuracy
            course = r.course
            courseAccuracy = r.courseAccuracy
            appVersion = r.appVersion
            source = r.source ?? TrackPoint.gpsSource
            simulated = source != TrackPoint.gpsSource
            tripCategory = r.tripCategory
        }
    }

    func upload(_ points: [TrackPointRecord], to server: ServerConfig) async throws {
        var request = URLRequest(url: server.url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !server.account.isEmpty {
            let token = Data("\(server.account):\(server.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(Payload(
            deviceID: server.deviceID, trackerName: server.trackerName, deviceName: server.trackerName,
            appVersion: AppInfo.version, appBuild: AppInfo.build,
            sentAt: .now, points: points.map(Point.init)
        ))

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw UploadError.insecureHTTP(server.url.host() ?? server.url.absoluteString)
        }
        guard let http = response as? HTTPURLResponse else { throw UploadError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw UploadError.http(http.statusCode) }
    }
}
