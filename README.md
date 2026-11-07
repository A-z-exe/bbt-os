# BBT OS

**Bug Bounty Toolkit Edition** - an installable overlay that turns Kali Linux
into a focused bug bounty workstation for **Web**, **Wireless**, **Android**
and **Windows / Active Directory** hunting.

BBT OS is not a Kali ISO fork. It is a reproducible overlay: clone the repo,
run one installer, and a stock Kali Rolling system gets the tools, launcher,
wallpaper and identity of BBT OS. `ID=kali` is preserved in `os-release`, so
Kali tooling, repositories and updates keep working normally.

> **Authorized testing only.** Use every tool here only against systems you
> own or have written permission to test, and stay inside the published
> program scope. BBT refuses to scan without an explicit authorization flag
> and a matching scope file.

## Developer

- **AmirHossein Zarei** (امیرحسین زارعی) - `A-z-exe`
- GitHub: [github.com/A-z-exe](https://github.com/A-z-exe)
- Project page: [a-z-exe.github.io/bbt-os](https://a-z-exe.github.io/bbt-os/)
- Email: 207771865+A-z-exe@users.noreply.github.com
- Upstream: [Kali Linux](https://www.kali.org/) by OffSec (not affiliated)

## What you get

| Area | Contents |
| --- | --- |
| **Web / Recon** | subfinder, httpx, katana, nuclei, ffuf, wfuzz, whatweb, wafw00f, gobuster, feroxbuster, dirb, nikto, sqlmap, WPScan, amass, dnsx, naabu, gowitness, theHarvester, arjun, exploitdb, nmap, masscan, hydra |
| **Wireless** | `bbt-wifi` engine: adapter/monitor check, scan cache, automatic method choice, PMKID/SAE (hcxdumptool), 4-way handshake (aircrack-ng), WPS Pixie Dust (reaver/bully), WEP, hashcat cracking, run history, cleanup |
| **Android** | adb, fastboot, apktool, jadx + JADX GUI, apksigner, dex2jar, jd-gui, scrcpy, frida-tools, objection, MobSF (Docker), `bbt-android-recovery` for device state, data copy and owned-device lock removal |
| **Windows / AD** | Impacket, NetExec, Evil-WinRM, Responder, Enum4linux-ng, BloodHound.py |
| **Smart card / NFC** | PC/SC readers (`pcsc_scan`, OpenSC), ATR and PKCS#15/PIV certificates, NFC tag scan, NDEF read/write and MIFARE dump (authorized cards only) |
| **Workflows** | `bbt-workflow`: matched chains `web`, `wordpress`, `android`, `ad`, every host checked against the scope file; `bbt-surface`: scope-gated header, discovery and JavaScript bundle audit with a report draft |
| **Kernel / drivers** | headers, DKMS build tools, Wi-Fi/NFC firmware, `cfg80211`/`mac80211`/`nfc` modules, regdb, `rfkill`, open-vm-tools |
| **Toolkit** | [BBT Toolkit](https://github.com/A-z-exe/BugBountyToolkit) with scope-gated `-m auto` orchestration |
| **Desktop** | searchable neon GTK launcher with a designed 43-icon set, live status footer, BBT wallpaper, menu entry, double-click installers |
| **Health** | `bbt-os-doctor` audits kernel, services, adapters, toolchain, data and integrations, with `--fix` |

Additional desktop work:

- Hostname `bbt-os`, `os-release` pretty name and MOTD/issue branding.
- BBT OS boot splash (Plymouth) and boot-menu artwork (GRUB) replace the Kali
  dragon at boot, with a neon progress bar and password prompt.
- Branded login and lock screen (LightDM greeter artwork, BBT lock dialog,
  avatar) with `Ctrl+Alt+L` locking the session.
- The BBT OS launcher opens automatically a few seconds after login.
- Sleep, suspend, hibernate, screen blanking and lock disabled for long scans.
- VMware cursor fix (Adwaita cursor, `xsetroot` at login and `SWcursor` Xorg
  fallback for guests where `vmwgfx` loses the hardware cursor plane).
- Double-click installation for `.deb`, `.AppImage`, `.run` and `.sh` files,
  with an explicit confirmation dialog before anything is installed or run.

## Install

Requirements: a stock **Kali Linux Rolling** installation (XFCE desktop is the
supported session), network access and about 20 GB of free disk for the tool
sets and MobSF image.

```bash
git clone https://github.com/A-z-exe/bbt-os.git
cd bbt-os
sudo bash install.sh
```

The installer is idempotent and logs to `/var/log/bbt-os-provision.log`.
Log out and back in (or reboot) once so hostname, wallpaper and cursor changes
reach the graphical session.

### Install options

```text
--no-upgrade       skip apt full-upgrade
--no-web           skip web/recon tools and database refresh
--no-android       skip Android tools
--no-windows       skip Windows/AD tools
--no-mobsf         skip Docker and MobSF
--no-bbt           skip the BBT Toolkit checkout
--no-desktop       skip launcher, wallpaper and file associations
--no-branding      skip hostname, os-release, issue and MOTD
--no-boot          skip the BBT OS boot splash and GRUB artwork
--no-lock          skip lock/login screen branding and lock settings
--no-smartcard     skip smart card / NFC tools
--no-kernel        skip kernel headers, firmware and module setup
--no-wifi          skip wireless tools and the bbt-wifi engine
--no-workflows     skip the matched workflow engine
--no-audit         skip installing the health doctor
--web-only         web tooling only
--target-user USER choose the desktop user (default: SUDO_USER)
```

Examples:

```bash
sudo bash install.sh --no-upgrade              # keep the current Kali snapshot
sudo bash install.sh --web-only                # smallest useful install
sudo bash install.sh --no-mobsf --no-windows   # skip the large Docker image
```

Environment variables:

- `BBT_MOBSF_PULL=0` - install Docker but do not pull the MobSF image.
- `BBT_TARGET_USER=alice` - same as `--target-user alice`.
- `BBT_OS_LOG=/path/log` - change the provisioning log.

## The launcher

Search the application menu for **BBT OS**, or run:

```bash
bbt-os
```

The launcher is a dark, icon-driven console:

- **Sidebar** - one icon per module with a live action count; click to filter.
- **Tiles** - every action is a tile with its own neon icon, name and one-line
  description. Tile icons live in `/usr/share/bbt-os/icons` (43 hand-drawn
  SVGs, generated by `assets/icons/generate-icons.py`).
- **Search** - filters names, descriptions and keywords across all modules.
- **Footer** - kernel, wireless adapters, PC/SC readiness and `tools N/M`.
- **Doctor** - one click runs `sudo bbt-os-doctor` in a terminal.

Modules:

- **Web / Recon** - BBT Auto Hunt, Recon workflow, WordPress workflow, and help
  for each tool.
- **Wireless** - Wi-Fi capture + crack wizard, scan, adapter status, crack a
  hash, previous runs, wireless doctor.
- **Android** - APK analysis pipeline, ADB, APK decompile with apktool, JADX
  GUI, Frida, Objection, scrcpy, start/stop MobSF and open its web UI.
- **Windows / AD** - AD workflow, NetExec, Impacket, Evil-WinRM, Responder,
  Enum4linux-ng, BloodHound.py.
- **Smart Card** - readers, ATR/PKCS#15, NFC, NDEF, MIFARE and APDU actions.
- **System** - kernel report, hardware inventory, interfaces, services and the
  health doctor.
- **Reporting** - BBT help, edit `~/scope.txt`, open results, workflow runs,
  wireless runs and recon folders.
- **Updates** - refresh BBT OS, update nuclei templates, update BBT, upgrade
  the system.

Every action opens a terminal (or a native GUI app). Nothing is scanned
automatically. **BBT Auto Hunt** asks for a target URL, a scope file and an
authorization checkbox, then runs:

```bash
bbt -t https://app.example.com -m auto --authorized --scope-file ~/scope.txt
```

Add `--deep` for katana crawling, ffuf, nikto and subfinder.

Check the launcher and tool availability from a shell:

```bash
bbt-os-launcher --check
bbt-os-launcher --version
bbt-os-launcher --check | tail -n 3   # engines, icons, tools, missing
```

## Lock screen and login account

The LightDM greeter uses the BBT OS background and avatar, and the lock dialog
is styled to match (dark panel, neon accent, BBT avatar). Press **Ctrl+Alt+L**
or use the session menu to lock. Locking on suspend is enabled; idle blanking
stays off so long scans are not interrupted. To also lock after idle time:

```bash
xfconf-query -c xfce4-screensaver -p /saver/idle-activation/enabled -n -t bool -s true
xfconf-query -c xfce4-screensaver -p /saver/idle-activation/delay -n -t uint -s 900
```

BBT OS images log in as **bbt**. On an existing Kali install you can create that
account while keeping the current home directory (tools and virtualenvs keep
working) and disable the stock `kali` account:

```bash
git clone https://github.com/A-z-exe/bbt-os.git
cd bbt-os
sudo BBT_NEW_PASS='<your-password>' bash scripts/bbt-os-account.sh
```

The script takes ownership of the home directory for `bbt`, copies the old
group membership, adds `bbt` to `sudo` and `docker`, hides `kali` from the
greeter and disables its shell. Log out and back in as `bbt`; change the
password later with `passwd`.

## Smart card / NFC

`pcscd` runs at boot, so CCID readers (USB or built-in) work as soon as they
are plugged in. In a VM, attach the reader to the guest first
(**VM > Removable Devices**). Use the **Smart Card** group in the launcher or:

```bash
bbt-smartcard                  # readers, ATR, card name and algorithms
bbt-smartcard info             # ATR and supported algorithms
bbt-smartcard certs            # PKCS#15 / PIV certificates
bbt-smartcard nfc-scan         # NFC targets in the field
bbt-smartcard ndef-read        # read an NDEF message from a MIFARE tag
bbt-smartcard ndef-write FILE  # write NDEF (asks for AUTHORIZED)
bbt-smartcard mifare-dump      # mfoc key recovery + dump (asks for AUTHORIZED)
bbt-smartcard apdu 00A40400... # send one APDU (asks for AUTHORIZED)
```

Commands that write to a card ask you to type `AUTHORIZED`; `--authorized`
skips the prompt for scripts. Only use cards and tags you own or have written
authorization to test. Writing to payment cards, government IDs or other
people's credentials is illegal.

## Wireless

`bbt-wifi` is the wireless engine behind the **Wireless** module. It detects
the adapter, checks monitor-mode support, caches nearby access points and picks
the capture method that fits the network you name:

| Network | Method chosen |
| --- | --- |
| WPS advertised | `reaver` PixieWPS, `bully` fallback |
| WPA3 / SAE | `hcxdumptool` SAE/PMKID capture |
| WPA2 / WPA | `hcxdumptool` PMKID, then 4-way handshake |
| WEP | `aireplay-ng` ARP replay + `aircrack-ng` |
| Open | nothing to recover |

```bash
bbt-wifi status                 # adapters, drivers, bands, monitor support
sudo bbt-wifi scan              # active scan -> ~/bbt/wifi/last-scan.tsv
bbt-wifi plan --ssid MyNetwork  # show the tool chain before running it
sudo bbt-wifi attack --ssid MyNetwork --authorized
sudo bbt-wifi attack --ssid MyNetwork --method wps --authorized
sudo bbt-wifi attack --ssid MyNetwork --deauth --authorized   # 3 frames max
bbt-wifi crack --hash ~/bbt/wifi/latest/hashes.22000
bbt-wifi captures --open
bbt-wifi doctor
```

In the launcher, open **Wireless > Wi-Fi capture + crack**: pick the network
from the cached scan (or type the SSID), the method label shows what BBT will
use and why, then Start opens a root terminal and runs the whole chain. The
attack is scoped to the single BSSID you picked, deauth is off by default and
capped at 3 frames, and every run is saved to `~/bbt/wifi/<ssid>-<time>/`
with `summary.md`, `run.log`, captures and `history.tsv`.

`--method auto` needs no input; the launcher validates the SSID, BSSID and
channel and requires the permission checkbox. `--dry-run` prints the plan
without touching the adapter.

**Virtual machines have no wireless radio.** In VMware attach a USB adapter
first (**VM > Removable Devices > your adapter > Connect**), then:

```bash
lsusb | grep -iE 'wireless|802.11|atheros|realtek|ralink'
sudo rfkill unblock wifi
bbt-wifi status
```

Only test networks you own or have written permission to test. Deauth against
networks you do not control is illegal in most jurisdictions.

## Android devices and recovery

`bbt-android-recovery` works on the phone itself, not the APK: it reports the
device state, copies data off an authorized phone, clears a screen lock without
touching user data when the phone is already rooted, and prints the Linux-phone
password-recovery steps.

```bash
bbt-android-recovery status     # model, Android version, encryption, root, lock option
bbt-android-recovery plan       # what is possible without wiping
bbt-android-recovery pull --dest ~/bbt/android/case01 --i-own-this-device
bbt-android-recovery unlock --i-own-this-device
bbt-android-recovery linux      # postmarketOS, PinePhone, Librem 5
```

| Device state | Lock removal without data loss |
| --- | --- |
| ADB already authorized + root | `unlock` clears the credential with `locksettings`; data stays |
| ADB authorized, no root | Not supported; `pull` copies photos and documents |
| ADB unauthorized, or rebooted and never unlocked | Encrypted `/data` keeps ADB away; vendor service or proof of purchase only |
| Locked bootloader | Unlocking it wipes the phone; the helper never does it |
| Linux phone | Reset the account password offline; a LUKS disk still needs its passphrase |

The launcher exposes the same flow under **Android -> Device recovery** (status,
plan, copy data, remove lock, Linux phone). Every command except `status`,
`plan`, `linux` and `help` needs `--i-own-this-device`; the helper never wipes,
flashes, unlocks a bootloader or runs an exploit.

## Matched workflows

`bbt-workflow` chains the tools that fit together instead of leaving them as
separate commands. Every web and AD chain resolves the host and refuses it
unless it is inside the scope file.

```bash
bbt-workflow list
bbt-workflow web --target example.com --scope ~/scope.txt --authorized
bbt-workflow web --target app.example.com --scope ~/scope.txt --deep --authorized
bbt-workflow wordpress --url https://blog.example.com --scope ~/scope.txt --authorized
bbt-workflow android --apk ~/Downloads/app.apk
bbt-workflow ad --dc 10.0.0.10 --domain corp.local --scope ~/scope.txt --authorized
```

| Chain | Steps |
| --- | --- |
| `web` | subfinder -> httpx -> katana -> nuclei (in-scope hosts only) |
| `wordpress` | wpscan -> nuclei wordpress tags |
| `android` | apktool -> jadx -> endpoint and secret extraction -> `summary.md` |
| `ad` | nmap DC ports -> enum4linux-ng (passive, no credential attacks) |

Add `--dry-run` to print the exact commands. Runs are written to
`~/bbt/runs/<chain>-<target>-<time>/` with logs and `summary.md`.

## Surface audit

`bbt-surface` is the deliberate, low-noise counterpart to the chains: a few
GET requests against one in-scope host, with every redirect re-checked against
the scope file so the tool never follows a hop off-target.

```bash
bbt-surface --target https://app.example.com --scope ~/scope.txt --authorized
bbt-surface --target https://app.example.com --scope ~/scope.txt --timeout 20 --authorized
```

| Step | What it records |
| --- | --- |
| Response | status, size, final headers, redirect chain |
| Headers | missing CSP, HSTS, XFO, nosniff, Referrer-Policy, Permissions-Policy; cookies without Secure/HttpOnly/SameSite |
| Discovery | `robots.txt`, `sitemap.xml`, `security.txt`, `.git/HEAD`, `.env`, `package.json`, with content checks to reject soft-404 pages |
| JavaScript | `sourceMappingURL` references, external API hosts, secret patterns (AWS, Google, GitHub, Slack, JWT, private keys); referenced source maps probed for `200` |
| Report | `summary.md` with a prefilled title/severity/steps/evidence/impact/remediation skeleton |

Signals are written to `findings.txt` and clearly marked as *to verify*; the
tool never claims a vulnerability on its own. Output goes to
`~/bbt/runs/surface-<host>-<time>/` and `~/bbt/runs/latest-surface`.

## Kernel and drivers

`modules/kernel.sh` installs DKMS build tools, Wi-Fi/NFC firmware, wireless
regdb, `iw`, `rfkill`, `usbutils`, `pciutils`, `ethtool` and open-vm-tools,
loads `nfc`, `cfg80211` and `mac80211` at boot, unblocks the radio and reports
whether a wireless or NFC device is visible.

```bash
bbt-os-doctor                  # kernel section shows the live state
uname -r
ls /usr/src/linux-headers-*
```

Kali sometimes publishes headers for a newer kernel than the one that is
running. When no headers exist for the running kernel, the module installs the
newest available `linux-headers-*kali-amd64` and notes that DKMS modules build
after rebooting into the matching kernel. The module never removes a kernel.

## Health doctor

```bash
bbt-os-doctor                  # full report
bbt-os-doctor --summary        # one line: pass/warn/fail, wifi, kernel
bbt-os-doctor --json           # machine-readable
sudo bbt-os-doctor --fix       # install missing packages and repair data
```

It checks the kernel, services, network adapters, every tool group and the
data/integration files (scope, wordlists, hashcat rules, run directories).

## MobSF

MobSF runs in Docker:

```bash
mobsf start      # start the container on http://127.0.0.1:8000
mobsf status
mobsf logs
mobsf stop
```

The first install pulls `opensecurity/mobile-security-framework-mobsf`. If the
pull failed (network/VPN), run:

```bash
sudo docker pull opensecurity/mobile-security-framework-mobsf:latest
```

Your user is added to the `docker` group; log out and back in once to use
Docker without `sudo`.

## BBT Toolkit

BBT is cloned to `~/tools/BugBountyToolkit` and installed in a local virtual
environment. Use it from a terminal:

```bash
cat > ~/scope.txt <<'EOF'
example.com
*.example.com
EOF

~/tools/BugBountyToolkit/.venv-sys/bin/python -m bbt \
  -t https://app.example.com -m auto --authorized \
  --scope-file ~/scope.txt --deep --rate 10
```

`-m auto` refuses to run without `--authorized` and a scope file. It never
automatically exploits anything; sqlmap only verifies injection and PoCs are
verification-only. The `bbt` wrapper is also added to `~/.local/bin`.

## Double-click installers

`.deb`, `.AppImage`, `.run` and `.sh` files open with the BBT OS installer:

| File | What happens |
| --- | --- |
| `.deb` | Confirmation dialog, then `apt install` in a terminal with the password prompt. |
| `.AppImage` | Copied to `~/Applications`, an extract-and-run wrapper is created and a menu entry is added (no libfuse2 required). |
| `.run` | Confirmation, then it runs in a terminal as your user. |
| `.sh` | Same as `.run`, executed with `bash`. |

From a shell:

```bash
bbt-os-install-file --dry-run ~/Downloads/example.deb
bbt-os-install-file ~/Downloads/example.deb
```

## Refresh

```bash
sudo bbt-os-refresh
```

This runs `apt update`, upgrades packages, refreshes nuclei templates, WPScan,
ExploitDB, nmap scripts and pipx tools, updates the BBT checkout, refreshes the
wireless and workflow engines, reinstalls the icon set and reapplies the
desktop assets. Use `--no-upgrade` to skip the distro upgrade, or
`--no-web`, `--no-android`, `--no-windows`, `--no-mobsf`, `--no-bbt`,
`--no-desktop`, `--no-boot`, `--no-lock`, `--no-smartcard`, `--no-kernel`,
`--no-wifi`, `--no-workflows`, `--no-audit` to skip a group.

## Uninstall

```bash
sudo bash uninstall.sh
```

This removes the launcher, wallpaper, desktop entries, wrappers and branding,
restores the original identity files and boot artwork from
`/var/backups/bbt-os`, and sets the Kali Plymouth/GRUB theme back. Installed
apt tools and the BBT Toolkit checkout are intentionally left in place.

## Cursor is not visible (VMware)

BBT OS installs `xinput`, `x11-xserver-utils`, the Adwaita cursor theme, an
autostart `xsetroot -cursor_name left_ptr`, and a `SWcursor` Xorg fallback.
If the pointer is still invisible after a logout/login:

1. VMware: **VM > Settings > Display** and disable **Accelerate 3D graphics**
   (or set `mks.enable3d = "FALSE"` in the `.vmx` file while the VM is off).
2. Ensure VMware Tools is running: `systemctl status open-vm-tools`.
3. Re-run `sudo bash provision.sh` and log out/in.

## Layout

```text
install.sh              installer entry point (sudo)
provision.sh            full provisioning
refresh.sh              package + database + toolkit refresh
uninstall.sh            remove the overlay, restore identity
VERSION                 build identity
AUTHORS.md, LICENSE     developer and license
assets/                 launcher icon, wallpaper, login art, Plymouth splash, GRUB art
assets/icons/           42 neon SVG launcher icons + generator
branding/               issue, issue.net, motd
menu/                   GTK launcher and desktop entry
modules/                web, wifi, workflows, kernel, android, windows, smartcard, mobsf, bbt, audit, desktop, lockscreen, branding, boot
packages/               apt package manifests per tool group
scripts/                bbt-wifi, bbt-workflow, bbt-surface, bbt-android-recovery, bbt-os-doctor, wallpaper, cursor, account, smart card, installer, MobSF helper
share/                  AppImage and .run MIME definitions
```

## License

MIT - see [LICENSE](LICENSE). Kali Linux and its tooling keep their own
licenses; BBT OS is an independent community overlay and is not endorsed by
OffSec.
