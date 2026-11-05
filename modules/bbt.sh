#!/usr/bin/env bash
# BBT Toolkit checkout and installation.

install_bbt() {
    step "BBT Toolkit"
    local repo="$TARGET_HOME/tools/BugBountyToolkit"
    local venv="$repo/.venv-sys"

    install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/tools"

    if [ -d "$repo/.git" ]; then
        log "Updating $repo"
        run_as_user git -C "$repo" pull --ff-only >/dev/null 2>&1 \
            || warn "git pull failed; keeping the current checkout"
    elif [ -d "$repo/bbt" ]; then
        log "Using the existing checkout at $repo"
    else
        log "Cloning $BBT_REPO_URL"
        if ! run_as_user git clone --depth 1 "$BBT_REPO_URL" "$repo"; then
            warn "BBT clone failed (network or VPN?); install it later with:"
            warn "  git clone $BBT_REPO_URL $repo"
            return 0
        fi
    fi

    if [ ! -x "$venv/bin/python" ]; then
        run_as_user python3 -m venv "$venv" \
            || { warn "could not create the BBT virtualenv"; return 0; }
    fi
    run_as_user "$venv/bin/pip" install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
    if run_as_user "$venv/bin/pip" install -e "$repo" >/dev/null 2>&1; then
        ok "BBT installed into $venv"
    else
        warn "BBT pip install failed; run it again from $repo"
        return 0
    fi

    if [ -x "$repo/scripts/install-desktop.sh" ]; then
        run_as_user bash "$repo/scripts/install-desktop.sh" >/dev/null 2>&1 \
            && ok "BBT desktop entry and PATH wrapper installed" \
            || warn "BBT desktop entry install failed"
    fi

    run_as_user "$venv/bin/python" -m bbt --version 2>/dev/null \
        | sed 's/^/    /' || true
}
