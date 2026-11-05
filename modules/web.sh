#!/usr/bin/env bash
# Web / reconnaissance tool group.

install_web() {
    step "Web / reconnaissance tooling"
    mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/web.txt")
    apt_install "${pkgs[@]}"
    refresh_web_databases
}

refresh_web_databases() {
    log "Refreshing nuclei templates, WPScan, ExploitDB and nmap scripts"

    run_as_user timeout 300 nuclei -update-templates -silent >/dev/null 2>&1 || true
    local count
    count=$(find "$TARGET_HOME/nuclei-templates" "$TARGET_HOME/.local/nuclei-templates" \
        -name '*.yaml' 2>/dev/null | wc -l)
    if [ "${count:-0}" -lt 100 ]; then
        download_nuclei_templates
    else
        ok "nuclei templates: $count files"
    fi

    run_as_user timeout 300 wpscan --update >/dev/null 2>&1 \
        || warn "wpscan database update failed"
    timeout 180 searchsploit -u >/dev/null 2>&1 \
        || warn "searchsploit update failed or timed out"
    timeout 60 nmap --script-updatedb >/dev/null 2>&1 || true
    run_as_user timeout 300 pipx upgrade-all >/dev/null 2>&1 || true
}

download_nuclei_templates() {
    log "nuclei updater left few templates; downloading the archive"
    local tmp
    tmp=$(mktemp -d)
    if curl -L --retry 3 --max-time 900 -o "$tmp/nt.zip" \
        https://github.com/projectdiscovery/nuclei-templates/archive/refs/heads/main.zip \
        && unzip -q "$tmp/nt.zip" -d "$tmp"; then
        install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.local/nuclei-templates"
        cp -a "$tmp/nuclei-templates-main/." "$TARGET_HOME/.local/nuclei-templates/"
        chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local/nuclei-templates"
        ok "nuclei templates installed from archive"
    else
        warn "nuclei template download failed"
    fi
    rm -rf "$tmp"
}
