#!/usr/bin/env bash
# BBT OS matched workflows: web, WordPress, Android and AD chains.

install_workflows() {
    step "Matched workflows"
    install -m 755 "$HERE/scripts/bbt-workflow.sh" /usr/local/bin/bbt-workflow
    install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/bbt/runs"
    ok "bbt-workflow ready: web, wordpress, android and ad recipes"
}
