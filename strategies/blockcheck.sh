#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/common.sh"

require_root "$@"
print_strategy_header "blockcheck (подобрано под провайдера)"

"$PROJECT_ROOT/stop.sh" >/dev/null 2>&1 || true
setup_iptables

ARGS=(
    --filter-udp=443
        --ipset-exclude="$IPSET_DOH"
        --dpi-desync=fake --dpi-desync-repeats=6
        --dpi-desync-fake-quic="$BIN_QUIC"
    --new
)

WINNER_FILE="$PROJECT_ROOT/lists/youtube-winner.txt"
if [ -s "$WINNER_FILE" ]; then
    YT_ARGS=()
    read -ra YT_ARGS < "$WINNER_FILE" || true
    if [ "${#YT_ARGS[@]}" -gt 0 ]; then
        log_info "Google/YouTube: профиль из $(basename "$WINNER_FILE")"
        ARGS+=(
            --filter-tcp=443
                --hostlist="$L_GOOGLE"
                --ipset-exclude="$IPSET_DOH"
                "${YT_ARGS[@]}"
            --new
        )
    fi
fi

ARGS+=(
    --filter-tcp=80,443
        --ipset-exclude="$IPSET_DOH"
        --dpi-desync=fakedsplit
        --dpi-desync-fooling=badseq
        --dpi-desync-split-pos=1
)

start_nfqws "${ARGS[@]}"
log_ok "Стратегия blockcheck активна. Выключите VPN и проверяйте сайты/YouTube."
