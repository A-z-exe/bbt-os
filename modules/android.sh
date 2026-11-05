#!/usr/bin/env bash
# Android tool group.

install_android() {
    step "Android tooling"
    mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/android.txt")
    apt_install "${pkgs[@]}"

    install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/Android"

    if [ ! -x "$TARGET_HOME/.local/bin/frida-ps" ]; then
        if run_as_user timeout 900 pipx install frida-tools >/dev/null 2>&1; then
            ok "frida-tools (pipx)"
        else
            warn "frida-tools install failed; retry with: pipx install frida-tools"
        fi
    fi
    if [ ! -x "$TARGET_HOME/.local/bin/objection" ]; then
        if run_as_user timeout 900 pipx install objection >/dev/null 2>&1; then
            ok "objection (pipx)"
        else
            warn "objection install failed; retry with: pipx install objection"
        fi
    fi

    run_as_user adb start-server >/dev/null 2>&1 || true
}
