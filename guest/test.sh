#!/usr/bin/env bash
# e) Abnahmetest in der VM: Toolchains, Browser, KI-Werkzeuge, Build von laboperator, k3d-Cluster mit Deployment.
# Bricht beim ersten Fehler mit Exit-Code != 0 ab.
set -euo pipefail
export LC_ALL=C.UTF-8
export PATH="$HOME/.cargo/bin:$HOME/go/bin:$PATH:/opt/node/bin:$HOME/.npm-global/bin:$HOME/.local/bin"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export CC_aarch64_unknown_linux_musl=musl-gcc
pass() { printf '\033[1;32m  PASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m  FAIL\033[0m %s\n' "$*"; exit 1; }
base="$HOME/Projects/kubers"

# 1. Sprachen und Werkzeuge
rustc --version >/dev/null 2>&1 && pass "$(rustc --version)" || fail "rustc"
cargo --version >/dev/null 2>&1 && pass "$(cargo --version)" || fail "cargo"
rustup target list --installed 2>/dev/null | grep -q aarch64-unknown-linux-musl && pass "Rust-Ziel aarch64-unknown-linux-musl" || fail "musl-Ziel"
cargo clippy --version >/dev/null 2>&1 && pass "clippy" || fail "clippy"
rustfmt --version >/dev/null 2>&1 && pass "rustfmt" || fail "rustfmt"
for t in kopium cargo-nextest cargo-watch cargo-audit bacon tokio-console cargo-add; do
  command -v "$t" >/dev/null 2>&1 && pass "cargo-Werkzeug $t" || fail "cargo-Werkzeug $t"
done
go version >/dev/null 2>&1 && pass "$(go version)" || fail "go"
dlv version >/dev/null 2>&1 && pass "delve" || fail "delve"
gopls version >/dev/null 2>&1 && pass "gopls" || fail "gopls"
podman --version >/dev/null 2>&1 && pass "$(podman --version)" || fail "podman"
[ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ] && pass "Podman läuft rootless" || fail "Podman rootless"
kubectl version --client >/dev/null 2>&1 && pass "kubectl $(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion)" || fail "kubectl"
for c in "k3d version" "helm version --short" "k9s version --short" "stern --version" "kubectx --help" "kind version"; do
  $c >/dev/null 2>&1 && pass "${c%% *}" || fail "${c%% *}"
done

# 2. Kleine Übersetzungstests Rust und Go
tdir="$(mktemp -d)"
(cd "$tdir" && cargo new --quiet hello >/dev/null 2>&1 && cd hello && cargo run --quiet 2>/dev/null | grep -q "Hello, world" ) && pass "Rust: Hello World übersetzt und läuft" || fail "Rust Hello World"
mkdir -p "$tdir/g" && printf 'package main\nimport "fmt"\nfunc main() { fmt.Println("hallo-go") }\n' > "$tdir/g/main.go"
(cd "$tdir/g" && go run main.go | grep -q hallo-go) && pass "Go: Hello World läuft" || fail "Go Hello World"
rm -rf "$tdir"

# 3. Browser
chromium --version >/dev/null 2>&1 && pass "$(chromium --version)" || fail "chromium"
[ "$(xdg-settings get default-web-browser 2>/dev/null)" = chromium.desktop ] && pass "Standard-Browser: Chromium" || fail "Standard-Browser"
dom="$(timeout 60 chromium --headless=new --no-sandbox --disable-gpu --dump-dom 'data:text/html,<p id=t>browser-ok</p>' 2>/dev/null || true)"
grep -q 'browser-ok' <<<"$dom" && pass "Chromium rendert (headless)" || fail "Chromium headless"

# 4. KI-Werkzeuge und Erweiterungen
for c in claude opencode qwen; do
  v="$("$c" --version 2>/dev/null | head -1 || true)"
  [ -n "$v" ] && pass "$c $v" || fail "$c nicht gefunden"
done
for e in anthropic.claude-code sst-dev.opencode qwenlm.qwen-code-vscode-ide-companion saoudrizwan.claude-dev github.copilot-chat \
         rust-lang.rust-analyzer golang.go vadimcn.vscode-lldb tamasfe.even-better-toml redhat.vscode-yaml ms-kubernetes-tools.vscode-kubernetes-tools; do
  codium --list-extensions 2>/dev/null | grep -qix "$e" && pass "Erweiterung $e" || fail "Erweiterung $e"
done

# 5. Verzeichnisse
[ -d "$base/laboperator/.git" ] && pass "laboperator geklont ($(git -C "$base/laboperator" log --oneline -1))" || fail "laboperator fehlt"
[ -f "$HOME/Kubers.code-workspace" ] && pass "Workspace-Datei" || fail "Workspace-Datei"
code="$base/code"
[ -L "$code" ] && touch "$code/.write-test" && rm -f "$code/.write-test" && pass "code/ ist beschreibbar (liegt auf dem Mac: $(readlink "$code"))" || fail "code/ Verknüpfung"

# 6. laboperator bauen (native musl-Binärdatei für ARM64)
(cd "$base/laboperator" && kubers-laboperator build >/tmp/laboperator-build.log 2>&1) || { tail -30 /tmp/laboperator-build.log; fail "laboperator build"; }
[ -x "$base/laboperator/target/aarch64-unknown-linux-musl/release/laboperator" ] && pass "laboperator gebaut ($(stat -c %s "$base/laboperator/target/aarch64-unknown-linux-musl/release/laboperator") Byte)" || fail "laboperator-Binärdatei fehlt"

# 7. Cluster, Image, Deployment
kubers-up >/tmp/kubers-up.log 2>&1 || { tail -30 /tmp/kubers-up.log; fail "kubers-up (k3d-Cluster)"; }
kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null 2>&1 && pass "k3d-Cluster: Knoten Ready" || fail "Knoten nicht Ready"
(cd "$base/laboperator" && kubers-laboperator image >/tmp/laboperator-image.log 2>&1) || { tail -20 /tmp/laboperator-image.log; fail "podman build"; }
pass "Container-Image gebaut (Podman)"
(cd "$base/laboperator" && kubers-laboperator push >/tmp/laboperator-push.log 2>&1) || { tail -20 /tmp/laboperator-push.log; fail "Push in die lokale Registry"; }
pass "Image in k3d-lab-registry.localhost:5000 gepusht"
(cd "$base/laboperator" && kubers-laboperator deploy >/tmp/laboperator-deploy.log 2>&1) || { tail -20 /tmp/laboperator-deploy.log; fail "kubectl apply"; }
kubectl rollout status deployment/laboperator-test --timeout=240s >/dev/null 2>&1 && pass "Deployment laboperator-test läuft (Probes grün)" \
  || { kubectl get pods -A | tail -8; kubectl describe pod -l app=laboperator-test | tail -15; fail "Rollout laboperator-test"; }
kubectl get pods -l app=laboperator-test
kubers-down >/dev/null 2>&1 && pass "Cluster wieder entfernt" || true
echo "Alle Tests bestanden."
