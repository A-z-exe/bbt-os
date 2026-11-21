# Changelog

All notable changes to BBT OS are documented in this file.

## 2.7.0

### Added — automated hunting
- `scripts/bbt-autohunt.sh`: one-command, scope-gated pipeline (subdomain discovery → live host probe → fingerprint/TLS → nuclei/dalfox/nikto/ffuf/commix → report).
- `scripts/bbt-report.py`: converts run output into a Markdown report with findings, PoC guidance and remediation notes.
- Installed in the VM as `bbt-autohunt`.

### Added — expanded bug-bounty toolset
- `packages/web.txt`: added `dirsearch`, `commix`, `dalfox`, `dnsrecon`, `fierce`, `recon-ng`, `sslscan`, `testssl.sh`, `burpsuite`, `metasploit-framework`, `wireshark` and `john`.
- `provision.sh` verification now checks for all of the above binaries, so a clean install confirms they are present instead of silently omitting them.
- `scripts/bbt-os-doctor.sh`: added health checks for the new tools (`msfconsole`, `burpsuite`, `wireshark`, `dalfox`, `dirsearch`, `commix`, `dnsrecon`, `fierce`, `recon-ng`, `sslscan`, `testssl.sh`, `john`).
- `README.md`: new "Exploitation / proxy" row and updated Web/Recon tool list.

### Fixed (from 2.6.2, retained)
- `scripts/bbt-os-doctor.sh`: `probe()` now captures the real `timeout` exit code instead of the last pipeline stage.
- `scripts/bbt-os-doctor.sh --fix`: no longer skips every `kali-tools-web` package, so required web tools can actually be repaired.
- `scripts/bbt-wifi.sh`: value-taking options report a usage error instead of aborting under `set -u`.
- `uninstall.sh`: removes only the BBT lock-dialog CSS block, preserving user rules appended after it.
- `menu/bbt-os-launcher.py`: text-only modes work without GTK; no leaked temp runner; `git pull` now reinstalls the toolkit.

### Changed
- Project page (`docs/index.html`, `gh-pages`) refreshed for v2.7.0.
- Bumped `VERSION` from 2.6.1 to 2.7.0.
