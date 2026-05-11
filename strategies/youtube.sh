#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/common.sh"

require_root "$@"
print_strategy_header "youtube (сайты + YouTube/Google)"

"$PROJECT_ROOT/stop.sh" >/dev/null 2>&1 || true
setup_iptables

YT=(--dpi-desync=multidisorder --dpi-desync-fooling=badseq --dpi-desync-split-pos=1,midsld)
WINNER="$PROJECT_ROOT/lists/youtube-winner.txt"
[ -s "$WINNER" ] && read -ra YT < "$WINNER" || true

ARGS=(
    --filter-udp=443
        --ipset-exclude="$IPSET_DOH"
        --dpi-desync=fake --dpi-desync-repeats=6
        --dpi-desync-fake-quic="$BIN_QUIC"
    --new
    --filter-tcp=443
        --hostlist="$L_GOOGLE"
        --ipset-exclude="$IPSET_DOH"
        "${YT[@]}"
    --new
    --filter-tcp=80,443
        --ipset-exclude="$IPSET_DOH"
        --dpi-desync=fakedsplit
        --dpi-desync-fooling=badseq
        --dpi-desync-split-pos=1
)

start_nfqws "${ARGS[@]}"
log_ok "Стратегия youtube активна. Выключите VPN. Проверяйте сайты и YouTube."
