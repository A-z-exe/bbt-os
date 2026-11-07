#!/usr/bin/env bash
# BBT OS matched workflows: web, WordPress, Android and AD chains.

install_workflows() {
    step "Matched workflows"
    install -m 755 "$HERE/scripts/bbt-workflow.sh" /usr/local/bin/bbt-workflow
    install -m 755 "$HERE/scripts/bbt-surface.sh" /usr/local/bin/bbt-surface
    install -m 755 "$HERE/scripts/bbt-bounty.sh" /usr/local/bin/bbt-bounty
    install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/bbt/runs" "$TARGET_HOME/bbt/bounty"
    ok "bbt-workflow ready: web, wordpress, android and ad recipes"
    ok "bbt-surface ready: scope-gated headers, discovery and JS bundle audit"
    ok "bbt-bounty ready: programs, report gate and income ledger"
}
