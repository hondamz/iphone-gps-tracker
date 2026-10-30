#!/bin/sh
# Build-Prüfung für Release-Builds (TestFlight/Archiv): bricht ab, wenn private Daten im App-Paket stehen.
# Läuft als Build-Phase im Xcode-Projekt, nur bei CONFIGURATION=Release. Prüfziel: 1. Argument oder Build-Umgebung.
APP="${1:-$TARGET_BUILD_DIR/$WRAPPER_NAME}"
[ -d "$APP" ] || { echo "error: App-Paket nicht gefunden: $APP"; exit 1; }
if [ -e "$APP/PrivateDefaults.json" ]; then
  echo "error: PrivateDefaults.json ist im Release-Paket – private Voreinstellungen dürfen nicht verteilt werden."
  exit 1
fi
# konkrete Tailnet-Namen sowie Tailscale- und LAN-Adressen (Platzhalter wie 192.168.x.x treffen nicht)
PATTERN='tail[0-9a-f]{5,}\.ts\.net|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)|(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'
HITS=$(grep -rlaE "$PATTERN" "$APP" 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "error: Private Adressen im Release-Paket gefunden in:"
  echo "$HITS"
  exit 1
fi
echo "Release-Paket geprüft: keine privaten Daten."
