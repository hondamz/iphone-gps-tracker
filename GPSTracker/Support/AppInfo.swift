import Foundation

/// Software-Version der App. Wird bei jedem Push erhöht (siehe CLAUDE.md / CHANGELOG.md),
/// zu jedem GPS-Punkt gespeichert und an die Server übertragen.
enum AppInfo {
    /// Marketing-Version, z. B. "0.3.0".
    nonisolated static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fortlaufende Build-Nummer (= Anzahl der Pushes mit Versionssprung).
    nonisolated static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// Anzeigeform "0.3.0 (3)".
    nonisolated static var fullVersion: String { "\(version) (\(build))" }
}
