#!/usr/bin/env bash
# BBT OS health audit entry point.

install_audit() {
    step "Health audit"
    install -m 755 "$HERE/scripts/bbt-os-doctor.sh" /usr/local/bin/bbt-os-doctor
    ok "bbt-os-doctor ready (kernel, services, adapters, tools, data)"
}
