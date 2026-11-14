#!/usr/bin/env bash
# Läuft als Benutzer in der VM: Rust-Toolchain und Cargo-Werkzeuge, Podman-Konfiguration, IDE-Erweiterungen.
set -euo pipefail
export LC_ALL=C.UTF-8
export PATH="$HOME/.cargo/bin:$HOME/go/bin:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
log()  { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }

# ---- Rust über rustup (Debian-Paket "rustup", Toolchains von static.rust-lang.org): stable, aktuell bei jedem Lauf
log "Rust: stable-Toolchain mit clippy, rustfmt, rust-analyzer, rust-src und musl-Zielen"
rustup set profile minimal >/dev/null 2>&1 || true
rustup toolchain install stable --profile minimal \
  -c clippy -c rustfmt -c rust-analyzer -c rust-src \
  -t aarch64-unknown-linux-musl -t x86_64-unknown-linux-musl >/dev/null 2>&1 \
  || warn "rustup toolchain install fehlgeschlagen"
rustup default stable >/dev/null 2>&1 || true
log "$(rustc --version 2>/dev/null || echo 'rustc fehlt')"

# ---- Cargo-Werkzeuge (aus dem Quellcode, --locked); vorhandene werden übersprungen
cargo_tool() { # <crate> [binary-name]
  local crate=$1 bin=${2:-$1}
  if cargo install --list 2>/dev/null | grep -q "^$crate v"; then log "$crate vorhanden"; return; fi
  log "cargo install $crate (dauert)"
  nice cargo install --locked "$crate" >"/tmp/cargo-install-$crate.log" 2>&1 || warn "$crate nicht installierbar (Log: /tmp/cargo-install-$crate.log)"
}
cargo_tool kopium        # CRDs (YAML/OpenAPI) -> Rust-Typen
cargo_tool cargo-edit    # cargo add / rm / upgrade
cargo_tool cargo-watch
cargo_tool cargo-nextest
cargo_tool cargo-audit
cargo_tool bacon
cargo_tool tokio-console # Async-Laufzeit beobachten

# ---- Podman rootless: Netzwerk-Backend und Socket (für k3d/k3p)
mkdir -p "$HOME/.config/containers"
[ -f "$HOME/.config/containers/containers.conf" ] || printf '[network]\nnetwork_backend = "netavark"\n' > "$HOME/.config/containers/containers.conf"
if systemctl --user enable --now podman.socket >/dev/null 2>&1; then log "podman.socket aktiv"; else warn "podman.socket nicht aktivierbar (nach Neustart erneut versuchen)"; fi

# ---- IDE-Erweiterungen (Open VSX)
installed="$(codium --list-extensions 2>/dev/null | tr 'A-Z' 'a-z' || true)"
ext() {
  if grep -qix "$(tr 'A-Z' 'a-z' <<<"$1")" <<<"$installed"; then log "Erweiterung $1 vorhanden"; return; fi
  if codium --install-extension "$1" >/dev/null 2>&1; then log "Erweiterung $1 installiert"; else warn "Erweiterung $1 nicht installierbar (übersprungen)"; fi
}
for id in rust-lang.rust-analyzer vadimcn.vscode-lldb tamasfe.even-better-toml fill-labs.dependi golang.go \
          redhat.vscode-yaml ms-kubernetes-tools.vscode-kubernetes-tools ms-azuretools.vscode-containers \
          ms-vscode.makefile-tools eamodio.gitlens mhutchie.git-graph usernamehw.errorlens editorconfig.editorconfig mkhl.direnv; do
  ext "$id"
done

# ---- Editor-Einstellungen (nur fehlende Schlüssel setzen, eigene Werte bleiben)
cfg="$HOME/.config/VSCodium/User/settings.json"
mkdir -p "$(dirname "$cfg")"
[ -f "$cfg" ] || echo '{}' > "$cfg"
python3 - "$cfg" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for k, v in {
  "telemetry.telemetryLevel": "off", "update.mode": "none", "workbench.startupEditor": "none",
  "editor.fontSize": 15, "terminal.integrated.fontSize": 14, "debug.console.fontSize": 14,
  "editor.fontFamily": "'Fira Code', 'DejaVu Sans Mono', monospace", "editor.fontLigatures": True,
  "editor.minimap.enabled": False, "window.zoomLevel": 0, "security.workspace.trust.enabled": False,
  "rust-analyzer.check.command": "clippy", "files.watcherExclude": {"**/target/**": True},
}.items():
    d.setdefault(k, v)
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
log "user.sh fertig"
