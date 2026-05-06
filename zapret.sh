#!/bin/bash

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CLI_LINK="/usr/local/bin/zapret"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
priv() { $SUDO "$@"; }

L() { printf '%s\033[K\n' "$*"; }

zapret_running() { pgrep -x nfqws >/dev/null 2>&1; }
tg_proxy_running() { pgrep -f 'tgproxy.server' >/dev/null 2>&1; }

current_strategy() {
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" 2>/dev/null
}

service_installed() { [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; }

strategy_index() {
    local i
    for i in "${!ZAPRET_STRATEGIES[@]}"; do
        [ "${ZAPRET_STRATEGIES[$i]}" = "$1" ] && { echo "$((i + 1))"; return; }
    done
}

active_label() {
    local parts=()
    if zapret_running; then
        local name; name="$(current_strategy)"
        if [ -n "$name" ]; then
            local num; num="$(strategy_index "$name")"
            parts+=("${name}${num:+($num)}")
        else
            parts+=("nfqws(?)")
        fi
    fi
    tg_proxy_running && parts+=("telegram(6)")
    local IFS='/'
    echo "${parts[*]}"
}

banner() {
    L "${C_BOLD}${C_BLUE}"
    L "   ████████  █████  ██████  ██████  ███████ ████████"
    L "       ███  ██   ██ ██   ██ ██   ██ ██         ██"
    L "     ███    ███████ ██████  ██████  █████      ██"
    L "   ███      ██   ██ ██      ██   ██ ██         ██"
    L "   ████████ ██   ██ ██      ██   ██ ███████    ██"
    L "${C_RESET}                                     ${C_BOLD}by darettau${C_RESET}"
    L ""
    if zapret_running || tg_proxy_running; then
        L "   статус: ${C_GREEN}${C_BOLD}● работает${C_RESET}  ·  стратегии: ${C_BOLD}$(active_label)${C_RESET}"
    else
        L "   статус: ${C_RED}${C_BOLD}○ остановлено${C_RESET}  ·  трафик идёт напрямую"
    fi
    if service_installed; then
        L "   автозапуск (systemd): ${C_GREEN}установлен${C_RESET}"
    fi
    L ""
}

screen() { clear; banner; }

pause() {
    echo
    read -rsn1 -p "${C_YELLOW}Нажмите любую клавишу, чтобы вернуться в меню…${C_RESET}"
}

menu() {
    local title="$1"; shift
    local __res="$1"; shift
    local items=("$@")
    local n=${#items[@]}
    local sel=0 key k2 i

    printf '\033[?25l\033[2J'
    trap 'printf "\033[?25h"' RETURN

    while true; do
        printf '\033[H'
        banner
        L "   ${C_BOLD}${title}${C_RESET}"
        L ""
        for ((i = 0; i < n; i++)); do
            if ((i == sel)); then
                L "   ${C_GREEN}${C_BOLD}❯ ${items[$i]}${C_RESET}"
            else
                L "     ${items[$i]}"
            fi
        done
        L ""
        L "   ${C_YELLOW}↑/↓ — выбор · Enter — ок · q — назад/выход${C_RESET}"
        printf '\033[J'

        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.05 k2
                case "$k2" in
                    '[A') ((sel--)); ((sel < 0)) && sel=$((n - 1)) ;;
                    '[B') ((sel++)); ((sel >= n)) && sel=0 ;;
                    '') printf '\033[?25h'; return 255 ;;
                esac
                ;;
            k|w|K|W) ((sel--)); ((sel < 0)) && sel=$((n - 1)) ;;
            j|s|J|S) ((sel++)); ((sel >= n)) && sel=0 ;;
            q|Q)     printf '\033[?25h'; return 255 ;;
            '')      printf -v "$__res" '%s' "$sel"; printf '\033[?25h'; return 0 ;;
        esac
    done
}

action_start() {
    local labels=() i
    for i in "${!ZAPRET_STRATEGIES[@]}"; do
        local mark=""
        [ "$((i + 1))" -eq "$ZAPRET_DEFAULT_INDEX" ] && mark="  ${C_GREEN}[по умолчанию]${C_RESET}"
        labels+=("$(printf '%-14s — %s%s' "${ZAPRET_STRATEGIES[$i]}" "${ZAPRET_DESCRIPTIONS[$i]}" "$mark")")
    done

    local choice
    menu "Стратегия обхода (telegram(6) можно добавить поверх основной):" choice "${labels[@]}" || return 0

    local name="${ZAPRET_STRATEGIES[$choice]}"
    screen
    echo "   ${C_BOLD}Запуск стратегии: ${name}${C_RESET}"
    echo
    priv "$SCRIPT_DIR/strategies/${name}.sh"
    pause
}

action_stop() {
    screen
    echo "   ${C_BOLD}Остановка обхода DPI${C_RESET}"
    echo
    priv "$SCRIPT_DIR/stop.sh"
    pause
}

action_status() {
    screen
    priv "$SCRIPT_DIR/service.sh" status
    pause
}

action_diagnose() {
    screen
    if [ -x "$SCRIPT_DIR/diagnose.sh" ]; then
        priv "$SCRIPT_DIR/diagnose.sh"
    else
        priv "$SCRIPT_DIR/service.sh" check
    fi
    pause
}

action_log() {
    screen
    echo "   ${C_BOLD}Последние строки лога ($LOG_FILE):${C_RESET}"
    echo
    if [ -f "$LOG_FILE" ]; then
        priv tail -n 30 "$LOG_FILE"
    else
        log_warn "Лог-файл ещё не создан."
    fi
    pause
}

action_autostart() {
    local choice
    local opts=(
        "Установить автозапуск (выбрать стратегию)"
        "Удалить автозапуск"
        "Назад"
    )
    menu "Автозапуск через systemd:" choice "${opts[@]}" || return 0
    case "$choice" in
        0)
            local labels=() i
            for i in "${!ZAPRET_STRATEGIES[@]}"; do
                labels+=("$(printf '%-14s — %s' "${ZAPRET_STRATEGIES[$i]}" "${ZAPRET_DESCRIPTIONS[$i]}")")
            done
            local s
            menu "Стратегия для автозапуска:" s "${labels[@]}" || return 0
            screen
            priv "$SCRIPT_DIR/service.sh" install "${ZAPRET_STRATEGIES[$s]}"
            pause
            ;;
        1)
            screen
            priv "$SCRIPT_DIR/service.sh" remove
            pause
            ;;
    esac
}

action_install_cli() {
    screen
    echo "   ${C_BOLD}Установка глобальной команды zapret${C_RESET}"
    echo
    if [ -L "$CLI_LINK" ] && [ "$(readlink -f "$CLI_LINK")" = "$SELF" ]; then
        log_ok "Команда уже установлена: $CLI_LINK"
    else
        if priv ln -sf "$SELF" "$CLI_LINK"; then
            log_ok "Готово. Теперь из любой директории можно запускать: ${C_BOLD}zapret${C_RESET}"
        else
            log_err "Не удалось создать симлинк $CLI_LINK"
        fi
    fi
    pause
}

main_menu() {
    local opts=(
        "Запустить / сменить стратегию"
        "Остановить обход"
        "Статус (подробно)"
        "Диагностика"
        "Показать лог"
        "Автозапуск (systemd)"
        "Установить команду zapret в систему"
        "Выход"
    )
    while true; do
        local choice
        menu "Главное меню:" choice "${opts[@]}"
        [ $? -ne 0 ] && { clear; exit 0; }
        case "$choice" in
            0) action_start ;;
            1) action_stop ;;
            2) action_status ;;
            3) action_diagnose ;;
            4) action_log ;;
            5) action_autostart ;;
            6) action_install_cli ;;
            7) clear; exit 0 ;;
        esac
    done
}

main_menu
