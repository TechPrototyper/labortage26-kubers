# labortage26-kubers

Wiederholbar aufgebaute **Experimentierumgebung für Kubernetes, Rust und Go auf dem Mac** (Apple Silicon): eine
Debian-13-VM mit Desktop, IDE, rootless Podman, einem lokalen k3d-Cluster und einer kompletten Rust-/Go-Toolchain.
Entstanden im Anschluss an den Vortrag *Kubernetes Operators in Rust* (Labortage 2026); als Beispielprojekt wird
[`laboperator`](https://codeberg.org/platforms-systems/laboperator) mitgeklont. Schwesterprojekt:
[labortage26-z80env](https://github.com/TechPrototyper/labortage26-z80env).

Die VM läuft mit [Lima](https://lima-vm.io) auf Apples Virtualization.framework: schnell, sparsam, Fenster direkt auf
dem Mac, kein XQuartz, keine VM-Lizenz.

## Voraussetzungen

- Mac mit Apple Silicon, macOS 13 oder neuer, [Homebrew](https://brew.sh)
- ca. 30 GB freier Speicher (die VM-Platte ist bis 80 GB „sparse“), 12 GB RAM sollten frei sein (die VM bekommt 8 GB)
- Zeit: der erste Lauf dauert **ca. 60–90 Minuten** (Cargo-Werkzeuge werden aus dem Quellcode gebaut); weitere Läufe wenige Minuten

## Los geht's

```bash
git clone https://github.com/TechPrototyper/labortage26-kubers.git
cd labortage26-kubers
./run-all.sh
```

Danach liegt **StartKubers** auf dem Schreibtisch. Doppelklick startet die VM; es öffnet sich ein Fenster mit dem
Linux-Desktop (automatische Anmeldung). `run-all.sh` ist **idempotent** und beliebig oft wiederholbar. Teilskripte:

| Skript | Aufgabe |
|---|---|
| `01-host.sh` | Lima und ImageMagick per Homebrew |
| `02-vm.sh` | Debian-Image laden (SHA-512 geprüft), VM `kubers` anlegen und starten, Lima-Schutz gegen versehentliches Löschen |
| `03-provision.sh` | Desktop, Container, Rust, Go, Kubernetes-Werkzeuge, Browser, KI-Werkzeuge, IDE einrichten |
| `04-repo.sh` | `~/Projects/kubers/` einrichten: `laboperator` und dieses Repo klonen, `code/` auf den Mac verknüpfen, Starter anlegen |
| `05-test.sh` | Abnahmetest inkl. Build von `laboperator`, k3d-Cluster, Push in die Registry, Deployment |
| `06-finish.sh` | VM herunterfahren, `StartKubers.app` auf den Schreibtisch legen |

Variablen: `VM_NAME` (Standard `kubers`), `LAB_CODE_DIR` (Mac-Ordner für eigenen Code, Standard
`~/Projects/kubers/code`), `LABOPERATOR_REPO_URL`, `LAB_ENV_REPO_URL`, `LAB_NO_STOP=1` (`06-finish.sh` lässt die VM laufen).

## Verzeichnisse

```
~/Projects/kubers/
├── laboperator/           Beispielprojekt aus dem Vortrag (Codeberg)
├── labortage26-kubers/    dieses Repository
├── code/                  Verknüpfung auf den Mac-Ordner (Standard ~/Projects/kubers/code)
└── …                      weitere Repositories einfach hier ablegen
```

Was in `code/` liegt, steht in Wahrheit **auf dem Mac** und übersteht jeden Neuaufbau der VM. Alles andere in der VM ist ersetzbar.

## Was installiert wird

- **System:** Debian 13 „trixie“ (ARM64), XFCE, Autologin, deutsche Tastatur; Meldungen auf Englisch (`en_US.UTF-8`),
  Zahlen-/Datumsformat, Maßeinheiten und Papier deutsch (`LC_*=de_DE.UTF-8`); Zeitzone Berlin
- **Rust:** `rustup` (Debian-Paket) mit stable, clippy, rustfmt, rust-analyzer und den Zielen `aarch64`/`x86_64-unknown-linux-musl`;
  Cargo-Werkzeuge `kopium`, `cargo-edit`, `cargo-watch`, `cargo-nextest`, `cargo-audit`, `bacon`, `tokio-console`; `musl-tools`
- **Go:** Debians `golang-go`, `gopls`, `delve`
- **Container und Kubernetes:** rootless **Podman** (mit `buildah`, `skopeo`, `podman-compose`), **k3d**/k3s über Podman (`k3p`),
  `kubectl` und `kind` (Debian), `helm`, `k9s`, `stern`, `kubectx`/`kubens` (Binärdateien mit SHA-256-Prüfung)
- **IDE:** VSCodium mit rust-analyzer, CodeLLDB, Go, YAML, Kubernetes-, Container-, TOML-, Makefile-Unterstützung u. a.
- **Browser:** Chromium (Debian), Standard-Browser. Google Chrome gibt es für Linux nur für x86_64, nicht für ARM64.
- **KI-Werkzeuge:** Claude Code (offizieller Installer), OpenCode, Qwen Code (npm, jeweils aktuelle Version bei jedem Lauf) und die
  VS-Code-Erweiterungen Claude Code, Cline, OpenCode, Qwen Code und GitHub Copilot Chat. **Standard ist Claude**: Claude Code öffnet
  in der Seitenleiste, Copilot-Vorschläge sind ausgeschaltet (in den Einstellungen `github.copilot.enable` einschaltbar).
  Es werden keine Zugangsdaten abgelegt; Anmeldung in der VM selbst (`claude`, `opencode auth login`, `qwen`, GitHub in der IDE).

Von außen geladene Dateien (VM-Image, Binärdateien, Node.js, VSIX, Quell-Commits) sind per Prüfsumme bzw. Commit gepinnt; Ausnahme sind
bewusst die „jeweils aktuellen“ npm-Pakete der KI-Werkzeuge.

## Cluster und laboperator

Auf dem VM-Desktop gibt es die Starter **Cluster starten**, **k9s** und **Cluster beenden**; im Terminal:

```bash
kubers-up                     # Registry k3d-lab-registry.localhost:5000 + k3d-Cluster "lab-cluster" (rootless Podman)
kubers-laboperator all        # bauen, Image bauen, in die Registry pushen, deployen
kubectl get pods              # laboperator-test läuft
kubers-down                   # Cluster und Registry entfernen
```

`kubers-laboperator` baut das Projekt nativ für `aarch64-unknown-linux-musl`, weil die VM ARM64 ist. Das Makefile von
`laboperator` zielt auf `x86_64-unknown-linux-musl`, das Containerfile erwartet diesen Pfad; deshalb wird dort eine
Verknüpfung auf das aarch64-Verzeichnis gelegt. Das Projekt selbst bleibt unverändert. (Außerdem zeigt im Makefile
`CLUSTERROLEBINDING` aus Versehen auf `clusterrole.yaml`; der Helfer übergibt die richtige Datei.)

## Anzeigegröße

Standard ist die Stufe **Groß** (1440×900, 144 dpi). Umstellen über den Starter „Anzeigegröße“ oder `labzoom normal|gross|riesig`.

## Zurücksetzen

```bash
limactl unprotect kubers && limactl delete kubers   # löscht die VM samt Inhalt (code/ auf dem Mac bleibt!)
./run-all.sh                                        # baut sie neu
```

## Quellen und Lizenz

Die Cluster-Einrichtung (`k3p`, Netzwerk, Registry, `KubeletInUserNamespace`) folgt dem Vortrag *Kubernetes Operators in Rust* von
CyReVolt (Folien: <https://metaspora.org/kubernetes-operators-in-rust-labortage2026.pdf>, CC BY 4.0). Die Skripte in diesem
Repository stehen unter der MIT-Lizenz (`LICENSE`); installierte Programme und geklonte Projekte haben ihre eigenen Lizenzen.
