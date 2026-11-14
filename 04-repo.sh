#!/usr/bin/env bash
# d) Projektverzeichnisse in der VM einrichten (idempotent):
#   ~/Projects/kubers/laboperator            Operator-Projekt aus dem Vortrag (Codeberg)
#   ~/Projects/kubers/labortage26-kubers     dieses Repository
#   ~/Projects/kubers/code                   Verknüpfung auf den Mac-Ordner $LAB_CODE_DIR (eigener Code, bleibt erhalten)
# Weitere Repositories legst du einfach als weitere Ordner unter ~/Projects/kubers/ ab.
source "$(dirname "$0")/lib.sh"
vm_running || die "VM läuft nicht - erst 02-vm.sh"
mkdir -p "$LAB_CODE_DIR"

vm_sh bash -s "$LABOPERATOR_REPO_URL" "$LAB_ENV_REPO_URL" <<'GUEST'
set -euo pipefail
base="$HOME/Projects/kubers"
mkdir -p "$base"
clone_or_pull() { # url dir
  if [ -d "$2/.git" ]; then
    echo "  -> $(basename "$2") vorhanden, aktualisiere"
    git -C "$2" pull --ff-only || echo "  !! pull nicht möglich (lokale Änderungen?) - übersprungen" >&2
  else
    echo "  -> Klone $1"
    git clone "$1" "$2"
  fi
  git -C "$2" log --oneline -1
}
clone_or_pull "$1" "$base/laboperator"
# Dieses Repo: ist es (noch) nicht öffentlich erreichbar, bleibt der Ordner leer und wird unten vom Mac kopiert.
clone_or_pull "$2" "$base/labortage26-kubers" || echo "  !! Repo nicht klonbar (noch nicht veröffentlicht?) - wird vom Mac kopiert" >&2
ln -sfn /mnt/code "$base/code"
[ -d "$base/code" ] || { echo "  !! $base/code zeigt ins Leere - ist der Mount /mnt/code vorhanden?" >&2; exit 1; }
GUEST

# Fallback: Repo nicht per git in der VM vorhanden -> lokalen Stand vom Mac hinüberkopieren
if ! vm_sh test -d Projects/kubers/labortage26-kubers/.git 2>/dev/null; then
  log "Kopiere dieses Repository vom Mac in die VM"
  vm_sh bash -c 'mkdir -p "$HOME/Projects/kubers/labortage26-kubers"'
  limactl copy -r "$LAB_DIR/." "$VM_NAME:Projects/kubers/labortage26-kubers/"
fi

log "Desktop-Starter"
vm_sh bash -s < "$LAB_DIR/guest/desktop.sh"
