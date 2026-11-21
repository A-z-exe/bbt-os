# Changelog

All notable changes to BBT OS are documented in this file.

## 2.6.2

### Fixed
- `provision.sh`: removed `msfconsole`, `burpsuite` and `wireshark` from the tool inventory — none of the manifests or modules install them, so a clean install always reported them as missing.
- `scripts/bbt-os-doctor.sh`: `probe()` now captures the real `timeout` exit code instead of the last pipeline stage, so the "did not answer in 6s" warning works.
- `scripts/bbt-os-doctor.sh`: `dalfox` and `john` are no longer flagged as required (they are not installed by any manifest and are not in the advertised tool set).
- `scripts/bbt-os-doctor.sh --fix`: no longer skips every `kali-tools-web` package, so required web tools can actually be repaired.
- `scripts/bbt-wifi.sh`: all value-taking attack options (`--ssid`, `--bssid`, `--channel`, `--security`, `--iface`, `--method`, `--timeout`, `--wordlist`, `--crack-time`, `--client`) now report a usage error instead of aborting with "unbound variable" under `set -u`.
- `uninstall.sh`: removes only the BBT lock-dialog CSS block instead of deleting everything to end of file, preserving user rules appended after it. `modules/lockscreen.sh` now writes an explicit block end marker.
- `menu/bbt-os-launcher.py`: `--version` and `--check` work on hosts without GTK/gi; the temporary terminal runner script is no longer leaked on `exec`; "Update BBT toolkit" reinstalls the package after `git pull` for console-script installations.

### Changed
- Project page (`docs/index.html`): added version badge, quick-start block, feature cards and updated metadata/structured data for version 2.6.2.
- `README.md`: corrected icon count (43) and aligned the advertised tool set with the doctor's checks (`dalfox`, `john`).
- Bumped `VERSION` from 2.6.1 to 2.6.2.
