#!/usr/bin/env python3
"""Generate the BBT OS neon icon set (24x24, green stroke + cyan accents)."""
from pathlib import Path

OUT = Path(__file__).resolve().parent
G = "#39ff14"
C = "#22d3ee"
D = "#145c4a"

def svg(body: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" '
        'fill="none" stroke="%s" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">\n'
        "%s\n</svg>\n" % (G, body)
    )

ICONS = {}

# --- categories -------------------------------------------------------------
ICONS["web"] = """
<circle cx="12" cy="12" r="8"/>
<path d="M4 12h16"/>
<path d="M12 4c2.8 2.4 4 5 4 8s-1.2 5.6-4 8c-2.8-2.4-4-5-4-8s1.2-5.6 4-8z" stroke="#22d3ee"/>
"""
ICONS["wifi"] = """
<path d="M3 9a13 13 0 0 1 18 0"/>
<path d="M6 12.6a9 9 0 0 1 12 0"/>
<path d="M9 16.2a5 5 0 0 1 6 0"/>
<circle cx="12" cy="19.4" r="1.1" fill="#39ff14" stroke="none"/>
"""
ICONS["android"] = """
<path d="M5 11h14v5.5a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4z"/>
<path d="M8.5 7.5 7 5M15.5 7.5 17 5"/>
<path d="M8 11v-1a4 4 0 0 1 8 0v1"/>
<circle cx="9.4" cy="13.3" r=".8" fill="#22d3ee" stroke="none"/>
<circle cx="14.6" cy="13.3" r=".8" fill="#22d3ee" stroke="none"/>
"""
ICONS["windows"] = """
<rect x="3" y="4.5" width="8" height="6.2" rx=".6"/>
<rect x="13" y="4.5" width="8" height="6.2" rx=".6"/>
<rect x="3" y="13.3" width="8" height="6.2" rx=".6"/>
<rect x="13" y="13.3" width="8" height="6.2" rx=".6" stroke="#22d3ee"/>
"""
ICONS["card"] = """
<rect x="2.5" y="5.5" width="19" height="13" rx="2"/>
<rect x="5.5" y="9" width="5" height="4" rx=".8" stroke="#22d3ee"/>
<path d="M5.5 16h7M5.5 18h4.5"/>
<path d="M14.5 9.5h4M14.5 12h4M14.5 14.5h2.5"/>
"""
ICONS["pulse"] = """
<path d="M12 3 19 6v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9V6z"/>
<path d="M7.5 12h2l1.2-2.4 1.8 4.2 1.2-1.8h2.3" stroke="#22d3ee"/>
"""
ICONS["doc"] = """
<path d="M6 3h8l4 4v14H6z"/>
<path d="M14 3v4h4"/>
<path d="M9 12h6M9 15h6M9 18h3.5" stroke="#22d3ee"/>
"""
ICONS["refresh"] = """
<path d="M20 12a8 8 0 1 1-2.3-5.7"/>
<path d="M20 4v4.2h-4.2"/>
<path d="M8.5 12h7" stroke="#22d3ee"/>
"""

# --- web --------------------------------------------------------------------
ICONS["crosshair"] = """
<circle cx="12" cy="12" r="7"/>
<path d="M12 3v3M12 18v3M3 12h3M18 12h3"/>
<circle cx="12" cy="12" r="1.4" fill="#39ff14" stroke="none"/>
<path d="M15.6 8.4 18 6" stroke="#22d3ee"/>
"""
ICONS["radar"] = """
<path d="M12 20a8 8 0 1 1 8-8"/>
<path d="M12 17a5 5 0 1 1 5-5"/>
<path d="M12 12 18.5 7" stroke="#22d3ee"/>
<circle cx="12" cy="12" r="1.1" fill="#39ff14" stroke="none"/>
<circle cx="16.4" cy="9.2" r="1" fill="#22d3ee" stroke="none"/>
"""
ICONS["vuln"] = """
<ellipse cx="12" cy="13.5" rx="4.2" ry="5.5"/>
<path d="M12 8V5.5M10 6 8.6 4.4M14 6l1.4-1.6"/>
<path d="M7.8 11H4.5M7.8 14H4M8.4 17 5.5 19M16.2 11h3.3M16.2 14H20M15.6 17l2.9 2" stroke="#22d3ee"/>
"""
ICONS["funnel"] = """
<path d="M3.5 4.5h17l-6.5 7.5V19l-4 2v-9z"/>
<path d="M7 8h10" stroke="#22d3ee"/>
"""
ICONS["crawl"] = """
<circle cx="12" cy="12" r="8"/>
<circle cx="12" cy="12" r="4.5" stroke="#22d3ee"/>
<path d="M12 4v16M4 12h16M6.3 6.3l11.4 11.4M17.7 6.3 6.3 17.7" stroke-width="1.1"/>
"""
ICONS["net"] = """
<circle cx="12" cy="5" r="2.2"/>
<circle cx="5" cy="18" r="2.2"/>
<circle cx="19" cy="18" r="2.2"/>
<path d="M12 7.2 6.3 16M12 7.2 17.7 16M7.2 18h9.6" stroke="#22d3ee"/>
"""
ICONS["search"] = """
<circle cx="10" cy="10" r="5.5"/>
<path d="M14.2 14.2 20 20"/>
<path d="M7.8 8.5h4.4M7.8 11h3" stroke="#22d3ee"/>
"""
ICONS["puzzle"] = """
<path d="M4 9h3.2a2 2 0 1 1 3.6 0H14v3.2a2 2 0 1 1 0 3.6V19H9.8a2 2 0 1 0-3.6 0H4z"/>
<path d="M15 11.5h3.5" stroke="#22d3ee"/>
"""
ICONS["server"] = """
<rect x="3.5" y="4" width="17" height="7" rx="1.2"/>
<rect x="3.5" y="13" width="17" height="7" rx="1.2"/>
<path d="M6.8 7.5h.1M6.8 16.5h.1" stroke-width="2.4"/>
<path d="M14 7.5h3.5M14 16.5h3.5" stroke="#22d3ee"/>
"""
ICONS["db"] = """
<ellipse cx="12" cy="5.8" rx="7" ry="2.8"/>
<path d="M5 5.8v6c0 1.6 3.1 2.8 7 2.8s7-1.2 7-2.8v-6"/>
<path d="M5 11.8v6c0 1.6 3.1 2.8 7 2.8s7-1.2 7-2.8v-6"/>
<path d="M13.9 10.2 11 14.6h2.3l-.9 3.2 3.1-4.6h-2.3z" stroke="#22d3ee" fill="none"/>
"""
ICONS["code"] = """
<path d="M8.5 6.5 3 12l5.5 5.5M15.5 6.5 21 12l-5.5 5.5"/>
<path d="M13.5 5 10.5 19" stroke="#22d3ee"/>
"""
ICONS["key"] = """
<circle cx="8" cy="8" r="4"/>
<path d="M11 11 20 20M17.2 17.2l2-2M14.6 14.6l1.8-1.8" />
<path d="M6.4 8h3.2" stroke="#22d3ee"/>
"""
ICONS["shield"] = """
<path d="M12 3 19 6v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9V6z"/>
<path d="M8.8 12.2l2.1 2.1 4.3-4.4" stroke="#22d3ee"/>
"""
ICONS["usb"] = """
<path d="M12 21V5"/>
<path d="M12 5 9.5 8M12 5l2.5 3"/>
<path d="M12 14c-3 0-3-3.6-6-3.6V8"/>
<path d="M12 16c3 0 3-3.6 6-3.6V10" stroke="#22d3ee"/>
<circle cx="6" cy="7" r="1" fill="#22d3ee" stroke="none"/>
<rect x="17" y="8.4" width="2" height="2" rx=".3" stroke="#22d3ee"/>
"""
ICONS["package"] = """
<path d="M12 3 20 7.5v9L12 21l-8-4.5v-9z"/>
<path d="M4 7.5 12 12l8-4.5M12 12v9"/>
<path d="M8 5.2l8 4.6" stroke="#22d3ee"/>
"""
ICONS["hook"] = """
<path d="M15 4v6.5a4 4 0 1 1-8 0"/>
<circle cx="15" cy="4" r="1.4"/>
<path d="M9 14.5 6.5 17" stroke="#22d3ee"/>
"""
ICONS["terminal"] = """
<rect x="2.5" y="4" width="19" height="16" rx="2"/>
<path d="M6 9l3 3-3 3" stroke="#22d3ee"/>
<path d="M11.5 15h6"/>
"""
ICONS["phone"] = """
<rect x="7" y="2.5" width="10" height="19" rx="2"/>
<path d="M10.5 18.5h3"/>
<path d="M9.5 6.5h5M9.5 9.5h5" stroke="#22d3ee"/>
"""
ICONS["shieldscan"] = """
<path d="M12 3 19 6v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9V6z"/>
<path d="M8 11.5h8M8 14h8" stroke="#22d3ee"/>
<circle cx="12" cy="11.5" r="1" fill="#39ff14" stroke="none"/>
"""
ICONS["stop"] = """
<rect x="4" y="4" width="16" height="16" rx="3"/>
<rect x="8.5" y="8.5" width="7" height="7" rx="1" stroke="#22d3ee"/>
"""
ICONS["logs"] = """
<path d="M4 6h16M4 11h16M4 16h10M4 20h7" stroke-width="1.3"/>
<circle cx="20" cy="18.5" r="1.3" fill="#22d3ee" stroke="none"/>
"""
ICONS["graph"] = """
<circle cx="6" cy="6.5" r="2.3"/>
<circle cx="18" cy="8.5" r="2.3"/>
<circle cx="11" cy="18" r="2.3"/>
<path d="M8.2 7.2 15.8 8M7.2 8.5l2.7 7.5M16.6 10.5l-4.3 5.7" stroke="#22d3ee"/>
"""
ICONS["radio"] = """
<path d="M12 21V9"/>
<path d="M8.5 21h7"/>
<path d="M8.2 6a5 5 0 0 1 7.6 0M5.4 3.6a9 9 0 0 1 13.2 0" stroke="#22d3ee"/>
<circle cx="12" cy="9" r="1.3" fill="#39ff14" stroke="none"/>
"""
ICONS["reader"] = """
<path d="M3.5 8h17v11a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 19z"/>
<path d="M2.5 8 4 4.5h16L21.5 8"/>
<rect x="7" y="11.5" width="5.5" height="4" rx=".7" stroke="#22d3ee"/>
<path d="M15 12.5h3.5M15 15h2.5"/>
"""
ICONS["chip"] = """
<rect x="7" y="7" width="10" height="10" rx="1.4"/>
<rect x="10" y="10" width="4" height="4" rx=".5" stroke="#22d3ee"/>
<path d="M10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4"/>
"""
ICONS["cert"] = """
<path d="M5.5 3h9l4 4v9.5h-13z"/>
<path d="M14.5 3v4h4"/>
<path d="M8.5 9h3M8.5 11.5h3" stroke="#22d3ee"/>
<circle cx="16" cy="15.5" r="3"/>
<path d="M14.4 18 13.5 22l2.5-1.3L18.5 22l-.9-4" stroke="#22d3ee"/>
"""
ICONS["nfc"] = """
<rect x="3.5" y="2.5" width="13" height="19" rx="2"/>
<path d="M7.5 15.5a4.5 4.5 0 0 1 0-7" stroke="#22d3ee"/>
<path d="M9.8 13.6a1.8 1.8 0 0 1 0-3.2" stroke="#22d3ee"/>
<path d="M15 8.5c2.5 1.8 3.8 4 3.8 6.5M15 12.4c1.2.9 1.8 1.8 1.8 2.6" stroke="#39ff14"/>
"""
ICONS["edit"] = """
<path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17z"/>
<path d="M13.8 6.8l3.4 3.4" stroke="#22d3ee"/>
<path d="M4 20h4" stroke="#22d3ee"/>
"""
ICONS["cpu"] = """
<rect x="4" y="4" width="16" height="16" rx="2"/>
<rect x="8.5" y="8.5" width="7" height="7" rx=".8" stroke="#22d3ee"/>
<path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2"/>
"""
ICONS["gear"] = """
<circle cx="12" cy="12" r="7.4"/>
<circle cx="12" cy="12" r="3.1" stroke="#22d3ee"/>
<path d="M12 2.4v2.2M12 19.4v2.2M2.4 12h2.2M19.4 12h2.2M5.2 5.2l1.6 1.6M17.2 17.2l1.6 1.6M18.8 5.2l-1.6 1.6M6.8 17.2l-1.6 1.6"/>
"""
ICONS["folder"] = """
<path d="M3 6.5A1.5 1.5 0 0 1 4.5 5h4l2 2.5h9A1.5 1.5 0 0 1 21 9v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18z"/>
<path d="M3 10h18" stroke="#22d3ee"/>
"""
ICONS["download"] = """
<path d="M12 3v11"/>
<path d="M7.5 10 12 14.5 16.5 10"/>
<path d="M4 17v2.5h16V17" stroke="#22d3ee"/>
"""
ICONS["handshake"] = """
<path d="M3 9h7a3 3 0 0 1 0 6H7"/>
<path d="M6 9 3.5 11.5 6 14"/>
<path d="M21 15h-7a3 3 0 0 1 0-6h3" stroke="#22d3ee"/>
<path d="M18 15l2.5-2.5L18 10" stroke="#22d3ee"/>
"""
ICONS["routerlock"] = """
<rect x="3" y="12" width="18" height="8" rx="2"/>
<path d="M6.5 16h.1M9.5 16h.1" stroke-width="2.4"/>
<path d="M12 7.5V10M12 7.5a4 4 0 0 1 4-4" stroke="#22d3ee"/>
<rect x="14.5" y="4.5" width="4" height="3.4" rx=".7" stroke="#22d3ee"/>
"""

for name, body in ICONS.items():
    (OUT / f"{name}.svg").write_text(svg(body.strip()), encoding="utf-8")

print(f"{len(ICONS)} icons written to {OUT}")
