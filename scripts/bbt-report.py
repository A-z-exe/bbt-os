#!/usr/bin/env python3
"""Generate a Markdown bug-bounty report from a bbt-autohunt run."""
import argparse
from pathlib import Path


def read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = Path(args.out)
    report = out / "report"
    report.mkdir(parents=True, exist_ok=True)

    alive = read(out / "recon" / "alive.txt").splitlines()
    nuclei = read(out / "scan" / "nuclei.txt").splitlines()
    dalfox = read(out / "scan" / "dalfox.txt").splitlines()
    critical = [line for line in nuclei if any(k in line.lower() for k in ("critical", "high", "medium"))]

    lines = [
        f"# Bug bounty report — {args.target}",
        "",
        "## Scope and authorization",
        f"- Target: `{args.target}`",
        "- Testing must stay inside the program's published scope.",
        "",
        "## Summary",
        f"- Live hosts discovered: {len(alive)}",
        f"- Nuclei findings: {len(nuclei)}",
        f"- Potential XSS (dalfox): {len(dalfox)}",
        f"- Medium/high/critical nuclei findings: {len(critical)}",
        "",
        "## Discovered hosts",
    ]
    lines += [f"- `{host}`" for host in alive[:100]] or ["- none"]
    lines += ["", "## High-signal findings", ""]
    lines += [f"- {item}" for item in critical[:50]] or ["- none automatically classified; review raw nuclei output."]
    lines += ["", "## XSS candidates", ""]
    lines += [f"- {item}" for item in dalfox[:50]] or ["- none"]
    lines += [
        "",
        "## Attack chain / PoC guidance",
        "",
        read(out / "exploit" / "poc-hints.md") or "- see raw tool output",
        "",
        "## Raw evidence",
        "",
        "- `scan/nuclei.txt`, `scan/dalfox.txt`, `scan/nikto.txt`, `scan/ffuf.json`",
        "- `scan/whatweb_*.txt`, `scan/sslscan_*.txt`",
        "",
        "## Remediation",
        "",
        "- Confirm each finding manually before submission.",
        "- Include request/response pairs, impact, and step-by-step reproduction.",
        "- Follow the platform's disclosure policy; do not access unrelated data.",
    ]
    path = report / "report.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(path)


if __name__ == "__main__":
    main()
