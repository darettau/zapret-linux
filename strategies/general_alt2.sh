#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/common.sh"

require_root "$@"
print_strategy_header "general_alt2 (multisplit + seqovl)"

"$PROJECT_ROOT/stop.sh" >/dev/null 2>&1 || true
setup_iptables

ARGS=(
    --filter-udp=443
        --hostlist="$L_GENERAL"
        --hostlist="$L_GENERAL_USER"
        --hostlist-exclude="$L_EXCLUDE"
        --dpi-desync=fake --dpi-desync-repeats=6
        --dpi-desync-fake-quic="$BIN_QUIC"
    --new
    --filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun
        --dpi-desync=fake --dpi-desync-repeats=6
    --new
    --filter-tcp=80,443
        --hostlist="$L_GENERAL"
        --hostlist="$L_GENERAL_USER"
        --hostlist-exclude="$L_EXCLUDE"
        --dpi-desync=multisplit
        --dpi-desync-split-seqovl=652
        --dpi-desync-split-pos=2
        --dpi-desync-split-seqovl-pattern="$BIN_TLS"
    --new
    --filter-tcp=443
        --hostlist="$L_GOOGLE"
        --dpi-desync=multisplit
        --dpi-desync-split-seqovl=652
        --dpi-desync-split-pos=2
        --dpi-desync-split-seqovl-pattern="$BIN_TLS"
)

start_nfqws "${ARGS[@]}"
log_ok "Стратегия general_alt2 активна."
