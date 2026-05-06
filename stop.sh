#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root "$@"

print_strategy_header "СТОП"

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        log_ok "Демон nfqws (PID $PID) остановлен."
    fi
    rm -f "$PIDFILE"
fi

if pgrep -x nfqws >/dev/null 2>&1; then
    pkill -x nfqws 2>/dev/null || true
    log_ok "Дополнительные процессы nfqws завершены."
else
    log_info "Активных процессов nfqws не найдено."
fi

TG_PROXY_PID="/tmp/tg-proxy.pid"
if [ -f "$TG_PROXY_PID" ]; then
    TP="$(cat "$TG_PROXY_PID" 2>/dev/null || true)"
    [ -n "$TP" ] && kill "$TP" 2>/dev/null || true
    rm -f "$TG_PROXY_PID"
fi
if pgrep -f 'tgproxy.server' >/dev/null 2>&1; then
    pkill -f 'tgproxy.server' 2>/dev/null || true
    log_ok "Telegram-прокси остановлен."
fi

remove_rule() {
    local ipt="$1" proto="$2" ports="$3"
    while "$ipt" -t mangle -C OUTPUT -p "$proto" -m multiport --dports "$ports" \
            -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null; do
        "$ipt" -t mangle -D OUTPUT -p "$proto" -m multiport --dports "$ports" \
            -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null || break
    done
}

remove_rule iptables tcp "$TCP_PORTS"
remove_rule iptables udp "$UDP_PORTS"

if command -v ip6tables >/dev/null 2>&1; then
    remove_rule ip6tables tcp "$TCP_PORTS"
    remove_rule ip6tables udp "$UDP_PORTS"
fi

rm -f "$STATE_FILE"

log_ok "Правила iptables (NFQUEUE, очередь $QNUM) удалены."
log_ok "Обход DPI остановлен. Трафик идёт напрямую."
