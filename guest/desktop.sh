#!/usr/bin/env bash
# Läuft als Benutzer, nachdem die Repos geklont sind: Autostart für labzoom, Workspace, Desktop-Starter.
set -euo pipefail
export LC_ALL=C.UTF-8
log() { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }

mkdir -p "$HOME/Desktop" "$HOME/.config/labzoom" "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/labzoom.desktop" <<AUTO
[Desktop Entry]
Type=Application
Name=Anzeigegröße anwenden
Exec=/usr/local/bin/labzoom apply
Terminal=false
X-GNOME-Autostart-Phase=Initialization
AUTO

# Standard-Browser: Chromium (Debian). Google Chrome gibt es für Linux nur für x86_64, nicht für ARM64.
xdg-settings set default-web-browser chromium.desktop >/dev/null 2>&1 || true
mkdir -p "$HOME/.config/xfce4"
if grep -q '^WebBrowser=' "$HOME/.config/xfce4/helpers.rc" 2>/dev/null; then
  sed -i 's/^WebBrowser=.*/WebBrowser=chromium/' "$HOME/.config/xfce4/helpers.rc"
else
  echo 'WebBrowser=chromium' >> "$HOME/.config/xfce4/helpers.rc"
fi

# Workspace mit Operator-Projekt, eigenem Code und diesem Repo
cat > "$HOME/Kubers.code-workspace" <<'WS'
{
  "folders": [
    { "name": "laboperator", "path": "Projects/kubers/laboperator" },
    { "name": "code (liegt auf dem Mac)", "path": "Projects/kubers/code" },
    { "name": "labortage26-kubers", "path": "Projects/kubers/labortage26-kubers" }
  ]
}
WS

mk() { # mk <Datei> <Name> <Exec> <Icon> [Terminal]
  f="$HOME/Desktop/$1.desktop"
  cat > "$f" <<DESK
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
Terminal=${5:-false}
StartupNotify=false
DESK
  chmod +x "$f"
}
mk kubers-ide     "Kubers IDE"            "codium \$HOME/Kubers.code-workspace"                      vscodium
mk kubers-term    "Terminal"              "xfce4-terminal --working-directory=\$HOME/Projects/kubers"  utilities-terminal
mk kubers-up      "Cluster starten"       "xfce4-terminal --hold -e kubers-up"                         applications-system
mk kubers-k9s     "k9s (Cluster-UI)"      "xfce4-terminal -e k9s"                                      utilities-terminal
mk kubers-down    "Cluster beenden"       "xfce4-terminal --hold -e kubers-down"                       process-stop
mk kubers-zoom    "Anzeigegröße"          "/usr/local/bin/labzoom pick"                                preferences-desktop-font
rm -f "$HOME/Desktop/labcomp-"*.desktop

# Als vertrauenswürdig markieren (sonst fragt XFCE bei jedem Start nach). Braucht den Session-Bus.
bus="/run/user/$(id -u)/bus"
if [ -S "$bus" ]; then
  for f in "$HOME"/Desktop/kubers-*.desktop; do
    sum="$(sha256sum "$f" | cut -d' ' -f1)"
    DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" gio set -t string "$f" metadata::xfce-exe-checksum "$sum" 2>/dev/null \
      && DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" gio set "$f" metadata::trusted true 2>/dev/null || true
  done
else
  echo "  !! kein Session-Bus - Starter nicht als vertrauenswürdig markiert (beim ersten Start bestätigen)" >&2
fi
log "Desktop-Starter angelegt"

# Gewählte Anzeigegröße sofort anwenden (nicht kritisch, wenn keine Sitzung läuft)
/usr/local/bin/labzoom apply || true
