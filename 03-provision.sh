#!/usr/bin/env bash
# c) Software in der VM installieren (idempotent; mehrfach ausführbar).
source "$(dirname "$0")/lib.sh"
vm_running || die "VM läuft nicht - erst 02-vm.sh"

LAB_USER="$(vm_sh id -un)"

# Hilfsprogramme (k3p, kubers-up, kubers-down, kubers-laboperator, labzoom) in die VM bringen
vm_sh bash -c 'rm -rf /tmp/kubers-bin'
limactl copy -r "$LAB_DIR/guest/bin" "$VM_NAME:/tmp/kubers-bin"

log "Systempakete, Desktop, Container, Rust/Go, Kubernetes-Werkzeuge (als root)"
limactl shell --workdir / "$VM_NAME" -- sudo env LAB_USER="$LAB_USER" bash -s < "$LAB_DIR/guest/system.sh"

log "Rust-Toolchain, Cargo-Werkzeuge, IDE-Erweiterungen, Podman-Konfiguration (als $LAB_USER)"
vm_sh bash -s < "$LAB_DIR/guest/user.sh"

log "KI-Werkzeuge: Node.js (root)"
limactl shell --workdir / "$VM_NAME" -- sudo bash -s < "$LAB_DIR/guest/ai-root.sh"
log "KI-Werkzeuge: Claude Code, OpenCode, Qwen Code, Erweiterungen (als $LAB_USER)"
vm_sh bash -s < "$LAB_DIR/guest/ai-user.sh"

# Neustart, wenn sich Locale, Anmeldung oder systemd-Delegation geändert haben
if [ "$(vm_sh cat /var/lib/lab/needs-reboot 2>/dev/null || true)" = "1" ]; then
  log "Neustart der VM (Locale, Desktop, cgroup-Delegation)"
  limactl stop "$VM_NAME"
  limactl start --tty=false "$VM_NAME"
  limactl shell --workdir / "$VM_NAME" -- sudo rm -f /var/lib/lab/needs-reboot
fi
