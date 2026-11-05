#!/usr/bin/env python3
"""BBT OS launcher - a dark, searchable console for bug bounty tooling.

Every action opens a terminal (or a native GUI app) and never scans a target
on its own. Guided actions require an explicit authorization confirmation.
"""
from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

VERSION = "1.0.0"
GITHUB = "https://github.com/A-z-exe"
EMAIL = "207771865+A-z-exe@users.noreply.github.com"
HOME = Path.home()
SCOPE_FILE = HOME / "scope.txt"
RECON_DIR = HOME / "bbt" / "recon"

CSS = b"""
window { background-color: #04080a; color: #d7fff1; }
headerbar { background: #07110f; border-bottom: 1px solid #145c4a; }
.title { color: #39ff14; font-family: monospace; font-weight: bold; font-size: 24px; }
.subtitle { color: #6fbfa8; font-family: monospace; font-size: 11px; }
.section { color: #22d3ee; font-family: monospace; font-weight: bold; font-size: 12px; }
button { background: #0a1815; border: 1px solid #145c4a; border-radius: 8px;
         padding: 9px 12px; color: #d7fff1; font-family: monospace; }
button:hover { border-color: #39ff14; background: #0f2622; }
entry { background: #07110f; color: #d7fff1; border: 1px solid #145c4a;
        border-radius: 6px; padding: 6px; font-family: monospace; }
label.name { color: #d7fff1; font-family: monospace; font-weight: bold; font-size: 13px; }
label.desc { color: #6fbfa8; font-family: monospace; font-size: 10px; }
label.warn { color: #ffbd2e; font-family: monospace; font-size: 11px; }
label.muted { color: #5f8f82; font-family: monospace; font-size: 10px; }
"""


def which(tool: str) -> str | None:
    found = shutil.which(tool)
    if found:
        return found
    for directory in (HOME / ".local" / "bin", Path("/usr/local/bin")):
        candidate = directory / tool
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


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
    if flag == "-x":
        return [term, flag, runner]
    return [term, flag, runner]


def launch_terminal(title: str, command: str) -> None:
    argv = terminal_command(title, command)
    if not argv:
        show_error("No terminal emulator found. Install qterminal, xfce4-terminal or xterm.")
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


def mark_missing(action: dict) -> str:
    tool = action.get("tool")
    if tool and not which(tool):
        return "  [not installed - run Refresh]"
    return ""


def build_actions() -> list[dict]:
    actions: list[dict] = []
    _repo, bbt_argv = bbt_invocation()
    bbt_cmd = shlex.join(bbt_argv)

    def add(category, name, desc, command, tool=None, gui=False, keywords=""):
        actions.append(
            {
                "category": category,
                "name": name,
                "desc": desc,
                "command": command,
                "tool": tool,
                "gui": gui,
                "keywords": keywords,
            }
        )

    # ---------------------------------------------------------------- Web
    add(
        "Web / Recon",
        "BBT Auto Hunt",
        "Scope-gated -m auto run with a target and scope file",
        "",
        keywords="bbt auto scan bug bounty",
    )
    add(
        "Web / Recon",
        "Web Recon Pipeline",
        "subfinder -> httpx for an authorized domain",
        "",
        keywords="subfinder httpx subdomain recon",
    )
    add("Web / Recon", "httpx", "HTTP probing, titles, tech and status codes",
        "httpx -h 2>&1 | head -n 60", "httpx")
    add("Web / Recon", "nuclei", "Template-based vulnerability checks",
        "nuclei -h 2>&1 | head -n 60", "nuclei")
    add("Web / Recon", "ffuf", "Content and parameter discovery",
        "ffuf -h 2>&1 | head -n 60", "ffuf")
    add("Web / Recon", "katana", "JavaScript-aware crawling",
        "katana -h 2>&1 | head -n 60", "katana")
    add("Web / Recon", "subfinder", "Passive subdomain enumeration",
        "subfinder -h 2>&1 | head -n 40", "subfinder")
    add("Web / Recon", "whatweb", "Fingerprint web technologies",
        "whatweb --help 2>&1 | head -n 40", "whatweb")
    add("Web / Recon", "WPScan", "WordPress enumeration (authorized sites only)",
        "wpscan --help 2>&1 | head -n 50", "wpscan")
    add("Web / Recon", "Nikto", "Web server misconfiguration checks",
        "nikto -Help 2>&1 | head -n 50", "nikto")
    add("Web / Recon", "sqlmap", "Injection verification only - stop after confirm",
        "sqlmap -h 2>&1 | head -n 50", "sqlmap")

    # ------------------------------------------------------------- Android
    add("Android", "ADB devices", "List connected Android devices",
        "adb devices -l", "adb", keywords="adb android usb")
    add("Android", "APK decompile (apktool)", "Choose an APK and decompile it",
        "", "apktool", keywords="apk apktool decompile")
    add("Android", "APK open (JADX GUI)", "Choose an APK and open JADX GUI",
        "", "jadx-gui", gui=True, keywords="apk jadx decompile gui")
    add("Android", "APK to JAR (dex2jar)", "Choose an APK and convert its classes to a JAR",
        "", "d2j-dex2jar", keywords="apk dex2jar jar classes")
    add("Android", "Frida processes", "List processes on the USB device",
        "frida-ps -U", "frida-ps", keywords="frida hook instrumentation")
    add("Android", "Objection", "Runtime mobile exploration help",
        "objection --help 2>&1 | head -n 50", "objection")
    add("Android", "Scrcpy", "Mirror and control the Android device",
        "", "scrcpy", gui=True, keywords="scrcpy screen mirror")
    add("Android", "Start MobSF", "Run MobSF in Docker on port 8000 (first run pulls the image)",
        "mobsf start", "docker", keywords="mobsf apk static analysis docker")
    add("Android", "Stop MobSF", "Stop the MobSF container",
        "mobsf stop", "docker", keywords="mobsf stop docker")
    add("Android", "MobSF logs", "Follow the MobSF container log",
        "mobsf logs", "docker", keywords="mobsf logs docker")
    add("Android", "Open MobSF UI", "Open http://127.0.0.1:8000 in the browser",
        "", None, gui=True, keywords="mobsf browser")

    # --------------------------------------------------------- Windows / AD
    add("Windows / AD", "NetExec", "SMB/WinRM/LDAP assessment help (authorized AD only)",
        "netexec --help 2>&1 | head -n 60", "netexec", keywords="netexec smb ldap ad")
    add("Windows / AD", "Impacket", "List installed Impacket example tools",
        "compgen -c | grep '^impacket-' | sort -u | head -n 40", "python3",
        keywords="impacket smb secretsdump")
    add("Windows / AD", "Evil-WinRM", "WinRM shell help (authorized hosts only)",
        "evil-winrm -h 2>&1 | head -n 50", "evil-winrm")
    add("Windows / AD", "Responder", "LLMNR/NBT-NS/MDNS poisoning help (lab/authorized only)",
        "sudo responder -h 2>&1 | head -n 50", "responder")
    add("Windows / AD", "Enum4linux-ng", "SMB/NetBIOS enumeration",
        "enum4linux-ng -h 2>&1 | head -n 50", "enum4linux-ng")
    add("Windows / AD", "BloodHound.py", "AD collection help",
        "bloodhound-python -h 2>&1 | head -n 50", "bloodhound-python")

    # ------------------------------------------------------------ Reporting
    add("Reporting", "BBT help", "Show every BBT mode and option",
        f"{bbt_cmd} --help 2>&1 | head -n 80", keywords="bbt help usage")
    add("Reporting", "Edit scope file", "Create or edit ~/scope.txt",
        f"mkdir -p {shlex.quote(str(HOME))} && "
        f"[ -f {shlex.quote(str(SCOPE_FILE))} ] || "
        f"printf '# one host/domain/URL/CIDR per line\\n' > {shlex.quote(str(SCOPE_FILE))}; "
        f"${{EDITOR:-nano}} {shlex.quote(str(SCOPE_FILE))}")
    add("Reporting", "Open BBT results", "Open the toolkit results directory",
        f"mkdir -p {shlex.quote(str(HOME / 'tools' / 'BugBountyToolkit' / 'results'))} && "
        f"xdg-open {shlex.quote(str(HOME / 'tools' / 'BugBountyToolkit' / 'results'))}",
        gui=True)
    add("Reporting", "Open recon files", "Open ~/bbt/recon",
        f"mkdir -p {shlex.quote(str(RECON_DIR))} && xdg-open {shlex.quote(str(RECON_DIR))}",
        gui=True)

    # -------------------------------------------------------------- Updates
    add("Updates", "Refresh BBT OS", "apt update, tool updates and database refresh",
        "sudo bbt-os-refresh", keywords="update upgrade refresh")
    add("Updates", "Update nuclei templates", "Download the latest nuclei templates",
        "nuclei -update-templates", "nuclei")
    add("Updates", "Update BBT toolkit", "git pull and reinstall the Python package",
        "", "git", keywords="bbt update git")
    add("Updates", "System upgrade", "apt update && apt full-upgrade",
        "sudo apt update && sudo apt full-upgrade -y")

    return actions


class BBTWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="BBT OS")
        self.set_default_size(1020, 720)
        self.set_border_width(0)
        self.actions = build_actions()
        self.buttons: list[tuple[Gtk.Widget, dict, Gtk.Label]] = []

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.props.title = "BBT OS"
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        title = Gtk.Label(label="BBT OS", xalign=0)
        title.get_style_context().add_class("title")
        subtitle = Gtk.Label(label="BUG BOUNTY TOOLKIT - web / android / windows", xalign=0)
        subtitle.get_style_context().add_class("subtitle")
        title_box.pack_start(title, False, False, 0)
        title_box.pack_start(subtitle, False, False, 0)
        header.set_custom_title(title_box)
        about = Gtk.Button(label="About")
        about.connect("clicked", self.on_about)
        header.pack_end(about)
        self.set_titlebar(header)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        outer.set_border_width(12)

        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search tools, categories or keywords...")
        search.connect("search-changed", self.on_search)
        outer.pack_start(search, False, False, 0)
        self.search = search

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_hexpand(True)
        sw.set_vexpand(True)
        self.content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.content.set_border_width(4)
        sw.add(self.content)
        outer.pack_start(sw, True, True, 0)

        warning = Gtk.Label(
            label="AUTHORIZED TARGETS ONLY  -  every scan is your responsibility",
            xalign=0.5,
        )
        warning.get_style_context().add_class("warn")
        outer.pack_start(warning, False, False, 0)

        self.add(outer)
        self.build_sections()
        self.connect("destroy", Gtk.main_quit)
        self.show_all()

    def build_sections(self) -> None:
        categories: list[str] = []
        for action in self.actions:
            if action["category"] not in categories:
                categories.append(action["category"])

        for category in categories:
            section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            heading = Gtk.Label(label=f"// {category.upper()}", xalign=0)
            heading.get_style_context().add_class("section")
            section.pack_start(heading, False, False, 0)

            grid = Gtk.Grid(column_spacing=8, row_spacing=8)
            grid.set_column_homogeneous(True)
            section.pack_start(grid, False, False, 0)

            row = col = 0
            for action in self.actions:
                if action["category"] != category:
                    continue
                button = self.make_button(action)
                grid.attach(button, col, row, 1, 1)
                col += 1
                if col == 2:
                    col = 0
                    row += 1
            self.content.pack_start(section, False, False, 0)
            section.show_all()

    def make_button(self, action: dict) -> Gtk.Button:
        button = Gtk.Button()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        box.set_border_width(2)
        name = Gtk.Label(label=action["name"], xalign=0)
        name.get_style_context().add_class("name")
        desc = Gtk.Label(label=action["desc"] + mark_missing(action), xalign=0)
        desc.set_line_wrap(True)
        desc.get_style_context().add_class("desc")
        box.pack_start(name, False, False, 0)
        box.pack_start(desc, False, False, 0)
        button.add(box)
        button.set_tooltip_text(action["desc"])
        button.connect("clicked", self.on_action, action)
        self.buttons.append((button, action, desc))
        return button

    def on_search(self, entry: Gtk.SearchEntry) -> None:
        needle = entry.get_text().strip().lower()
        for button, action, _desc in self.buttons:
            haystack = " ".join(
                [
                    action["category"],
                    action["name"],
                    action["desc"],
                    action["keywords"],
                ]
            ).lower()
            button.set_visible(not needle or needle in haystack)

        child = self.content.get_children()
        for section in child:
            visible = any(
                button.get_visible()
                for button, _action, _desc in self.buttons
                if button.get_parent() is not None
                and button.get_parent().get_parent() is section
            )
            section.set_visible(visible)

    def on_action(self, _button: Gtk.Button, action: dict) -> None:
        name = action["name"]
        if name == "BBT Auto Hunt":
            self.dialog_hunt()
        elif name == "Web Recon Pipeline":
            self.dialog_recon()
        elif name == "APK decompile (apktool)":
            apk = self.choose_apk()
            if apk:
                out = apk[:-4] + "_apktool" if apk.lower().endswith(".apk") else apk + "_apktool"
                launch_terminal(
                    f"apktool: {Path(apk).name}",
                    f"apktool d -f {shlex.quote(apk)} -o {shlex.quote(out)}",
                )
        elif name == "APK open (JADX GUI)":
            apk = self.choose_apk()
            if apk:
                launch_gui(["jadx-gui", apk])
        elif name == "APK to JAR (dex2jar)":
            apk = self.choose_apk()
            if apk:
                out = apk[:-4] + ".jar" if apk.lower().endswith(".apk") else apk + ".jar"
                launch_terminal(
                    f"dex2jar: {Path(apk).name}",
                    f"d2j-dex2jar -f -o {shlex.quote(out)} {shlex.quote(apk)}",
                )
        elif name == "Scrcpy":
            launch_gui(["scrcpy"])
        elif name == "Open MobSF UI":
            launch_gui(["xdg-open", "http://127.0.0.1:8000"])
        elif name == "Update BBT toolkit":
            self.update_bbt()
        elif action["command"]:
            if action.get("gui"):
                launch_gui(["bash", "-c", action["command"]])
            else:
                launch_terminal(name, action["command"])

    def update_bbt(self) -> None:
        repo, _argv = bbt_invocation()
        if not (Path(repo) / ".git").is_dir():
            show_error("BBT is not a git checkout, so it cannot be updated this way.", self)
            return
        command = (
            f"cd {shlex.quote(repo)} && git pull --ff-only && "
            ".venv-sys/bin/pip install -e . && bbt --version"
        )
        launch_terminal("Update BBT toolkit", command)

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

    def dialog_hunt(self) -> None:
        repo, argv = bbt_invocation()
        dialog = Gtk.Dialog(title="BBT Auto Hunt", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run hunt", Gtk.ResponseType.OK)
        dialog.set_default_size(560, 300)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)

        target = Gtk.Entry()
        target.set_placeholder_text("https://app.example.com")
        scope = Gtk.Entry()
        scope.set_text(str(SCOPE_FILE))
        deep = Gtk.CheckButton(label="Deep scan (katana, ffuf, nikto, subfinder)")
        auth = Gtk.CheckButton(label="I have written authorization for this target")

        for label, widget in (
            ("Target URL", target),
            ("Scope file", scope),
            ("", deep),
            ("", auth),
        ):
            if label:
                caption = Gtk.Label(label=label, xalign=0)
                caption.get_style_context().add_class("muted")
                box.pack_start(caption, False, False, 0)
            box.pack_start(widget, False, False, 0)

        hint = Gtk.Label(
            label=f"Toolkit: {repo}\nThe run uses -m auto --authorized and is limited to the scope file.",
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
            show_error(f"Scope file not found:\n{scope_path}\n\nCreate it with Reporting > Edit scope file.", self)
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
        launch_terminal("BBT auto hunt", command)

    def dialog_recon(self) -> None:
        dialog = Gtk.Dialog(title="Web Recon Pipeline", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Run", Gtk.ResponseType.OK)
        dialog.set_default_size(520, 220)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)

        domain = Gtk.Entry()
        domain.set_placeholder_text("example.com")
        auth = Gtk.CheckButton(label="I have written authorization for this domain")
        for label, widget in (("Domain", domain), ("", auth)):
            if label:
                caption = Gtk.Label(label=label, xalign=0)
                caption.get_style_context().add_class("muted")
                box.pack_start(caption, False, False, 0)
            box.pack_start(widget, False, False, 0)
        dialog.show_all()
        response = dialog.run()
        value = domain.get_text().strip()
        authorized = auth.get_active()
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        if not re.match(r"^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$", value):
            show_error("Enter a bare domain such as example.com.", self)
            return
        if not authorized:
            show_error("Tick the authorization checkbox first.", self)
            return
        command = (
            f"mkdir -p {shlex.quote(str(RECON_DIR))} && cd {shlex.quote(str(RECON_DIR))} && "
            f"subfinder -d {shlex.quote(value)} -silent | httpx -silent "
            f"-o {shlex.quote(value + '-live.txt')}"
        )
        launch_terminal("Web recon pipeline", command)

    def on_about(self, _button: Gtk.Button) -> None:
        dialog = Gtk.AboutDialog(transient_for=self, modal=True)
        dialog.set_program_name("BBT OS")
        dialog.set_version(VERSION)
        dialog.set_comments(
            "Bug Bounty Toolkit Edition - community overlay for Kali Linux.\n"
            "Web / Recon, Android, Windows / AD and reporting."
        )
        dialog.set_website(GITHUB)
        dialog.set_website_label("github.com/A-z-exe")
        dialog.set_authors(["AmirHossein Zarei <" + EMAIL + ">"])
        dialog.set_license_type(Gtk.License.MIT_X11)
        dialog.set_logo_icon_name("utilities-terminal")
        dialog.run()
        dialog.destroy()


def main() -> int:
    if "--version" in sys.argv:
        print(f"BBT OS launcher {VERSION}")
        return 0
    if "--check" in sys.argv:
        for action in build_actions():
            state = mark_missing(action) or ""
            print(f"{action['category']}: {action['name']}{state}")
        return 0
    if not os.environ.get("DISPLAY"):
        print("BBT OS launcher needs a graphical session (DISPLAY is not set).", file=sys.stderr)
        return 1
    BBTWindow()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
