#!/bin/bash

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_BOLD=$'\033[1m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

log_ok()   { echo "${C_GREEN}[OK]${C_RESET}   $*"; }
log_err()  { echo "${C_RED}[ОШИБКА]${C_RESET} $*" >&2; }
log_warn() { echo "${C_YELLOW}[ВНИМАНИЕ]${C_RESET} $*"; }
log_info() { echo "${C_BLUE}[ИНФО]${C_RESET} $*"; }

COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$COMMON_SH_DIR"

QNUM=200
NFQWS_BIN="$PROJECT_ROOT/bin/nfqws"
PIDFILE="/tmp/zapret.pid"
STATE_FILE="/tmp/zapret.strategy"
LOG_FILE="$PROJECT_ROOT/zapret.log"
SERVICE_NAME="zapret"

ZAPRET_STRATEGIES=(
    "general"
    "general_alt"
    "general_alt2"
    "general_fake"
    "simple_fake"
    "telegram"
    "blockcheck"
    "youtube"
)
ZAPRET_DESCRIPTIONS=(
    "базовая (split2) — универсальный стартовый вариант"
    "альтернатива 1 (multidisorder) — если базовая не помогает"
    "альтернатива 2 (multisplit+seqovl)"
    "fake (поддельный TLS/QUIC)"
    "упрощённая fake — без хостлистов, ко всему трафику"
    "клиент Telegram — локальный MTProto-прокси"
    "подобрано под провайдера (замена VPN)"
    "сайты + YouTube — подобрано под провайдера (по умолчанию)"
)
ZAPRET_DEFAULT_INDEX=8

L_GENERAL="$PROJECT_ROOT/lists/list-general.txt"
L_GENERAL_USER="$PROJECT_ROOT/lists/list-general-user.txt"
L_EXCLUDE="$PROJECT_ROOT/lists/list-exclude.txt"
L_EXCLUDE_USER="$PROJECT_ROOT/lists/list-exclude-user.txt"
L_GOOGLE="$PROJECT_ROOT/lists/list-google.txt"
IPSET_ALL="$PROJECT_ROOT/lists/ipset-all.txt"
IPSET_EXCLUDE="$PROJECT_ROOT/lists/ipset-exclude.txt"
IPSET_DOH="$PROJECT_ROOT/lists/ipset-doh.txt"

BIN_QUIC="$PROJECT_ROOT/bin/quic_initial_www_google_com.bin"
BIN_TLS="$PROJECT_ROOT/bin/tls_clienthello_www_google_com.bin"

TCP_PORTS="80,443,2053,2083,2087,2096,8443"
UDP_PORTS="443,19294:19344,50000:50100"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_err "Этот скрипт нужно запускать от root. Используйте: sudo $0 $*"
        exit 1
    fi
}

setup_iptables() {
    log_info "Настройка правил iptables (mangle/OUTPUT, очередь $QNUM)..."

    iptables -t mangle -A OUTPUT -p tcp -m multiport --dports "$TCP_PORTS" \
        -j NFQUEUE --queue-num "$QNUM" --queue-bypass

    iptables -t mangle -A OUTPUT -p udp -m multiport --dports "$UDP_PORTS" \
        -j NFQUEUE --queue-num "$QNUM" --queue-bypass

    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -t mangle -A OUTPUT -p tcp -m multiport --dports "$TCP_PORTS" \
            -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null || true
        ip6tables -t mangle -A OUTPUT -p udp -m multiport --dports "$UDP_PORTS" \
            -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null || true
    fi

    log_ok "Правила iptables добавлены."
}

start_nfqws() {
    if [ ! -x "$NFQWS_BIN" ]; then
        log_err "Бинарь nfqws не найден: $NFQWS_BIN"
        log_err "Сначала выполните установку: sudo ./install.sh"
        exit 1
    fi

    log_info "Запуск nfqws (очередь $QNUM)..."
    "$NFQWS_BIN" \
        --daemon \
        --pidfile="$PIDFILE" \
        --qnum="$QNUM" \
        "$@" >>"$LOG_FILE" 2>&1

    sleep 1
    if check_nfqws_running; then
        local caller
        caller="$(basename "${BASH_SOURCE[1]:-}" .sh 2>/dev/null)"
        [ -n "$caller" ] && echo "$caller" > "$STATE_FILE" 2>/dev/null || true
        log_ok "nfqws запущен (PID $(cat "$PIDFILE" 2>/dev/null))."
        log_info "Лог: $LOG_FILE"
    else
        log_err "Не удалось запустить nfqws. Смотрите лог: $LOG_FILE"
        exit 1
    fi
}

check_nfqws_running() {
    [ -f "$PIDFILE" ] || return 1
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

vpn_iface() {
    ip route show default 2>/dev/null \
        | grep -oE 'dev [a-z0-9]+' | awk '{print $2}' \
        | grep -iE '^(tun|tap|wg|nordlynx|proton|wgcf|ipsec|ppp|utun|neko)' | head -1
}

print_strategy_header() {
    echo "${C_BOLD}${C_BLUE}=== zapret-linux :: стратегия: $1 ===${C_RESET}"
}
