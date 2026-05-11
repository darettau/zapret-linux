#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/common.sh"

require_root "$@"
print_strategy_header "telegram (MTProto-прокси)"

PROXY_DIR="$PROJECT_ROOT/tg-proxy"
PROXY_SCRIPT="$PROXY_DIR/run.sh"
PROXY_PID="/tmp/tg-proxy.pid"
PROXY_LOG="/tmp/tg-proxy.log"
PORT="${TG_PROXY_PORT:-1443}"

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    log_err "Не удалось определить обычного пользователя (SUDO_USER пуст)."
    log_err "Запускайте через sudo от своего пользователя: sudo ./start.sh 6"
    exit 1
fi

if [ ! -x "$PROXY_SCRIPT" ]; then
    log_err "Не найден скрипт прокси: $PROXY_SCRIPT"
    exit 1
fi

if [ -f "$PROXY_PID" ]; then
    oldpid="$(cat "$PROXY_PID" 2>/dev/null || true)"
    [ -n "$oldpid" ] && kill "$oldpid" 2>/dev/null || true
    rm -f "$PROXY_PID"
fi
pkill -f 'tgproxy.server' 2>/dev/null || true
sleep 0.3

if ! check_nfqws_running; then
    log_warn "nfqws не запущен — сначала запустите общую стратегию: sudo ./start.sh 8"
fi

log_info "Запускаю прокси от '$REAL_USER' на 127.0.0.1:$PORT ..."
sudo -u "$REAL_USER" -H setsid bash -lc \
    "exec env TG_PROXY_PORT='$PORT' '$PROXY_SCRIPT' >'$PROXY_LOG' 2>&1" &
disown 2>/dev/null || true

proxy_pid=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    proxy_pid="$(pgrep -u "$REAL_USER" -f 'tgproxy.server' | head -1)"
    [ -n "$proxy_pid" ] && break
done

if [ -z "$proxy_pid" ]; then
    log_err "Прокси не поднялся. Лог: $PROXY_LOG"
    tail -n 15 "$PROXY_LOG" 2>/dev/null || true
    exit 1
fi
echo "$proxy_pid" > "$PROXY_PID"

SECRET="$(tr -d '[:space:]' < "$PROXY_DIR/secret.txt" 2>/dev/null)"
log_ok "Прокси запущен (PID $proxy_pid). Лог: $PROXY_LOG"
echo
echo "${C_BOLD}Telegram → Settings → Advanced → Connection type → Use proxy:${C_RESET}"
echo "    MTProto,  server: 127.0.0.1,  port: $PORT,  secret: ${C_BOLD}dd${SECRET}${C_RESET}"
echo "  или ссылка:"
echo "    ${C_BLUE}tg://proxy?server=127.0.0.1&port=${PORT}&secret=dd${SECRET}${C_RESET}"
echo
log_info "Прокси работает в фоне. Остановить: sudo ./stop.sh"
