#!/usr/bin/env bash
# MobSF through Docker.

install_mobsf() {
    step "MobSF (Docker)"

    if ! command -v docker >/dev/null 2>&1; then
        apt_install docker.io || { warn "docker unavailable; MobSF skipped"; return 0; }
    fi
    systemctl enable --now docker >/dev/null 2>&1 \
        || warn "could not enable the Docker service"

    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker "$TARGET_USER" >/dev/null 2>&1 \
            || warn "could not add $TARGET_USER to the docker group"
    fi

    install -m 755 "$HERE/scripts/bbt-os-mobsf.sh" /usr/local/bin/mobsf
    ok "mobsf helper installed"

    if [ "${BBT_MOBSF_PULL:-1}" != "1" ]; then
        log "MobSF image pull skipped (BBT_MOBSF_PULL=0)"
        return 0
    fi
    if timeout 60 docker image inspect "$MOBSF_IMAGE" >/dev/null 2>&1; then
        ok "MobSF image already present"
    elif timeout 1200 docker pull "$MOBSF_IMAGE" >/dev/null 2>&1; then
        ok "MobSF image pulled"
    else
        warn "MobSF image pull failed; run: sudo docker pull $MOBSF_IMAGE"
    fi
}
