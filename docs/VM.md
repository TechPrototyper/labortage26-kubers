# VM „kubers“ – Kubernetes, Rust, Go

Gebaut von **labortage26-kubers** · Debian 13 ARM64 · 4 CPUs, 8 GB RAM, 80 GB Platte (sparse) · Start: **StartKubers** auf dem Mac-Schreibtisch

> Stand: aufgebaut und getestet am 14.11.2026 (Operator gebaut, k3d-Cluster gestartet, Image gepusht, Deployment läuft, Probes grün).

## Wofür
Experimentierumgebung für Kubernetes-Operatoren in Rust (nach dem Vortrag *Kubernetes Operators in Rust*, Labortage 2026), später auch
für Go und weitere Kubernetes-Experimente. Beispielprojekt: [laboperator](https://codeberg.org/platforms-systems/laboperator).

## Ordner in der VM (`~/Projects/kubers/`)
| Ordner | Inhalt |
|---|---|
| `laboperator/` | Beispielprojekt aus dem Vortrag (Codeberg) |
| `labortage26-kubers/` | das Skript-Repo |
| `code/` | Verknüpfung auf `~/Projects/kubers/code` **auf dem Mac** – eigener Code, bleibt erhalten |
| weitere | weitere Repositories einfach als Ordner hier ablegen |

IDE: Starter „Kubers IDE“ öffnet `~/Kubers.code-workspace` mit laboperator, code und dem Skript-Repo.

## Werkzeuge
- **Rust:** `rustup` (stable, clippy, rustfmt, rust-analyzer, musl-Ziele), `kopium`, `cargo-edit`, `cargo-watch`, `cargo-nextest`, `cargo-audit`, `bacon`, `tokio-console`
- **Go:** `golang-go`, `gopls`, `delve`
- **Container/Kubernetes:** rootless **Podman** (+ `buildah`, `skopeo`, `podman-compose`), **k3d**/k3s über Podman (`k3p`), `kubectl`, `kind`, `helm`, `k9s`, `stern`, `kubectx`/`kubens`
- **Browser und KI:** Chromium (Standard-Browser), Claude Code, OpenCode, Qwen Code; Erweiterungen Claude Code (Standard), Cline, OpenCode, Qwen Code, GitHub Copilot Chat
- **IDE:** VSCodium mit rust-analyzer, CodeLLDB, Go, YAML, Kubernetes, Container, TOML, Makefile u. a.

## Cluster und laboperator
```bash
kubers-up                 # Registry k3d-lab-registry.localhost:5000 + Cluster "lab-cluster" (idempotent)
kubers-laboperator all    # bauen (aarch64-musl), Image bauen, pushen, deployen
kubectl get pods          # laboperator-test
kubers-down               # Cluster und Registry entfernen
```
Desktop-Starter: „Cluster starten“, „k9s“, „Cluster beenden“. Hinweis ARM: `laboperator` zielt im Makefile auf x86_64; der Helfer baut nativ
für aarch64 und legt dafür eine Verknüpfung, das Projekt bleibt unverändert.

## Alltag
- Anzeigegröße: `labzoom normal|gross|riesig`
- Abnahmetest: `./05-test.sh` im Skript-Repo auf dem Mac (baut den Operator und fährt ein Test-Cluster)
- Neu aufbauen: `./run-all.sh` im Repo `labortage26-kubers` (idempotent; erster Lauf 60–90 Minuten)
- KI-Werkzeuge wie in der Z80-VM; Standard ist Claude
