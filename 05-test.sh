#!/usr/bin/env bash
# e) Test der Umgebung in der VM (idempotent). Baut laboperator, startet ein k3d-Cluster und deployt den Operator.
source "$(dirname "$0")/lib.sh"
vm_running || die "VM läuft nicht - erst 02-vm.sh"
vm_sh bash -s < "$LAB_DIR/guest/test.sh"
