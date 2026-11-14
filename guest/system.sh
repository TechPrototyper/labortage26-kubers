#!/usr/bin/env bash
# Läuft als root in der VM. Idempotent: alles prüft vorher, was schon da ist.
set -euo pipefail
export LC_ALL=C.UTF-8
export DEBIAN_FRONTEND=noninteractive
: "${LAB_USER:?LAB_USER fehlt}"

log()  { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }
mkdir -p /var/lib/lab

# ---------------------------------------------------------------- Paketlisten
# Alles aus Debian 13, soweit vorhanden (echtes Debian, keine fremden Paketquellen außer VSCodium).
REQUIRED="build-essential git make gdb lldb pkg-config curl ca-certificates gnupg xz-utils unzip cmake libssl-dev
  protobuf-compiler jq yq ripgrep fd-find bat tmux direnv fzf hyperfine tokei git-delta shellcheck yamllint
  bash-completion httpie netcat-openbsd socat strace tcpdump bind9-dnsutils iproute2 iputils-ping
  x11-utils x11-xserver-utils xdotool xvfb imagemagick xfce4 xfce4-terminal lightdm lightdm-gtk-greeter dbus-x11
  xserver-xorg-core xserver-xorg-input-libinput fonts-dejavu fonts-liberation fonts-firacode mousepad locales zenity
  chromium
  podman buildah skopeo podman-compose uidmap netavark aardvark-dns passt slirp4netns fuse-overlayfs crun
  containernetworking-plugins
  rustup musl-tools musl-dev
  golang-go gopls delve
  kubernetes-client kind"
OPTIONAL="htop tree ncdu lsof"
avail() { LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print ($2 != "(none)" && $2 != "")}' | grep -q 1; }

log "apt update"
apt-get update -qq
log "Pflichtpakete"
# shellcheck disable=SC2086
apt-get install -y -qq $REQUIRED
log "Optionale Pakete"
want=(); skipped=()
for p in $OPTIONAL; do if avail "$p"; then want+=("$p"); else skipped+=("$p"); fi; done
[ ${#want[@]} -gt 0 ] && apt-get install -y -qq "${want[@]}" || true
[ ${#skipped[@]} -gt 0 ] && warn "Nicht verfügbar (übersprungen): ${skipped[*]}"

# ------------------------------------------------- Bildschirmsperre entfernen
# Das Lab-Konto hat kein Passwort; eine Sperre würde die Sitzung aussperren.
apt-get purge -y -qq xfce4-screensaver light-locker 2>/dev/null || true

# ------------------------------------------------------------ Locale/Tastatur
# Meldungen und Programmsprache: Englisch (en_US.UTF-8). Deutsch bleiben die Tastatur (de, siehe unten) sowie
# Zahlen-, Datums- und Währungsformat, Maßeinheiten und Papierformat (LC_*=de_DE.UTF-8).
if ! locale -a | grep -qi '^en_US.utf8' || ! locale -a | grep -qi '^de_DE.utf8'; then
  sed -i 's/^# *\(de_DE.UTF-8 UTF-8\)/\1/; s/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen >/dev/null
fi
want_locale='LANG=en_US.UTF-8
LC_NUMERIC=de_DE.UTF-8
LC_TIME=de_DE.UTF-8
LC_MONETARY=de_DE.UTF-8
LC_PAPER=de_DE.UTF-8
LC_MEASUREMENT=de_DE.UTF-8
LC_NAME=de_DE.UTF-8
LC_ADDRESS=de_DE.UTF-8
LC_TELEPHONE=de_DE.UTF-8'
if [ "$(cat /etc/default/locale 2>/dev/null)" != "$want_locale" ]; then
  printf '%s\n' "$want_locale" > /etc/default/locale
  echo 1 > /var/lib/lab/needs-reboot      # neue Anmeldung/Neustart nötig, damit die Sitzung es übernimmt
fi
cat > /etc/default/keyboard <<'KBD'
XKBMODEL="pc105"
XKBLAYOUT="de"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBD
timedatectl set-timezone Europe/Berlin 2>/dev/null || ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

# ------------------------------------------------------ Desktop / Autologin
mkdir -p /etc/lightdm/lightdm.conf.d
want_conf="[Seat:*]
autologin-user=$LAB_USER
autologin-user-timeout=0
autologin-session=xfce
"
if [ "$(cat /etc/lightdm/lightdm.conf.d/50-lab.conf 2>/dev/null)" != "${want_conf%$'\n'}" ]; then
  printf '%s' "$want_conf" > /etc/lightdm/lightdm.conf.d/50-lab.conf
  touch /var/lib/lab/needs-reboot; echo 1 > /var/lib/lab/needs-reboot
fi
echo /usr/sbin/lightdm > /etc/X11/default-display-manager
if [ "$(systemctl get-default)" != graphical.target ]; then
  systemctl set-default graphical.target
  echo 1 > /var/lib/lab/needs-reboot
fi
systemctl enable lightdm >/dev/null 2>&1 || true

# ------------------------------------------------------------------ VSCodium
# Offizielles Repo des VSCodium-Projekts (Open-Source-Build von VS Code ohne Telemetrie).
if ! dpkg -s codium >/dev/null 2>&1; then
  log "VSCodium installieren"
  curl -fsSL https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
    | gpg --dearmor --yes -o /usr/share/keyrings/vscodium-archive-keyring.gpg
  cat > /etc/apt/sources.list.d/vscodium.sources <<'SRC'
Types: deb
URIs: https://download.vscodium.com/debs
Suites: vscodium
Components: main
Architectures: amd64 arm64
Signed-by: /usr/share/keyrings/vscodium-archive-keyring.gpg
SRC
  apt-get update -qq
  apt-get install -y -qq codium
else
  log "VSCodium bereits installiert"
fi


# ------------------------------------------------ Rootless Podman / k3d vorbereiten
# subuid/subgid für den Benutzer
grep -q "^$LAB_USER:" /etc/subuid || usermod --add-subuids 100000-165535 "$LAB_USER"
grep -q "^$LAB_USER:" /etc/subgid || usermod --add-subgids 100000-165535 "$LAB_USER"
# cgroup-v2-Delegation für rootless k3s (cpu, cpuset, io, memory, pids)
mkdir -p /etc/systemd/system/user@.service.d
want_deleg='[Service]
Delegate=cpu cpuset io memory pids'
if [ "$(cat /etc/systemd/system/user@.service.d/delegate.conf 2>/dev/null)" != "$want_deleg" ]; then
  printf '%s\n' "$want_deleg" > /etc/systemd/system/user@.service.d/delegate.conf
  systemctl daemon-reload
  echo 1 > /var/lib/lab/needs-reboot
fi
# inotify-Limits (Kubernetes-Knoten und IDE brauchen viele Watches)
printf 'fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=524288\n' > /etc/sysctl.d/99-kubers.conf
sysctl --system >/dev/null 2>&1 || true
# Benutzer-systemd läuft auch ohne Anmeldung (podman.socket)
loginctl enable-linger "$LAB_USER" || true
# Registries: Docker Hub als Standard für kurze Namen, lokale k3d-Registry ohne TLS
mkdir -p /etc/containers/registries.conf.d
printf 'unqualified-search-registries = ["docker.io"]\n' > /etc/containers/registries.conf.d/10-unqualified.conf
cat > /etc/containers/registries.conf.d/50-kubers.conf <<'REG'
[[registry]]
location = "k3d-lab-registry.localhost:5000"
insecure = true

[[registry]]
location = "k3d-lab-registry.localhost"
insecure = true
REG
grep -q 'k3d-lab-registry.localhost' /etc/hosts || echo '127.0.0.1 k3d-lab-registry.localhost' >> /etc/hosts

# ------------------------------------------------ Kubernetes-Werkzeuge (gepinnte Binärdateien)
# kubectl und kind kommen aus Debian; der Rest ist nicht in Debian und wird mit SHA-256-Prüfung geladen.
fetch_bin() { # name url sha256 [tar-member]
  local name=$1 url=$2 sha=$3 member=${4:-} tmp
  if [ -x "/usr/local/bin/$name" ] && [ "$(cat "/var/lib/lab/$name.sha" 2>/dev/null)" = "$sha" ]; then
    log "$name bereits installiert"; return
  fi
  log "Installiere $name"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/dl" "$url"
  echo "$sha  $tmp/dl" | sha256sum -c --status || { echo "Prüfsumme $name falsch" >&2; rm -rf "$tmp"; exit 1; }
  if [ -n "$member" ]; then
    tar -xzf "$tmp/dl" -C "$tmp" "$member"
    install -m 755 "$tmp/$member" "/usr/local/bin/$name"
  else
    install -m 755 "$tmp/dl" "/usr/local/bin/$name"
  fi
  echo "$sha" > "/var/lib/lab/$name.sha"
  rm -rf "$tmp"
}
fetch_bin k3d     https://github.com/k3d-io/k3d/releases/download/v5.9.0/k3d-linux-arm64 03cde5cf23e6e8e67de5a039ecf26e5b85aca82fba3e5d13dadf904cd218a250
fetch_bin k9s     https://github.com/derailed/k9s/releases/download/v0.51.0/k9s_Linux_arm64.tar.gz 3ee05c82e5f9198928a4e86133608ba6a2c10a2244d6a7789e820f78319d640c k9s
fetch_bin helm    https://get.helm.sh/helm-v4.3.2-linux-arm64.tar.gz df31cb61680ef728f82c770e5280dd565617bee6b039d37e85c677288be4bbb0 linux-arm64/helm
fetch_bin stern   https://github.com/stern/stern/releases/download/v1.35.0/stern_1.35.0_linux_arm64.tar.gz b12f5e2ee0d01f6f21e0759cced0be2d8df9cd4e93e6a3cf11393170ae0f43cf stern
fetch_bin kubectx https://github.com/ahmetb/kubectx/releases/download/v0.11.0/kubectx_v0.11.0_linux_arm64.tar.gz 1dac2072216689e773325cb7587b858ea7415706ebcf04e23bf80e7e70555340 kubectx
fetch_bin kubens  https://github.com/ahmetb/kubectx/releases/download/v0.11.0/kubens_v0.11.0_linux_arm64.tar.gz 37058abe82ef20c93b44f3dc8ca2382dbb95d416cec958fbf7b8f79f011be86c kubens

# Hilfsprogramme aus dem Repo (k3p, kubers-up, kubers-down, kubers-laboperator, labzoom); 03-provision.sh legt sie in /tmp/kubers-bin ab
if [ -d /tmp/kubers-bin ]; then
  install -m 755 /tmp/kubers-bin/* /usr/local/bin/
fi

# Shell-Vervollständigung
for c in kubectl:"kubectl completion bash" helm:"helm completion bash" k3d:"k3d completion bash" kind:"kind completion bash"; do
  n=${c%%:*}; cmd=${c#*:}
  command -v "$n" >/dev/null 2>&1 && $cmd > "/etc/bash_completion.d/$n" 2>/dev/null || true
done

# PATH und Umgebung für alle Sitzungen
cat > /etc/profile.d/kubers.sh <<'KUBERS'
case ":$PATH:" in *":$HOME/.cargo/bin:"*) ;; *) export PATH="$HOME/.cargo/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$PATH:$HOME/go/bin" ;; esac
# natives Bauen für musl auf ARM64 (laboperator: aws-lc/ring brauchen einen C-Compiler für das musl-Ziel)
export CC_aarch64_unknown_linux_musl=musl-gcc
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
case $- in *i*) alias k=kubectl ;; esac
KUBERS
grep -q 'kubers.sh' /etc/bash.bashrc || printf '\n[ -r /etc/profile.d/kubers.sh ] && . /etc/profile.d/kubers.sh\n' >> /etc/bash.bashrc

log "system.sh fertig"
