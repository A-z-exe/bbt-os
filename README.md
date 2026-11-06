# BBT OS

**Bug Bounty Toolkit Edition** - an installable overlay that turns Kali Linux
into a focused bug bounty workstation for **Web**, **Android** and
**Windows / Active Directory** hunting.

BBT OS is not a Kali ISO fork. It is a reproducible overlay: clone the repo,
run one installer, and a stock Kali Rolling system gets the tools, launcher,
wallpaper and identity of BBT OS. `ID=kali` is preserved in `os-release`, so
Kali tooling, repositories and updates keep working normally.

> **Authorized testing only.** Use every tool here only against systems you
> own or have written permission to test, and stay inside the published
> program scope. BBT refuses to scan without an explicit authorization flag
> and a matching scope file.

## Developer

- **AmirHossein Zarei** (A-z-exe)
- GitHub: [github.com/A-z-exe](https://github.com/A-z-exe)
- Email: 207771865+A-z-exe@users.noreply.github.com
- Upstream: [Kali Linux](https://www.kali.org/) by OffSec (not affiliated)

## What you get

| Area | Contents |
| --- | --- |
| **Web / Recon** | subfinder, httpx, katana, nuclei, ffuf, wfuzz, whatweb, wafw00f, gobuster, feroxbuster, dirb, nikto, sqlmap, WPScan, amass, dnsx, naabu, gowitness, theHarvester, arjun, exploitdb, nmap, masscan, hydra |
| **Android** | adb, fastboot, apktool, jadx + JADX GUI, apksigner, dex2jar, jd-gui, scrcpy, frida-tools, objection, MobSF (Docker) |
| **Windows / AD** | Impacket, NetExec, Evil-WinRM, Responder, Enum4linux-ng, BloodHound.py |
| **Toolkit** | [BBT Toolkit](https://github.com/A-z-exe/BugBountyToolkit) with scope-gated `-m auto` orchestration |
| **Desktop** | searchable neon GTK launcher, BBT wallpaper, menu entry, double-click installers |

Additional desktop work:

- Hostname `bbt-os`, `os-release` pretty name and MOTD/issue branding.
- BBT OS boot splash (Plymouth) and boot-menu artwork (GRUB) replace the Kali
  dragon at boot, with a neon progress bar and password prompt.
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

The launcher is a dark, searchable grid grouped into:

- **Web / Recon** - BBT Auto Hunt, Web Recon Pipeline, and help for each tool.
- **Android** - ADB, APK decompile with apktool, JADX GUI, Frida, Objection,
  scrcpy, start/stop MobSF and open its web UI.
- **Windows / AD** - NetExec, Impacket, Evil-WinRM, Responder, Enum4linux-ng,
  BloodHound.py.
- **Reporting** - BBT help, edit `~/scope.txt`, open results and recon folders.
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
```

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
ExploitDB, nmap scripts and pipx tools, updates the BBT checkout, and reapplies
the desktop assets. Use `--no-upgrade` to skip the distro upgrade, or
`--no-web`, `--no-android`, `--no-windows`, `--no-mobsf`, `--no-bbt`,
`--no-desktop`, `--no-boot` to skip a group.

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
assets/                 launcher icon, wallpaper, Plymouth splash and GRUB art (SVG/PNG)
branding/               issue, issue.net, motd
menu/                   GTK launcher and desktop entry
modules/                web, android, windows, mobsf, bbt, desktop, branding, boot
packages/               apt package manifests per tool group
scripts/                wallpaper, cursor, double-click installer, MobSF helper
share/                  AppImage and .run MIME definitions
```

## License

MIT - see [LICENSE](LICENSE). Kali Linux and its tooling keep their own
licenses; BBT OS is an independent community overlay and is not endorsed by
OffSec.
