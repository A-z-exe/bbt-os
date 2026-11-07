#!/usr/bin/env python3
"""BBT OS launcher - a dark, icon-driven console for bug bounty tooling.

Tiles never scan a target on their own: every guided action asks for the
target first, checks the authorization box, and then opens a terminal.
The wireless tile picks the best capture method for the network you name.

    bbt-os-launcher --check      list actions and missing tools
    bbt-os-launcher --version
"""
from __future__ import annotations

import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()
SCOPE_FILE = HOME / "scope.txt"
RECON_DIR = HOME / "bbt" / "recon"
WIFI_DIR = HOME / "bbt" / "wifi"
RUNS_DIR = HOME / "bbt" / "runs"
GITHUB = "https://github.com/A-z-exe"
EMAIL = "207771865+A-z-exe@users.noreply.github.com"


def read_version() -> str:
    for candidate in (Path("/usr/share/bbt-os/VERSION"), REPO_ROOT / "VERSION"):
        try:
            value = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    return "0.0.0"


VERSION = read_version()

CSS = b"""
window { background-color: #04080a; color: #d7fff1; }
headerbar { background: #07110f; border-bottom: 1px solid #145c4a; }
headerbar button { padding: 5px 12px; }
.title { color: #39ff14; font-family: monospace; font-weight: bold; font-size: 20px; }
.version { color: #22d3ee; font-family: monospace; font-size: 10px; }
.subtitle { color: #6fbfa8; font-family: monospace; font-size: 10px; }
button { background: #0a1815; border: 1px solid #145c4a; border-radius: 8px;
         padding: 8px 12px; color: #d7fff1; font-family: monospace; }
button:hover { border-color: #39ff14; background: #0f2622; }
entry { background: #07110f; color: #d7fff1; border: 1px solid #145c4a;
        border-radius: 6px; padding: 6px; font-family: monospace; }
combobox button { padding: 5px 8px; }
spinbutton { background: #07110f; color: #d7fff1; border: 1px solid #145c4a; }
checkbutton { font-family: monospace; color: #d7fff1; }
label.name { color: #d7fff1; font-family: monospace; font-weight: bold; font-size: 12px; }
label.desc { color: #6fbfa8; font-family: monospace; font-size: 9px; }
label.warn { color: #ffbd2e; font-family: monospace; font-size: 10px; }
label.ok { color: #39ff14; font-family: monospace; font-size: 10px; }
label.muted { color: #5f8f82; font-family: monospace; font-size: 10px; }
label.section { color: #22d3ee; font-family: monospace; font-weight: bold; font-size: 11px; }
button.tile { padding: 10px 12px; border-radius: 10px; }
button.tile:hover { background: #0d211d; border-color: #39ff14; }
flowbox { background: transparent; }
flowboxchild { background: transparent; padding: 0; }
list { background: #06100e; border: 1px solid #0d3b31; border-radius: 10px; }
list row { padding: 2px 6px; border-radius: 6px; }
list row:hover { background: #0d211d; }
list row:selected { background: #10352c; }
label.side { color: #9fe6cf; font-family: monospace; font-size: 11px; }
label.sidecount { color: #22d3ee; font-family: monospace; font-size: 9px; }
box.footer { background: #06100e; border-top: 1px solid #0d3b31; }
label.pill { font-family: monospace; font-size: 10px; color: #6fbfa8;
             background: #0a1815; border: 1px solid #145c4a;
             border-radius: 9px; padding: 2px 9px; }
label.pill-ok { color: #39ff14; border-color: #1f7a5c; }
label.pill-warn { color: #ffbd2e; border-color: #7a5c1f; }
"""

METHOD_LABELS = {
    "Auto (recommended)": "auto",
    "PMKID / SAE - hcxdumptool": "pmkid",
    "4-way handshake - aircrack-ng": "handshake",
    "WPS Pixie Dust - reaver": "wps",
    "WEP ARP replay - aircrack-ng": "wep",
}

METHOD_NOTES = {
    "pmkid": "hcxdumptool captures PMKID/SAE material passively; a client helps.",
    "handshake": "aircrack chain: monitor -> airodump -> handshake -> aircrack. Deauth only if you tick it.",
    "wps": "reaver PixieWPS with bully as fallback; only works on APs that advertise WPS.",
    "wep": "ARP replay then aircrack; the network must carry traffic.",
    "wep-none": "WEP is dead but recoverable when traffic exists.",
}

CATEGORY_ICONS = {
    "Web / Recon": "web",
    "Wireless": "wifi",
    "Android": "android",
    "Windows / AD": "windows",
    "Smart Card": "card",
    "System": "cpu",
    "Reporting": "doc",
    "Updates": "refresh",
}


# ---------------------------------------------------------------------------
# helpers
def which(tool: str) -> str | None:
    found = shutil.which(tool)
    if found:
        return found
    for directory in (HOME / ".local" / "bin", Path("/usr/local/bin")):
        candidate = directory / tool
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def icon_dirs() -> list[Path]:
    directories: list[Path] = []
    env = os.environ.get("BBT_OS_ICONS")
    if env:
        directories.append(Path(env))
    directories += [
        Path("/usr/share/bbt-os/icons"),
        REPO_ROOT / "assets" / "icons",
        HOME / ".local" / "share" / "bbt-os" / "icons",
    ]
    return [directory for directory in directories if directory.is_dir()]


def icon_pixbuf(name: str, size: int = 24) -> GdkPixbuf.Pixbuf | None:
    for directory in icon_dirs():
        path = directory / f"{name}.svg"
        if not path.is_file():
            continue
        try:
            return GdkPixbuf.Pixbuf.new_from_file_at_scale(
                str(path), size, size, True
            )
        except GLib.Error:
            continue
    return None


def icon_image(name: str, size: int = 24) -> Gtk.Image:
    pixbuf = icon_pixbuf(name, size)
    if pixbuf is not None:
        return Gtk.Image.new_from_pixbuf(pixbuf)
    return Gtk.Image.new_from_icon_name("utilities-terminal", Gtk.IconSize.DND)


def wireless_adapters() -> list[str]:
    adapters: list[str] = []
    net = Path("/sys/class/net")
    if net.is_dir():
        for entry in sorted(net.iterdir()):
            if (entry / "wireless").exists():
                adapters.append(entry.name)
    return adapters


def bbt_invocation() -> tuple[str, list[str]]:
    """Return (working directory, argv) for the BBT toolkit."""
    for repo in (HOME / "tools" / "BugBountyToolkit", Path("/opt/bbt-toolkit")):
        if (repo / "bbt").is_dir():
            for venv in (".venv-sys", ".venv", "venv"):
                python = repo / venv / "bin" / "python"
                if python.is_file():
                    return str(repo), [str(python), "-m", "bbt"]
            return str(repo), ["python3", "-m", "bbt"]
    exe = which("bbt")
    if exe:
        return str(HOME), [exe]
    return str(HOME), ["bbt"]


def terminal_command(title: str, command: str) -> list[str] | None:
    """Build a terminal invocation that keeps the window open after the command."""
    term = None
    flag = "-e"
    for candidate in ("x-terminal-emulator", "qterminal", "xfce4-terminal", "xterm"):
        path = which(candidate)
        if path:
            term = path
            if candidate == "xfce4-terminal":
                flag = "-x"
            break
    if not term:
        return None

    fd, runner = tempfile.mkstemp(prefix="bbt-os-run-", suffix=".sh")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write("#!/usr/bin/env bash\n")
        handle.write("set -uo pipefail\n")
        handle.write("trap 'rm -f -- \"$0\"' EXIT\n")
        handle.write('export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"\n')
        handle.write("clear 2>/dev/null || true\n")
        handle.write(f"printf '\\033[1;32m%s\\033[0m\\n\\n' {shlex.quote(title)}\n")
        handle.write(command + "\n")
        handle.write("\necho\nexec \"${SHELL:-/bin/bash}\" -i\n")
    os.chmod(runner, 0o700)
    return [term, flag, runner]


def launch_terminal(title: str, command: str, parent: Gtk.Window | None = None) -> None:
    argv = terminal_command(title, command)
    if not argv:
        show_error("No terminal emulator found.\nInstall qterminal, xfce4-terminal or xterm.", parent)
        return
    subprocess.Popen(argv, start_new_session=True)


def launch_gui(argv: list[str]) -> None:
    subprocess.Popen(
        argv,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def show_error(message: str, parent: Gtk.Window | None = None) -> None:
    dialog = Gtk.MessageDialog(
        transient_for=parent,
        modal=True,
        message_type=Gtk.MessageType.ERROR,
        buttons=Gtk.ButtonsType.CLOSE,
        text=message,
    )
    dialog.run()
    dialog.destroy()


def caption(text: str) -> Gtk.Label:
    label = Gtk.Label(label=text, xalign=0)
    label.get_style_context().add_class("muted")
    return label


def field_row(label_text: str, widget: Gtk.Widget, *extra: Gtk.Widget) -> Gtk.Box:
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    label = Gtk.Label(label=label_text, xalign=0)
    label.set_size_request(108, -1)
    label.get_style_context().add_class("muted")
    row.pack_start(label, False, False, 0)
    row.pack_start(widget, True, True, 0)
    for item in extra:
        row.pack_start(item, False, False, 0)
    return row


def valid_ssid(value: str) -> bool:
    return bool(re.fullmatch(r"[\x20-\x7e]{1,32}", value)) and not any(
        char in value for char in "*?"
    )


def valid_bssid(value: str) -> bool:
    return bool(re.fullmatch(r"([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", value))


def recommend_method(security: str, wps: int) -> tuple[str, str]:
    sec = (security or "").upper()
    if "WEP" in sec:
        return "wep", METHOD_NOTES["wep-none"]
    if "OPEN" in sec:
        return "open", "The network is open; there is no key to recover."
    if wps and which("reaver"):
        return "wps", METHOD_NOTES["wps"]
    if "SAE" in sec or "WPA3" in sec:
        if which("hcxdumptool") and which("hcxpcapngtool"):
            return "pmkid", "WPA3/SAE: hcxdumptool captures SAE/PMKID material. " + METHOD_NOTES["pmkid"]
        return "handshake", "No hcxdumptool; the aircrack chain needs a handshake."
    if which("hcxdumptool") and which("hcxpcapngtool"):
        return "pmkid", "hcxdumptool is preferred: PMKID needs no client reconnect."
    if which("aircrack-ng"):
        return "handshake", METHOD_NOTES["handshake"]
    return "none", "No compatible capture tool. Run bbt-os-doctor --fix."


def mark_missing(action: dict) -> str:
    tool = action.get("tool")
    if tool and not which(tool):
        return "  [not installed - run Refresh]"
    return ""


def load_cached_aps() -> list[dict]:
    cache = WIFI_DIR / "last-scan.tsv"
    rows: list[dict] = []
    try:
        lines = cache.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return rows
    for line in lines:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 8:
            continue
        bssid, ssid, channel, freq, band, signal, sec, wps = parts[:8]
        try:
            signal_value = int(signal)
        except ValueError:
            signal_value = -100
        rows.append(
            {
                "bssid": bssid,
                "ssid": ssid,
                "channel": channel,
                "freq": freq,
                "band": band,
                "signal": signal_value,
                "security": sec,
                "wps": 1 if wps in ("1", "yes", "true", "WPS") else 0,
            }
        )
    rows.sort(key=lambda item: item["signal"], reverse=True)
    return rows


# ---------------------------------------------------------------------------
# actions
def build_actions() -> list[dict]:
    actions: list[dict] = []
    _repo, bbt_argv = bbt_invocation()
    bbt_cmd = shlex.join(bbt_argv)

    def add(category, name, desc, command="", tool=None, gui=False,
            icon="terminal", keywords="", dialog=None, preset=""):
        actions.append(
            {
                "category": category,
                "name": name,
                "desc": desc,
                "command": command,
                "tool": tool,
                "gui": gui,
                "icon": icon,
                "keywords": keywords,
                "dialog": dialog,
                "preset": preset,
            }
        )

    # ---------------------------------------------------------------- Web
    add("Web / Recon", "BBT Auto Hunt",
        "Scope-gated -m auto run for one target",
        tool="bbt", icon="crosshair", dialog="hunt",
        keywords="bbt auto scan bug bounty")
    add("Web / Recon", "Recon workflow",
        "subfinder -> httpx -> katana -> nuclei, scope checked",
        tool="bbt-workflow", icon="radar", dialog="web",
        keywords="subfinder httpx katana nuclei pipeline workflow")
    add("Web / Recon", "WordPress workflow",
        "wpscan -> nuclei for an authorized WordPress site",
        tool="bbt-workflow", icon="puzzle", dialog="wordpress",
        keywords="wpscan wordpress wp plugin theme")
    add("Web / Recon", "httpx", "HTTP probing, titles, tech and status codes",
        "httpx -h 2>&1 | head -n 60", "httpx", icon="pulse",
        keywords="httpx http probe")
    add("Web / Recon", "nuclei", "Template-based vulnerability checks",
        "nuclei -h 2>&1 | head -n 60", "nuclei", icon="vuln",
        keywords="nuclei templates cve")
    add("Web / Recon", "ffuf", "Content and parameter discovery",
        "ffuf -h 2>&1 | head -n 60", "ffuf", icon="funnel",
        keywords="ffuf fuzz directory")
    add("Web / Recon", "katana", "JavaScript-aware crawling",
        "katana -h 2>&1 | head -n 60", "katana", icon="crawl",
        keywords="katana crawl spider")
    add("Web / Recon", "subfinder", "Passive subdomain enumeration",
        "subfinder -h 2>&1 | head -n 40", "subfinder", icon="net",
        keywords="subfinder subdomain recon")
    add("Web / Recon", "whatweb", "Fingerprint web technologies",
        "whatweb --help 2>&1 | head -n 40", "whatweb", icon="search",
        keywords="whatweb fingerprint tech")
    add("Web / Recon", "WPScan", "WordPress enumeration (authorized sites only)",
        "wpscan --help 2>&1 | head -n 50", "wpscan", icon="puzzle",
        keywords="wpscan wordpress")
    add("Web / Recon", "Nikto", "Web server misconfiguration checks",
        "nikto -Help 2>&1 | head -n 50", "nikto", icon="shieldscan",
        keywords="nikto server scan")
    add("Web / Recon", "sqlmap", "Injection verification only - stop after confirm",
        "sqlmap -h 2>&1 | head -n 50", "sqlmap", icon="db",
        keywords="sqlmap sql injection")

    # ----------------------------------------------------------- Wireless
    add("Wireless", "Wi-Fi capture + crack",
        "Pick a network, BBT chooses the best tool and runs it",
        tool="bbt-wifi", icon="wifi", dialog="wifi", preset="attack",
        keywords="wifi wireless wpa wpa2 wpa3 wep pmkid handshake wps crack")
    add("Wireless", "Scan networks",
        "Active scan, writes the AP cache used by the wizard",
        tool="bbt-wifi", icon="radar", dialog="wifi", preset="scan",
        keywords="wifi scan airodump access points")
    add("Wireless", "Adapter status",
        "Adapters, drivers, bands and monitor-mode support",
        tool="bbt-wifi", icon="radio", dialog="wifi", preset="status",
        keywords="wifi adapter monitor driver status")
    add("Wireless", "Crack a hash",
        "hashcat -m 22000 on a captured .22000 file",
        tool="bbt-wifi", icon="key", dialog="wifi", preset="crack",
        keywords="hashcat crack pmkid handshake 22000")
    add("Wireless", "Previous runs",
        "Open saved captures and summaries",
        tool="bbt-wifi", icon="folder", dialog="wifi", preset="captures",
        keywords="wifi runs captures history")
    add("Wireless", "Wireless doctor",
        "Check adapters, monitor mode and the wireless toolchain",
        tool="bbt-wifi", icon="pulse", dialog="wifi", preset="doctor",
        keywords="wifi doctor diagnose")

    # ------------------------------------------------------------- Android
    add("Android", "APK analysis pipeline",
        "apktool -> jadx -> endpoints and hard-coded secrets",
        tool="bbt-workflow", icon="android", dialog="android",
        keywords="apk android jadx apktool endpoints secrets")
    add("Android", "ADB devices", "List connected Android devices",
        "adb devices -l", "adb", icon="usb", keywords="adb android usb")
    add("Android", "Device recovery",
        "Lock state, data copy or lock removal on a phone you own",
        tool="bbt-android-recovery", icon="unlock", dialog="android_recovery",
        keywords="android recovery lock screen pin pattern unlock data copy phone")
    add("Android", "APK decompile (apktool)", "Choose an APK and decompile it",
        "", "apktool", icon="package", keywords="apk apktool decompile")
    add("Android", "APK open (JADX GUI)", "Choose an APK and open JADX GUI",
        "", "jadx-gui", gui=True, icon="code", keywords="apk jadx decompile gui")
    add("Android", "APK to JAR (dex2jar)", "Choose an APK and convert its classes to a JAR",
        "", "d2j-dex2jar", icon="package", keywords="apk dex2jar jar classes")
    add("Android", "Frida processes", "List processes on the USB device",
        "frida-ps -U", "frida-ps", icon="hook", keywords="frida hook instrumentation")
    add("Android", "Objection", "Runtime mobile exploration help",
        "objection --help 2>&1 | head -n 50", "objection", icon="terminal")
    add("Android", "Scrcpy", "Mirror and control the Android device",
        "", "scrcpy", gui=True, icon="phone", keywords="scrcpy screen mirror")
    add("Android", "Start MobSF", "Run MobSF in Docker on port 8000 (first run pulls the image)",
        "mobsf start", "docker", icon="server", keywords="mobsf apk static analysis docker")
    add("Android", "Stop MobSF", "Stop the MobSF container",
        "mobsf stop", "docker", icon="stop", keywords="mobsf stop docker")
    add("Android", "MobSF logs", "Follow the MobSF container log",
        "mobsf logs", "docker", icon="logs", keywords="mobsf logs docker")
    add("Android", "Open MobSF UI", "Open http://127.0.0.1:8000 in the browser",
        "", None, gui=True, icon="web", keywords="mobsf browser")

    # --------------------------------------------------------- Windows / AD
    add("Windows / AD", "AD workflow",
        "nmap DC ports -> enum4linux-ng, passive and scope checked",
        tool="bbt-workflow", icon="windows", dialog="ad",
        keywords="active directory ad dc domain controller nmap enum4linux")
    add("Windows / AD", "NetExec", "SMB/WinRM/LDAP assessment help (authorized AD only)",
        "netexec --help 2>&1 | head -n 60", "netexec", icon="server",
        keywords="netexec smb ldap ad")
    add("Windows / AD", "Impacket", "List installed Impacket example tools",
        "compgen -c | grep '^impacket-' | sort -u | head -n 40", "python3",
        icon="terminal", keywords="impacket smb secretsdump")
    add("Windows / AD", "Evil-WinRM", "WinRM shell help (authorized hosts only)",
        "evil-winrm -h 2>&1 | head -n 50", "evil-winrm", icon="terminal")
    add("Windows / AD", "Responder", "LLMNR/NBT-NS/MDNS poisoning help (lab/authorized only)",
        "sudo responder -h 2>&1 | head -n 50", "responder", icon="radio")
    add("Windows / AD", "Enum4linux-ng", "SMB/NetBIOS enumeration",
        "enum4linux-ng -h 2>&1 | head -n 50", "enum4linux-ng", icon="net")
    add("Windows / AD", "BloodHound.py", "AD collection help",
        "bloodhound-python -h 2>&1 | head -n 50", "bloodhound-python", icon="graph")

    # ----------------------------------------------------------- Smart Card
    add("Smart Card", "Reader status", "PC/SC readers, ATR and card status",
        "bbt-smartcard status", "pcsc_scan", icon="card",
        keywords="smart card pcsc reader atr nfc chip")
    add("Smart Card", "Read chip info", "ATR, card name, protocols and algorithms",
        "bbt-smartcard info", "opensc-tool", icon="chip",
        keywords="smart card chip information atr opensc")
    add("Smart Card", "Certificates (PIV/PKCS#15)", "List certificates stored on the card",
        "bbt-smartcard certs", "pkcs15-tool", icon="cert",
        keywords="piv pkcs15 certificate smartcard")
    add("Smart Card", "NFC tag scan", "List NFC targets in the field",
        "bbt-smartcard nfc-scan", "nfc-list", icon="nfc",
        keywords="nfc rfid tag scan libnfc")
    add("Smart Card", "Read NDEF tag", "Read an NDEF message from a MIFARE Classic tag",
        "bbt-smartcard ndef-read", "mifare-classic-read-ndef", icon="reader",
        keywords="ndef nfc mifare tag read")
    add("Smart Card", "Write NDEF tag", "Write a message to a MIFARE tag (confirmation required)",
        "bbt-smartcard ndef-write", "mifare-classic-write-ndef", icon="edit",
        keywords="ndef nfc mifare write edit tag")
    add("Smart Card", "MIFARE dump", "Recover keys and dump a MIFARE Classic tag (confirmation required)",
        "bbt-smartcard mifare-dump", "mfoc", icon="key",
        keywords="mfoc mifare dump keys tag")
    add("Smart Card", "Send APDU", "Send one raw APDU to the card (confirmation required)",
        "bbt-smartcard apdu", "opensc-tool", icon="code",
        keywords="apdu iso7816 smartcard command")

    # -------------------------------------------------------------- System
    add("System", "Kernel report", "Running kernel, headers and module status",
        "uname -a; echo; ls -1 /lib/modules; echo; "
        "dpkg -l 'linux-headers-*' 2>/dev/null | awk '/^ii/{print $2, $3}'",
        icon="cpu", keywords="kernel headers uname modules")
    add("System", "Hardware inventory", "CPU, USB and PCI devices",
        "lscpu | head -n 25; echo; lsusb; echo; lspci | head -n 30",
        icon="chip", keywords="hardware cpu usb pci lsusb lspci")
    add("System", "Network interfaces", "Links and NetworkManager device state",
        "ip -br address; echo; nmcli device status 2>/dev/null || true",
        icon="net", keywords="network interface ip address nmcli")
    add("System", "Running services", "Active systemd services",
        "systemctl --no-pager --type=service --state=running | head -n 40",
        icon="gear", keywords="services systemd status")
    add("System", "Health doctor", "Full BBT OS audit with a fix option",
        "bbt-os-doctor", "bbt-os-doctor", icon="pulse",
        keywords="doctor health audit diagnose fix")

    # ----------------------------------------------------------- Reporting
    add("Reporting", "BBT help", "Show every BBT mode and option",
        f"{bbt_cmd} --help 2>&1 | head -n 80", icon="terminal",
        keywords="bbt help usage")
    add("Reporting", "Edit scope file", "Create or edit ~/scope.txt",
        f"mkdir -p {shlex.quote(str(HOME))} && "
        f"[ -f {shlex.quote(str(SCOPE_FILE))} ] || "
        f"printf '# one host/domain/URL/CIDR per line\\n' > {shlex.quote(str(SCOPE_FILE))}; "
        f"${{EDITOR:-nano}} {shlex.quote(str(SCOPE_FILE))}", icon="edit",
        keywords="scope authorization target list")
    add("Reporting", "Open BBT results", "Open the toolkit results directory",
        f"mkdir -p {shlex.quote(str(HOME / 'tools' / 'BugBountyToolkit' / 'results'))} && "
        f"xdg-open {shlex.quote(str(HOME / 'tools' / 'BugBountyToolkit' / 'results'))}",
        gui=True, icon="folder")
    add("Reporting", "Open workflow runs", "subfinder/nuclei/apktool reports",
        f"mkdir -p {shlex.quote(str(RUNS_DIR))} && xdg-open {shlex.quote(str(RUNS_DIR))}",
        gui=True, icon="folder", keywords="runs reports workflow")
    add("Reporting", "Open wireless runs", "Captures, summaries and recovered keys",
        f"mkdir -p {shlex.quote(str(WIFI_DIR))} && xdg-open {shlex.quote(str(WIFI_DIR))}",
        gui=True, icon="folder", keywords="wifi captures runs")
    add("Reporting", "Open recon files", "Open ~/bbt/recon",
        f"mkdir -p {shlex.quote(str(RECON_DIR))} && xdg-open {shlex.quote(str(RECON_DIR))}",
        gui=True, icon="folder")

    # -------------------------------------------------------------- Updates
    add("Updates", "Refresh BBT OS", "apt update, tool updates and database refresh",
        "sudo bbt-os-refresh", icon="refresh", keywords="update upgrade refresh")
    add("Updates", "Update nuclei templates", "Download the latest nuclei templates",
        "nuclei -update-templates", "nuclei", icon="download")
    add("Updates", "Update BBT toolkit", "git pull and reinstall the Python package",
        "", "git", icon="download", keywords="bbt update git")
    add("Updates", "System upgrade", "apt update && apt full-upgrade",
        "sudo apt update && sudo apt full-upgrade -y", icon="refresh")

    return actions


# ---------------------------------------------------------------------------
# window
class BBTWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="BBT OS")
        self.set_default_size(1220, 780)
        self.set_border_width(0)
        self.actions = build_actions()
        self.selected_category = ""

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.build_header()

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        body.set_border_width(10)

        body.pack_start(self.build_sidebar(), False, False, 0)
        body.pack_start(self.build_main(), True, True, 0)
        outer.pack_start(body, True, True, 0)
        outer.pack_start(self.build_footer(), False, False, 0)
        self.add(outer)

        self.rebuild_tiles()
        self.connect("destroy", Gtk.main_quit)
        self.show_all()

    # -- header
    def build_header(self) -> None:
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.props.title = "BBT OS"
        header.props.subtitle = "bug bounty console"

        title_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        logo = icon_image("terminal", 26)
        title_box.pack_start(logo, False, False, 0)
        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        title = Gtk.Label(label="BBT OS", xalign=0)
        title.get_style_context().add_class("title")
        subtitle = Gtk.Label(
            label=f"v{VERSION}  -  web / wireless / android / windows", xalign=0
        )
        subtitle.get_style_context().add_class("subtitle")
        text_box.pack_start(title, False, False, 0)
        text_box.pack_start(subtitle, False, False, 0)
        title_box.pack_start(text_box, False, False, 0)
        header.set_custom_title(title_box)

        doctor = Gtk.Button(label="Doctor")
        doctor.set_tooltip_text("Audit kernel, adapters and tools")
        doctor.connect("clicked", lambda _b: self.run_doctor())
        about = Gtk.Button(label="About")
        about.connect("clicked", self.on_about)
        header.pack_end(about)
        header.pack_end(doctor)
        self.set_titlebar(header)

    # -- sidebar
    def build_sidebar(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_size_request(208, -1)

        heading = Gtk.Label(label="// MODULES", xalign=0)
        heading.get_style_context().add_class("section")
        box.pack_start(heading, False, False, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.set_activate_on_single_click(True)
        self.listbox.connect("row-selected", self.on_category)

        categories: list[str] = []
        for action in self.actions:
            if action["category"] not in categories:
                categories.append(action["category"])
        counts = {name: 0 for name in categories}
        for action in self.actions:
            counts[action["category"]] += 1

        self.add_sidebar_row("", "All modules", len(self.actions))
        for category in categories:
            self.add_sidebar_row(category, category, counts[category])

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.add(self.listbox)
        box.pack_start(scroller, True, True, 0)

        adapters = wireless_adapters()
        hint = Gtk.Label(
            label=(
                "Adapter: " + ", ".join(adapters)
                if adapters
                else "No Wi-Fi adapter\n(VM: attach USB first)"
            ),
            xalign=0,
        )
        hint.set_line_wrap(True)
        hint.get_style_context().add_class("ok" if adapters else "warn")
        box.pack_start(hint, False, False, 4)
        return box

    def add_sidebar_row(self, category: str, label_text: str, count: int) -> None:
        row = Gtk.ListBoxRow()
        row.category = category
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=7)
        box.set_border_width(4)
        icon_name = CATEGORY_ICONS.get(category, "terminal")
        box.pack_start(icon_image(icon_name, 18), False, False, 0)
        label = Gtk.Label(label=label_text, xalign=0)
        label.get_style_context().add_class("side")
        label.set_ellipsize(3)
        box.pack_start(label, True, True, 0)
        counter = Gtk.Label(label=str(count))
        counter.get_style_context().add_class("sidecount")
        box.pack_end(counter, False, False, 0)
        row.add(box)
        self.listbox.add(row)

    def on_category(self, _listbox: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        self.selected_category = getattr(row, "category", "") if row else ""
        self.rebuild_tiles()

    # -- main pane
    def build_main(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_hexpand(True)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Search modules, tools or keywords...")
        self.search.set_hexpand(True)
        self.search.connect("search-changed", lambda _e: self.rebuild_tiles())
        bar.pack_start(self.search, True, True, 0)
        refresh = Gtk.Button(label="Reload")
        refresh.set_tooltip_text("Rediscover installed tools and adapters")
        refresh.connect("clicked", self.on_reload)
        bar.pack_start(refresh, False, False, 0)
        box.pack_start(bar, False, False, 0)

        self.flow = Gtk.FlowBox()
        self.flow.set_selection_mode(Gtk.SelectionMode.NONE)
        self.flow.set_activate_on_single_click(True)
        self.flow.set_homogeneous(True)
        self.flow.set_row_spacing(8)
        self.flow.set_column_spacing(8)
        self.flow.set_min_children_per_line(1)
        self.flow.set_max_children_per_line(4)
        self.flow.set_valign(Gtk.Align.START)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_hexpand(True)
        scroller.set_vexpand(True)
        scroller.add(self.flow)
        box.pack_start(scroller, True, True, 0)

        self.empty = Gtk.Label(label="No module matches this search.")
        self.empty.get_style_context().add_class("muted")
        self.empty.set_no_show_all(True)
        box.pack_start(self.empty, False, False, 0)
        return box

    def build_footer(self) -> Gtk.Widget:
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        footer.get_style_context().add_class("footer")
        footer.set_border_width(7)

        tools = {action["tool"] for action in self.actions if action.get("tool")}
        present = sum(1 for tool in tools if which(tool))
        adapters = wireless_adapters()

        kernel = platform.release() or "unknown"
        pills = [
            (f"kernel {kernel}", True),
            (
                f"wifi {len(adapters)} adapter" + ("" if len(adapters) == 1 else "s"),
                bool(adapters),
            ),
            ("pcsc ready" if which("pcsc_scan") else "pcsc missing", bool(which("pcsc_scan"))),
            (f"tools {present}/{len(tools)}", present == len(tools)),
        ]
        for text, ok in pills:
            label = Gtk.Label(label=text)
            label.get_style_context().add_class("pill")
            label.get_style_context().add_class("pill-ok" if ok else "pill-warn")
            footer.pack_start(label, False, False, 0)

        note = Gtk.Label(label="authorized targets only", xalign=1)
        note.get_style_context().add_class("warn")
        footer.pack_end(note, False, False, 0)
        footer.pack_end(Gtk.Label(label=""), True, True, 0)
        return footer

    # -- tiles
    def rebuild_tiles(self) -> None:
        for child in self.flow.get_children():
            self.flow.remove(child)

        needle = self.search.get_text().strip().lower() if hasattr(self, "search") else ""
        shown = 0
        for action in self.actions:
            if self.selected_category and action["category"] != self.selected_category:
                continue
            haystack = " ".join(
                [action["category"], action["name"], action["desc"], action["keywords"]]
            ).lower()
            if needle and needle not in haystack:
                continue
            self.flow.add(self.make_tile(action))
            shown += 1

        if hasattr(self, "empty"):
            self.empty.set_visible(shown == 0)
        self.flow.show_all()

    def make_tile(self, action: dict) -> Gtk.Widget:
        button = Gtk.Button()
        button.get_style_context().add_class("tile")
        button.set_size_request(268, 72)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        icon = icon_image(action["icon"], 28)
        icon.set_valign(Gtk.Align.START)
        icon.set_margin_top(2)
        box.pack_start(icon, False, False, 0)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        name = Gtk.Label(label=action["name"], xalign=0)
        name.get_style_context().add_class("name")
        name.set_ellipsize(3)
        desc = Gtk.Label(label=action["desc"] + mark_missing(action), xalign=0)
        desc.get_style_context().add_class("desc")
        desc.set_line_wrap(True)
        desc.set_max_width_chars(34)
        desc.set_lines(2)
        desc.set_ellipsize(3)
        text_box.pack_start(name, False, False, 0)
        text_box.pack_start(desc, False, False, 0)
        box.pack_start(text_box, True, True, 0)

        button.add(box)
        button.set_tooltip_text(f"{action['name']}\n{action['desc']}")
        button.connect("clicked", self.on_action, action)
        return button

    def on_reload(self, _button: Gtk.Button) -> None:
        self.actions = build_actions()
        self.rebuild_tiles()

    # -- dispatch
    def on_action(self, _button: Gtk.Button, action: dict) -> None:
        dialog = action.get("dialog")
        if dialog == "hunt":
            self.dialog_hunt()
        elif dialog == "web":
            self.dialog_web()
        elif dialog == "wordpress":
            self.dialog_wordpress()
        elif dialog == "ad":
            self.dialog_ad()
        elif dialog == "android":
            self.dialog_android()
        elif dialog == "android_recovery":
            self.dialog_android_recovery()
        elif dialog == "wifi":
            self.dialog_wifi(action.get("preset", "attack"))
        elif action["name"] == "APK decompile (apktool)":
            apk = self.choose_apk()
            if apk:
                out = apk[:-4] + "_apktool" if apk.lower().endswith(".apk") else apk + "_apktool"
                launch_terminal(
                    f"apktool: {Path(apk).name}",
                    f"apktool d -f {shlex.quote(apk)} -o {shlex.quote(out)}",
                    self,
                )
        elif action["name"] == "APK open (JADX GUI)":
            apk = self.choose_apk()
            if apk:
                launch_gui(["jadx-gui", apk])
        elif action["name"] == "APK to JAR (dex2jar)":
            apk = self.choose_apk()
            if apk:
                out = apk[:-4] + ".jar" if apk.lower().endswith(".apk") else apk + ".jar"
                launch_terminal(
                    f"dex2jar: {Path(apk).name}",
                    f"d2j-dex2jar -f -o {shlex.quote(out)} {shlex.quote(apk)}",
                    self,
                )
        elif action["name"] == "Scrcpy":
            launch_gui(["scrcpy"])
        elif action["name"] == "Open MobSF UI":
            launch_gui(["xdg-open", "http://127.0.0.1:8000"])
        elif action["name"] == "Update BBT toolkit":
            self.update_bbt()
        elif action["command"]:
            if action.get("gui"):
                launch_gui(["bash", "-c", action["command"]])
            else:
                launch_terminal(action["name"], action["command"], self)

    def run_doctor(self) -> None:
        if not which("bbt-os-doctor"):
            show_error(
                "The doctor is not installed yet.\n\nRun: sudo bbt-os-refresh --no-upgrade",
                self,
            )
            return
        launch_terminal("BBT OS doctor", "sudo bbt-os-doctor", self)

    def update_bbt(self) -> None:
        repo, _argv = bbt_invocation()
        if not (Path(repo) / ".git").is_dir():
            show_error("BBT is not a git checkout, so it cannot be updated this way.", self)
            return
        command = (
            f"cd {shlex.quote(repo)} && git pull --ff-only && "
            ".venv-sys/bin/pip install -e . && bbt --version"
        )
        launch_terminal("Update BBT toolkit", command, self)

    def choose_apk(self) -> str | None:
        dialog = Gtk.FileChooserDialog(
            title="Select an APK", parent=self, action=Gtk.FileChooserAction.OPEN
        )
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK)
        file_filter = Gtk.FileFilter()
        file_filter.set_name("Android packages (*.apk)")
        file_filter.add_pattern("*.apk")
        dialog.add_filter(file_filter)
        response = dialog.run()
        path = dialog.get_filename()
        dialog.destroy()
        return path if response == Gtk.ResponseType.OK else None

    # -- web dialogs
    def dialog_hunt(self) -> None:
        repo, argv = bbt_invocation()
        dialog = Gtk.Dialog(title="BBT Auto Hunt", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run hunt", Gtk.ResponseType.OK)
        dialog.set_default_size(560, 300)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)

        target = Gtk.Entry()
        target.set_placeholder_text("https://app.example.com")
        scope = Gtk.Entry()
        scope.set_text(str(SCOPE_FILE))
        deep = Gtk.CheckButton(label="Deep scan (katana, ffuf, nikto, subfinder)")
        auth = Gtk.CheckButton(label="I have written authorization for this target")

        box.pack_start(caption("Target URL"), False, False, 0)
        box.pack_start(target, False, False, 0)
        box.pack_start(caption("Scope file"), False, False, 0)
        box.pack_start(scope, False, False, 0)
        box.pack_start(deep, False, False, 0)
        box.pack_start(auth, False, False, 0)

        hint = Gtk.Label(
            label=f"Toolkit: {repo}\nRuns -m auto --authorized and refuses targets outside the scope file.",
            xalign=0,
        )
        hint.get_style_context().add_class("muted")
        box.pack_start(hint, False, False, 0)
        dialog.show_all()
        response = dialog.run()
        values = (
            target.get_text().strip(),
            scope.get_text().strip(),
            deep.get_active(),
            auth.get_active(),
        )
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        url, scope_path, deep_flag, authorized = values
        if not re.match(r"^https?://", url):
            show_error("Enter a full http:// or https:// target URL.", self)
            return
        if not os.path.isfile(scope_path):
            show_error(
                f"Scope file not found:\n{scope_path}\n\nCreate it with Reporting > Edit scope file.",
                self,
            )
            return
        if not authorized:
            show_error("Tick the authorization checkbox first.", self)
            return
        command = (
            f"cd {shlex.quote(repo)} && {shlex.join(argv)} "
            f"-t {shlex.quote(url)} -m auto --authorized "
            f"--scope-file {shlex.quote(scope_path)}"
        )
        if deep_flag:
            command += " --deep"
        launch_terminal("BBT auto hunt", command, self)

    def dialog_web(self) -> None:
        if not which("bbt-workflow"):
            show_error("bbt-workflow is not installed.\n\nRun: sudo bbt-os-refresh --no-upgrade", self)
            return
        dialog = Gtk.Dialog(title="Recon workflow", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run", Gtk.ResponseType.OK)
        dialog.set_default_size(540, 260)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)

        target = Gtk.Entry()
        target.set_placeholder_text("example.com or https://app.example.com")
        scope = Gtk.Entry()
        scope.set_text(str(SCOPE_FILE))
        deep = Gtk.CheckButton(label="Deep scan (katana + nuclei fuzzing templates)")
        auth = Gtk.CheckButton(label="I have written authorization for this target")

        box.pack_start(caption("Target"), False, False, 0)
        box.pack_start(target, False, False, 0)
        box.pack_start(caption("Scope file"), False, False, 0)
        box.pack_start(scope, False, False, 0)
        box.pack_start(deep, False, False, 0)
        box.pack_start(auth, False, False, 0)
        note = Gtk.Label(
            label="Chain: subfinder -> httpx -> katana -> nuclei, every host checked against the scope file.",
            xalign=0,
        )
        note.set_line_wrap(True)
        note.get_style_context().add_class("muted")
        box.pack_start(note, False, False, 0)

        dialog.show_all()
        response = dialog.run()
        values = (
            target.get_text().strip(),
            scope.get_text().strip(),
            deep.get_active(),
            auth.get_active(),
        )
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        value, scope_path, deep_flag, authorized = values
        if not re.fullmatch(r"[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+", value):
            show_error("Enter a domain or URL such as example.com.", self)
            return
        if not os.path.isfile(scope_path):
            show_error(f"Scope file not found:\n{scope_path}", self)
            return
        if not authorized:
            show_error("Tick the authorization checkbox first.", self)
            return
        argv = ["bbt-workflow", "web", "--target", value, "--scope", scope_path, "--authorized"]
        if deep_flag:
            argv.append("--deep")
        launch_terminal("Recon workflow", shlex.join(argv), self)

    def dialog_wordpress(self) -> None:
        if not which("bbt-workflow"):
            show_error("bbt-workflow is not installed.\n\nRun: sudo bbt-os-refresh --no-upgrade", self)
            return
        dialog = Gtk.Dialog(title="WordPress workflow", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run", Gtk.ResponseType.OK)
        dialog.set_default_size(540, 230)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)

        url = Gtk.Entry()
        url.set_placeholder_text("https://blog.example.com")
        scope = Gtk.Entry()
        scope.set_text(str(SCOPE_FILE))
        auth = Gtk.CheckButton(label="I have written authorization for this site")
        box.pack_start(caption("WordPress URL"), False, False, 0)
        box.pack_start(url, False, False, 0)
        box.pack_start(caption("Scope file"), False, False, 0)
        box.pack_start(scope, False, False, 0)
        box.pack_start(auth, False, False, 0)
        note = Gtk.Label(label="Chain: wpscan (plugins, themes, users) -> nuclei wordpress tags.", xalign=0)
        note.get_style_context().add_class("muted")
        box.pack_start(note, False, False, 0)

        dialog.show_all()
        response = dialog.run()
        values = (url.get_text().strip(), scope.get_text().strip(), auth.get_active())
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        link, scope_path, authorized = values
        if not re.match(r"^https?://[A-Za-z0-9.-]+", link):
            show_error("Enter a full http:// or https:// URL.", self)
            return
        if not os.path.isfile(scope_path):
            show_error(f"Scope file not found:\n{scope_path}", self)
            return
        if not authorized:
            show_error("Tick the authorization checkbox first.", self)
            return
        launch_terminal(
            "WordPress workflow",
            shlex.join(["bbt-workflow", "wordpress", "--url", link,
                        "--scope", scope_path, "--authorized"]),
            self,
        )

    def dialog_ad(self) -> None:
        if not which("bbt-workflow"):
            show_error("bbt-workflow is not installed.\n\nRun: sudo bbt-os-refresh --no-upgrade", self)
            return
        dialog = Gtk.Dialog(title="Active Directory workflow", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run", Gtk.ResponseType.OK)
        dialog.set_default_size(540, 260)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)

        dc = Gtk.Entry()
        dc.set_placeholder_text("10.0.0.10")
        domain = Gtk.Entry()
        domain.set_placeholder_text("corp.local")
        scope = Gtk.Entry()
        scope.set_text(str(SCOPE_FILE))
        auth = Gtk.CheckButton(label="I have written authorization for this domain")

        box.pack_start(caption("Domain controller"), False, False, 0)
        box.pack_start(dc, False, False, 0)
        box.pack_start(caption("AD domain"), False, False, 0)
        box.pack_start(domain, False, False, 0)
        box.pack_start(caption("Scope file"), False, False, 0)
        box.pack_start(scope, False, False, 0)
        box.pack_start(auth, False, False, 0)
        note = Gtk.Label(
            label="Chain: nmap DC ports -> enum4linux-ng. Passive checks only, no credential attacks.",
            xalign=0,
        )
        note.set_line_wrap(True)
        note.get_style_context().add_class("muted")
        box.pack_start(note, False, False, 0)

        dialog.show_all()
        response = dialog.run()
        values = (
            dc.get_text().strip(),
            domain.get_text().strip(),
            scope.get_text().strip(),
            auth.get_active(),
        )
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        dc_value, domain_value, scope_path, authorized = values
        if not re.fullmatch(r"[A-Za-z0-9.:-]+", dc_value):
            show_error("Enter the DC IP address or hostname.", self)
            return
        if not re.fullmatch(r"[A-Za-z0-9.-]+\.[A-Za-z]{2,}", domain_value):
            show_error("Enter the AD domain, for example corp.local.", self)
            return
        if not os.path.isfile(scope_path):
            show_error(f"Scope file not found:\n{scope_path}", self)
            return
        if not authorized:
            show_error("Tick the authorization checkbox first.", self)
            return
        launch_terminal(
            "AD workflow",
            shlex.join(["bbt-workflow", "ad", "--dc", dc_value, "--domain", domain_value,
                        "--scope", scope_path, "--authorized"]),
            self,
        )

    def dialog_android(self) -> None:
        if not which("bbt-workflow"):
            show_error("bbt-workflow is not installed.\n\nRun: sudo bbt-os-refresh --no-upgrade", self)
            return
        apk = self.choose_apk()
        if not apk:
            return
        launch_terminal(
            f"APK pipeline: {Path(apk).name}",
            shlex.join(["bbt-workflow", "android", "--apk", apk]),
            self,
        )

    def dialog_android_recovery(self) -> None:
        if not which("bbt-android-recovery"):
            show_error(
                "The device recovery helper is not installed.\n\n"
                "Run: sudo bbt-os-refresh --no-upgrade",
                self,
            )
            return
        dialog = Gtk.Dialog(title="Device recovery", transient_for=self, modal=True)
        dialog.add_buttons(
            "Close", Gtk.ResponseType.CLOSE,
            "Status", 10,
            "Plan", 11,
            "Copy data", 12,
            "Remove lock", 13,
            "Linux phone", 14,
        )
        dialog.set_default_size(600, -1)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        intro = Gtk.Label(
            label=(
                "Non-destructive first. The helper never wipes, flashes or unlocks a bootloader.\n"
                "Removing a lock without data loss works only when ADB is already authorized "
                "and root is available. Otherwise use the vendor or the Linux-phone steps."
            ),
            xalign=0,
        )
        intro.set_line_wrap(True)
        box.pack_start(intro, False, False, 0)
        rule = Gtk.Label(
            label="Only for devices you own or have written authorization to service.",
            xalign=0,
        )
        rule.set_line_wrap(True)
        rule.get_style_context().add_class("warn")
        box.pack_start(rule, False, False, 0)
        dialog.show_all()
        response = dialog.run()
        dialog.destroy()
        if response == 10:
            launch_terminal("Android device status", "bbt-android-recovery status", self)
        elif response == 11:
            launch_terminal("Android lock plan", "bbt-android-recovery plan", self)
        elif response == 12:
            self.dialog_android_pull()
        elif response == 13:
            self.dialog_android_unlock()
        elif response == 14:
            launch_terminal("Linux phone recovery", "bbt-android-recovery linux", self)

    def dialog_android_pull(self) -> None:
        dialog = Gtk.Dialog(title="Copy device data", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Start", Gtk.ResponseType.OK)
        dialog.set_default_size(620, -1)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        note = Gtk.Label(
            label=(
                "Copies photos, downloads and documents from an authorized device. "
                "Private app data stays encrypted and is not included."
            ),
            xalign=0,
        )
        note.set_line_wrap(True)
        note.get_style_context().add_class("muted")
        box.pack_start(note, False, False, 0)
        dest_entry = Gtk.Entry()
        dest_entry.set_text(
            str(HOME / "bbt" / "android" / f"backup-{time.strftime('%Y%m%d-%H%M%S')}")
        )
        box.pack_start(field_row("Destination", dest_entry), False, False, 0)
        owned = Gtk.CheckButton(
            label="I own this device or have written authorization to copy its data"
        )
        box.pack_start(owned, False, False, 0)
        dialog.show_all()
        response = dialog.run()
        dest = os.path.expanduser(dest_entry.get_text().strip())
        consent = owned.get_active()
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        if not dest:
            show_error("Choose a destination directory.", self)
            return
        if not consent:
            show_error("Tick the ownership checkbox first.", self)
            return
        launch_terminal(
            "Android data copy",
            shlex.join(["bbt-android-recovery", "pull", "--dest", dest,
                        "--i-own-this-device"]),
            self,
        )

    def dialog_android_unlock(self) -> None:
        dialog = Gtk.Dialog(title="Remove screen lock", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Remove lock", Gtk.ResponseType.OK)
        dialog.set_default_size(600, -1)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        warning = Gtk.Label(
            label=(
                "Only works when the phone is already rooted and ADB is authorized. "
                "The credential is cleared with locksettings and user data is kept. "
                "A locked bootloader cannot be bypassed here."
            ),
            xalign=0,
        )
        warning.set_line_wrap(True)
        warning.get_style_context().add_class("warn")
        box.pack_start(warning, False, False, 0)
        serial_entry = Gtk.Entry()
        serial_entry.set_placeholder_text("serial from adb devices (optional)")
        box.pack_start(field_row("Serial", serial_entry), False, False, 0)
        owned = Gtk.CheckButton(
            label="I own this device or have written authorization to service it"
        )
        box.pack_start(owned, False, False, 0)
        dialog.show_all()
        response = dialog.run()
        serial = serial_entry.get_text().strip()
        consent = owned.get_active()
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        if serial and not re.fullmatch(r"[A-Za-z0-9._:-]{1,64}", serial):
            show_error("Serial looks invalid. Copy it from adb devices.", self)
            return
        if not consent:
            show_error("Tick the ownership checkbox first.", self)
            return
        confirm = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Clear the screen lock on this device?",
        )
        confirm.format_secondary_text(
            "User data stays in place. Continue only for a device you own."
        )
        approved = confirm.run() == Gtk.ResponseType.YES
        confirm.destroy()
        if not approved:
            return
        command = ["bbt-android-recovery", "unlock", "--i-own-this-device"]
        if serial:
            command += ["--serial", serial]
        launch_terminal("Remove Android lock", shlex.join(command), self)

    # -- wireless
    def dialog_wifi(self, preset: str) -> None:
        if preset == "crack":
            self.dialog_crack()
            return
        if not which("bbt-wifi"):
            show_error(
                "The wireless engine is not installed.\n\nRun: sudo bbt-os-refresh --no-upgrade",
                self,
            )
            return
        if preset in ("status", "scan", "captures", "doctor"):
            details = {
                "status": ("Wireless status", "Adapters, drivers, bands and monitor-mode support."),
                "scan": ("Scan networks", "Active scan; writes the cache used by the Wi-Fi wizard."),
                "captures": ("Previous runs", "Saved captures, summaries and history."),
                "doctor": ("Wireless doctor", "Checks adapters and the capture/crack toolchain."),
            }
            title, detail = details[preset]
            dialog = Gtk.Dialog(title=title, transient_for=self, modal=True)
            dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK)
            box = dialog.get_content_area()
            box.set_spacing(8)
            box.set_border_width(14)
            label = Gtk.Label(label=detail, xalign=0)
            label.set_line_wrap(True)
            label.get_style_context().add_class("muted")
            box.pack_start(label, False, False, 0)
            adapters = wireless_adapters()
            state = Gtk.Label(
                label=("Adapters: " + ", ".join(adapters)) if adapters
                else "No wireless adapter detected. In a VM attach the USB adapter first.",
                xalign=0,
            )
            state.set_line_wrap(True)
            state.get_style_context().add_class("ok" if adapters else "warn")
            box.pack_start(state, False, False, 0)
            dialog.show_all()
            response = dialog.run()
            dialog.destroy()
            if response != Gtk.ResponseType.OK:
                return
            launch_terminal(title, f"bbt-wifi {preset}", self)
            return

        self.dialog_wifi_attack()

    def dialog_wifi_attack(self) -> None:
        dialog = Gtk.Dialog(title="Wi-Fi capture and crack", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Start", Gtk.ResponseType.OK)
        dialog.set_default_size(660, 560)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)

        adapters = wireless_adapters()
        banner = Gtk.Label(
            label=("Adapter: " + ", ".join(adapters)) if adapters else
            "No wireless adapter detected. Attach the USB adapter (VM > Removable Devices) "
            "and run rfkill unblock wifi, then reopen this window.",
            xalign=0,
        )
        banner.set_line_wrap(True)
        banner.get_style_context().add_class("ok" if adapters else "warn")
        box.pack_start(banner, False, False, 0)

        model = Gtk.ListStore(str, str, str, str, str, int)
        for ap in load_cached_aps():
            ssid = ap["ssid"] or "(hidden SSID)"
            label = (
                f"{ssid}  -  {ap['signal']} dBm  -  ch {ap['channel']}  -  "
                f"{ap['security'] or '?'}" + ("  + WPS" if ap["wps"] else "")
            )
            model.append([label, ap["ssid"], ap["bssid"], ap["channel"],
                          ap["security"], ap["wps"]])

        combo = Gtk.ComboBox.new_with_model(model)
        renderer = Gtk.CellRendererText()
        combo.pack_start(renderer, True)
        combo.add_attribute(renderer, "text", 0)
        combo.set_hexpand(True)
        if len(model):
            combo.set_active(0)

        reload_btn = Gtk.Button(label="Reload")
        reload_btn.set_tooltip_text("Reload the cached scan (bbt-wifi scan refreshes it)")
        refresh_btn = Gtk.Button(label="Scan")
        refresh_btn.set_tooltip_text("Open a terminal and run an active scan as root")
        box.pack_start(caption("Network"), False, False, 0)
        box.pack_start(field_row("", combo, reload_btn, refresh_btn), False, False, 0)
        if not len(model):
            box.pack_start(
                caption("No cached scan yet. Press Scan once, then Reload."), False, False, 0
            )

        ssid_entry = Gtk.Entry()
        ssid_entry.set_placeholder_text("network name (SSID)")
        bssid_entry = Gtk.Entry()
        bssid_entry.set_placeholder_text("aa:bb:cc:dd:ee:ff")
        box.pack_start(field_row("SSID", ssid_entry), False, False, 0)
        box.pack_start(field_row("BSSID", bssid_entry), False, False, 0)

        security_combo = Gtk.ComboBoxText()
        for value in ("WPA2", "WPA3", "WPA", "WEP", "OPEN"):
            security_combo.append_text(value)
        security_combo.set_active(0)
        channel_entry = Gtk.Entry()
        channel_entry.set_placeholder_text("auto")
        channel_entry.set_width_chars(6)
        box.pack_start(
            field_row("Security", security_combo, caption("Channel"), channel_entry),
            False, False, 0,
        )

        method_combo = Gtk.ComboBoxText()
        for value in METHOD_LABELS:
            method_combo.append_text(value)
        method_combo.set_active(0)
        box.pack_start(field_row("Method", method_combo), False, False, 0)

        note = Gtk.Label(xalign=0)
        note.set_line_wrap(True)
        note.get_style_context().add_class("muted")
        box.pack_start(note, False, False, 0)

        timeout_spin = Gtk.SpinButton.new_with_range(30, 3600, 30)
        timeout_spin.set_value(180)
        crack_spin = Gtk.SpinButton.new_with_range(60, 7200, 60)
        crack_spin.set_value(1800)
        box.pack_start(
            field_row("Capture (s)", timeout_spin, caption("Crack (s)"), crack_spin),
            False, False, 0,
        )

        wordlist_entry = Gtk.Entry()
        wordlist_entry.set_text("/usr/share/wordlists/rockyou.txt")
        browse = Gtk.Button(label="Browse")
        box.pack_start(
            field_row("Wordlist", wordlist_entry, browse), False, False, 0
        )

        check_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=18)
        capture_only = Gtk.CheckButton(label="Capture only (no cracking)")
        deauth = Gtk.CheckButton(label="Allow 3 deauth frames")
        authorized = Gtk.CheckButton(label="I own this network or have written permission")
        check_row.pack_start(capture_only, False, False, 0)
        check_row.pack_start(deauth, False, False, 0)
        check_row.pack_start(authorized, False, False, 0)
        box.pack_start(check_row, False, False, 0)

        rules = Gtk.Label(
            label=(
                "The attack is scoped to the single BSSID you pick. Deauth is off by default; "
                "when enabled it sends at most 3 frames. Everything is logged to ~/bbt/wifi."
            ),
            xalign=0,
        )
        rules.set_line_wrap(True)
        rules.get_style_context().add_class("muted")
        box.pack_start(rules, False, False, 0)

        state = {"wps": 0}

        def update_note(*_args) -> None:
            security = security_combo.get_active_text() or ""
            choice = method_combo.get_active_text() or ""
            if METHOD_LABELS.get(choice, "auto") == "auto":
                method, reason = recommend_method(security, state["wps"])
                note.set_text(f"Auto -> {method.upper()}: {reason}")
            else:
                note.set_text(METHOD_NOTES.get(METHOD_LABELS.get(choice, ""), ""))

        def load_ap(*_args) -> None:
            active = combo.get_active_iter()
            if active is None:
                return
            ssid = model.get_value(active, 1)
            bssid = model.get_value(active, 2)
            channel = model.get_value(active, 3)
            security = model.get_value(active, 4)
            wps = model.get_value(active, 5)
            if ssid:
                ssid_entry.set_text(ssid)
            if bssid:
                bssid_entry.set_text(bssid)
            if channel:
                channel_entry.set_text(channel)
            if security:
                upper = security.upper()
                for index, value in enumerate(("WPA2", "WPA3", "WPA", "WEP", "OPEN")):
                    if value in upper or ("SAE" in upper and value == "WPA3"):
                        security_combo.set_active(index)
                        break
            state["wps"] = int(wps)
            update_note()

        def reload_cache(*_args) -> None:
            model.clear()
            for ap in load_cached_aps():
                ssid = ap["ssid"] or "(hidden SSID)"
                model.append([
                    f"{ssid}  -  {ap['signal']} dBm  -  ch {ap['channel']}  -  "
                    f"{ap['security'] or '?'}" + ("  + WPS" if ap["wps"] else ""),
                    ap["ssid"], ap["bssid"], ap["channel"], ap["security"], ap["wps"],
                ])
            if len(model):
                combo.set_active(0)

        def pick_wordlist(_button) -> None:
            chooser = Gtk.FileChooserDialog(
                title="Select a wordlist", parent=dialog, action=Gtk.FileChooserAction.OPEN
            )
            chooser.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK)
            if chooser.run() == Gtk.ResponseType.OK:
                wordlist_entry.set_text(chooser.get_filename() or "")
            chooser.destroy()

        combo.connect("changed", load_ap)
        security_combo.connect("changed", update_note)
        method_combo.connect("changed", update_note)
        reload_btn.connect("clicked", reload_cache)
        browse.connect("clicked", pick_wordlist)
        refresh_btn.connect(
            "clicked", lambda _b: launch_terminal("Wi-Fi scan", "bbt-wifi scan", dialog)
        )
        if len(model):
            load_ap()
        else:
            update_note()

        dialog.show_all()
        response = dialog.run()
        values = {
            "ssid": ssid_entry.get_text().strip(),
            "bssid": bssid_entry.get_text().strip(),
            "security": security_combo.get_active_text() or "",
            "channel": channel_entry.get_text().strip(),
            "method": METHOD_LABELS.get(method_combo.get_active_text() or "", "auto"),
            "timeout": int(timeout_spin.get_value()),
            "crack": int(crack_spin.get_value()),
            "wordlist": wordlist_entry.get_text().strip(),
            "capture_only": capture_only.get_active(),
            "deauth": deauth.get_active(),
            "authorized": authorized.get_active(),
        }
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return

        ssid = values["ssid"]
        if not valid_ssid(ssid):
            show_error(
                "Enter the exact network name (1-32 printable characters, no wildcards).",
                self,
            )
            return
        bssid = values["bssid"]
        if bssid and not valid_bssid(bssid):
            show_error("BSSID must look like aa:bb:cc:dd:ee:ff.", self)
            return
        channel = values["channel"] or "auto"
        if channel != "auto" and not channel.isdigit():
            show_error("Channel must be a number or auto.", self)
            return
        method = values["method"]
        if method == "none":
            show_error("No compatible capture tool installed. Run: sudo bbt-os-doctor --fix", self)
            return
        if method == "open":
            show_error("This network is open - there is no key to recover.", self)
            return
        if not values["authorized"]:
            show_error("Tick the permission checkbox first.", self)
            return
        if method == "handshake" and not values["deauth"]:
            confirm = Gtk.MessageDialog(
                transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.YES_NO,
                text="A handshake needs a client reconnect. Continue without deauth?",
            )
            answer = confirm.run()
            confirm.destroy()
            if answer != Gtk.ResponseType.YES:
                return

        argv = ["bbt-wifi", "attack", "--ssid", ssid, "--method", method,
                "--timeout", str(values["timeout"]), "--crack-time", str(values["crack"]),
                "--authorized"]
        if bssid:
            argv += ["--bssid", bssid]
        if values["security"]:
            argv += ["--security", values["security"]]
        if channel != "auto":
            argv += ["--channel", channel]
        if values["wordlist"]:
            argv += ["--wordlist", values["wordlist"]]
        if values["capture_only"]:
            argv.append("--no-crack")
        if values["deauth"]:
            argv.append("--deauth")
        launch_terminal(f"Wi-Fi: {ssid}", shlex.join(argv), self)

    def dialog_crack(self) -> None:
        if not which("bbt-wifi"):
            show_error("The wireless engine is not installed.\n\nRun: sudo bbt-os-refresh --no-upgrade", self)
            return
        dialog = Gtk.Dialog(title="Crack a captured hash", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run", Gtk.ResponseType.OK)
        dialog.set_default_size(560, 300)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)

        hash_entry = Gtk.Entry()
        hash_entry.set_placeholder_text("/root/bbt/wifi/<run>/hashes.22000")
        hash_entry.set_hexpand(True)
        browse = Gtk.Button(label="Browse")
        wordlist = Gtk.Entry()
        wordlist.set_text("/usr/share/wordlists/rockyou.txt")
        runtime = Gtk.SpinButton.new_with_range(300, 7200, 60)
        runtime.set_value(1800)
        show = Gtk.CheckButton(label="Only show already recovered keys (--show)")

        box.pack_start(caption("Hash file (.22000)"), False, False, 0)
        box.pack_start(field_row("", hash_entry, browse), False, False, 0)
        box.pack_start(caption("Wordlist"), False, False, 0)
        box.pack_start(wordlist, False, False, 0)
        box.pack_start(field_row("Runtime (s)", runtime), False, False, 0)
        box.pack_start(show, False, False, 0)
        note = Gtk.Label(
            label="hashcat -m 22000 with best64 rules when /usr/share/hashcat/rules/best64.rule exists.",
            xalign=0,
        )
        note.get_style_context().add_class("muted")
        box.pack_start(note, False, False, 0)

        def choose_hash(_button) -> None:
            chooser = Gtk.FileChooserDialog(
                title="Select a hash file", parent=dialog, action=Gtk.FileChooserAction.OPEN
            )
            chooser.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK)
            file_filter = Gtk.FileFilter()
            file_filter.set_name("Hash files (*.22000, *.hash)")
            file_filter.add_pattern("*.22000")
            file_filter.add_pattern("*.hash")
            chooser.add_filter(file_filter)
            if chooser.run() == Gtk.ResponseType.OK:
                hash_entry.set_text(chooser.get_filename() or "")
            chooser.destroy()

        browse.connect("clicked", choose_hash)
        dialog.show_all()
        response = dialog.run()
        values = (
            hash_entry.get_text().strip(),
            wordlist.get_text().strip(),
            int(runtime.get_value()),
            show.get_active(),
        )
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        hash_path, word_path, runtime_s, show_only = values
        if not os.path.isfile(hash_path):
            show_error("Pick an existing .22000 hash file.", self)
            return
        if show_only:
            argv = ["bbt-wifi", "crack", "--hash", hash_path, "--show"]
        else:
            if not os.path.isfile(word_path):
                show_error("Wordlist not found. Extract rockyou or pick another list.", self)
                return
            argv = ["bbt-wifi", "crack", "--hash", hash_path,
                    "--wordlist", word_path, "--runtime", str(runtime_s)]
        launch_terminal("Crack hash", shlex.join(argv), self)

    # -- about
    def on_about(self, _button: Gtk.Button) -> None:
        dialog = Gtk.AboutDialog(transient_for=self, modal=True)
        dialog.set_program_name("BBT OS")
        dialog.set_version(VERSION)
        dialog.set_comments(
            "Bug Bounty Toolkit Edition - community overlay for Kali Linux.\n"
            "Web / Recon, Wireless, Android, Windows / AD, Smart Card and reporting.\n"
            "Every attack stays inside the scope you declare."
        )
        dialog.set_website(GITHUB)
        dialog.set_website_label("github.com/A-z-exe")
        dialog.set_authors(["AmirHossein Zarei <" + EMAIL + ">"])
        dialog.set_license_type(Gtk.License.MIT_X11)
        logo = icon_pixbuf("terminal", 96)
        if logo is not None:
            dialog.set_logo(logo)
        else:
            dialog.set_logo_icon_name("utilities-terminal")
        dialog.run()
        dialog.destroy()


def main() -> int:
    if "--version" in sys.argv:
        print(f"BBT OS launcher {VERSION}")
        return 0
    if "--check" in sys.argv:
        actions = build_actions()
        missing: list[tuple[str, str]] = []
        for action in actions:
            state = mark_missing(action)
            print(f"{action['category']}: {action['name']}{state}")
            if state:
                missing.append((action["category"], action["name"]))
        tools = {action["tool"] for action in actions if action.get("tool")}
        present = sum(1 for tool in tools if which(tool))
        print(f"\nengines: bbt-wifi={'ok' if which('bbt-wifi') else 'missing'} "
              f"bbt-workflow={'ok' if which('bbt-workflow') else 'missing'} "
              f"doctor={'ok' if which('bbt-os-doctor') else 'missing'}")
        print(f"icons: {', '.join(str(path) for path in icon_dirs()) or 'none'}")
        print(f"tools: {present}/{len(tools)}")
        print(f"missing actions: {len(missing)}")
        return 0
    if not os.environ.get("DISPLAY"):
        print("BBT OS launcher needs a graphical session (DISPLAY is not set).", file=sys.stderr)
        return 1
    BBTWindow()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
