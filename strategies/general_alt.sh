#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/common.sh"

require_root "$@"
print_strategy_header "general_alt (альтернатива 1)"

"$PROJECT_ROOT/stop.sh" >/dev/null 2>&1 || true
setup_iptables

ARGS=(
    --filter-udp=443
        --hostlist="$L_GENERAL"
        --hostlist="$L_GENERAL_USER"
        --hostlist-exclude="$L_EXCLUDE"
        --dpi-desync=fake --dpi-desync-repeats=8
        --dpi-desync-fake-quic="$BIN_QUIC"
    --new
    --filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun
        --dpi-desync=fake --dpi-desync-repeats=8
    --new
    --filter-tcp=80,443
        --hostlist="$L_GENERAL"
        --hostlist="$L_GENERAL_USER"
        --hostlist-exclude="$L_EXCLUDE"
        --dpi-desync=multidisorder
        --dpi-desync-split-pos=1,midsld
    --new
    --filter-tcp=443
        --hostlist="$L_GOOGLE"
        --dpi-desync=multidisorder
        --dpi-desync-split-pos=1,midsld
)

start_nfqws "${ARGS[@]}"
log_ok "Стратегия general_alt активна."
