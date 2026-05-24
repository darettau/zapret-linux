#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

cmd_install() {
    require_root "install"

    local strategy="${1:-youtube}"
    local strat_script="$SCRIPT_DIR/strategies/${strategy}.sh"

    if [ ! -f "$strat_script" ]; then
        log_err "Стратегия '$strategy' не найдена: $strat_script"
        echo "Доступные стратегии:"
        ls -1 "$SCRIPT_DIR/strategies/" | sed 's/\.sh$//;s/^/  - /'
        exit 1
    fi

    if [ ! -x "$NFQWS_BIN" ]; then
        log_warn "Бинарь nfqws ещё не собран ($NFQWS_BIN)."
        log_warn "Сервис создастся, но не запустится, пока не сделаете ./install.sh"
    fi

    log_info "Создаю systemd-юнит: $UNIT_PATH"
    log_info "Стратегия автозапуска: $strategy"

    cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Zapret DPI bypass
After=network.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=$PIDFILE
ExecStart=$strat_script
ExecStop=$SCRIPT_DIR/stop.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    log_ok "Юнит создан."

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    log_ok "Автозапуск включён (systemctl enable $SERVICE_NAME)."

    if [ -x "$NFQWS_BIN" ]; then
        systemctl restart "$SERVICE_NAME"
        sleep 1
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_ok "Сервис запущен."
        else
            log_err "Сервис не запустился. Логи: journalctl -u $SERVICE_NAME -e"
        fi
    fi

    log_info "Управление: systemctl {start|stop|status} $SERVICE_NAME"
}

cmd_remove() {
    require_root "remove"

    if [ -f "$UNIT_PATH" ]; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$UNIT_PATH"
        systemctl daemon-reload
        log_ok "Сервис $SERVICE_NAME остановлен и удалён."
    else
        log_warn "Юнит $UNIT_PATH не найден — нечего удалять."
    fi

    "$SCRIPT_DIR/stop.sh" >/dev/null 2>&1 || true
    log_ok "Очистка завершена."
}

cmd_status() {
    echo "${C_BOLD}${C_BLUE}=== Статус zapret-linux ===${C_RESET}"

    if [ -f "$UNIT_PATH" ]; then
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_ok "systemd-сервис: активен (active)"
        else
            log_warn "systemd-сервис: установлен, но не активен"
        fi
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            log_ok "автозапуск: включён (enabled)"
        else
            log_warn "автозапуск: выключен"
        fi
    else
        log_info "systemd-сервис не установлен (см. ./service.sh install)"
    fi

    if check_nfqws_running; then
        log_ok "демон nfqws: запущен (PID $(cat "$PIDFILE"))"
    elif pgrep -x nfqws >/dev/null 2>&1; then
        log_warn "nfqws запущен, но pid-файл не совпадает (PID $(pgrep -x nfqws | tr '\n' ' '))"
    else
        log_warn "демон nfqws: не запущен"
    fi

    local rules
    rules="$(iptables -t mangle -S OUTPUT 2>/dev/null | grep -c "NFQUEUE --queue-num $QNUM" || true)"
    if [ "${rules:-0}" -gt 0 ]; then
        log_ok "правила iptables: найдено $rules (очередь $QNUM)"
        iptables -t mangle -S OUTPUT | grep "NFQUEUE --queue-num $QNUM" | sed 's/^/      /'
    else
        log_warn "правила iptables (NFQUEUE, очередь $QNUM): отсутствуют"
    fi
}

cmd_check() {
    echo "${C_BOLD}${C_BLUE}=== Диагностика zapret-linux ===${C_RESET}"
    local ok=1

    if [ -x "$NFQWS_BIN" ]; then
        log_ok "nfqws найден: $NFQWS_BIN"
    else
        log_err "nfqws НЕ найден ($NFQWS_BIN) — выполните ./install.sh"
        ok=0
    fi

    for f in "$BIN_QUIC" "$BIN_TLS"; do
        if [ -s "$f" ]; then
            log_ok "шаблон присутствует: $(basename "$f") ($(stat -c%s "$f") байт)"
        else
            log_warn "шаблон отсутствует/пуст: $(basename "$f")"
        fi
    done

    if command -v iptables >/dev/null 2>&1; then
        log_ok "iptables: $(command -v iptables)"
    else
        log_err "iptables не установлен"
        ok=0
    fi

    if command -v ipset >/dev/null 2>&1; then
        log_ok "ipset: $(command -v ipset)"
    else
        log_warn "ipset не установлен (нужен только при работе с ipset-списками)"
    fi

    if lsmod 2>/dev/null | grep -q nfnetlink_queue; then
        log_ok "модуль ядра nfnetlink_queue: загружен"
    elif modinfo nfnetlink_queue >/dev/null 2>&1; then
        log_warn "nfnetlink_queue не загружен, но доступен (загрузится автоматически)"
    else
        log_warn "не удалось подтвердить поддержку NFQUEUE в ядре"
    fi

    if [ -s "$L_GENERAL" ]; then
        log_ok "список list-general.txt: $(grep -cve '^\s*$' "$L_GENERAL") доменов"
    else
        log_warn "список list-general.txt пуст или отсутствует"
    fi

    echo
    if [ "$ok" -eq 1 ]; then
        log_ok "Базовая проверка пройдена. Можно запускать: sudo ./start.sh"
    else
        log_err "Есть проблемы (см. выше). Начните с: sudo ./install.sh"
        return 1
    fi
}

case "${1:-}" in
    install) shift; cmd_install "$@" ;;
    remove)  cmd_remove ;;
    status)  cmd_status ;;
    check)   cmd_check ;;
    *)
        echo "Использование: $0 {install [стратегия]|remove|status|check}"
        echo
        echo "  install [стратегия]  установить и включить автозапуск"
        echo "                       (по умолчанию: youtube)"
        echo "  remove               удалить сервис"
        echo "  status               показать текущий статус"
        echo "  check                диагностика окружения"
        exit 1
        ;;
esac
