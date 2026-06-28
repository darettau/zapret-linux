#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root "$@"

STRATEGIES=("${ZAPRET_STRATEGIES[@]}")
DESCRIPTIONS=("${ZAPRET_DESCRIPTIONS[@]}")
DEFAULT_INDEX="$ZAPRET_DEFAULT_INDEX"

run_by_index() {
    local idx="$1"
    local name="${STRATEGIES[$((idx - 1))]}"
    local script="$SCRIPT_DIR/strategies/${name}.sh"
    if [ ! -f "$script" ]; then
        log_err "Скрипт стратегии не найден: $script"
        exit 1
    fi
    log_info "Запускаю стратегию №$idx: $name"
    exec "$script" "$@"
}

if [ -n "$1" ]; then
    arg="$1"
    if [[ "$arg" =~ ^[1-8]$ ]]; then
        run_by_index "$arg"
    else
        for i in "${!STRATEGIES[@]}"; do
            if [ "${STRATEGIES[$i]}" = "$arg" ]; then
                run_by_index "$((i + 1))"
            fi
        done
        log_err "Неизвестная стратегия: $arg"
        echo "Доступны: ${STRATEGIES[*]}"
        exit 1
    fi
fi

echo "${C_BOLD}${C_BLUE}=== zapret-linux :: выбор стратегии обхода DPI ===${C_RESET}"
echo
for i in "${!STRATEGIES[@]}"; do
    n=$((i + 1))
    mark=""
    [ "$n" -eq "$DEFAULT_INDEX" ] && mark=" ${C_GREEN}[по умолчанию]${C_RESET}"
    printf "  ${C_BOLD}%d${C_RESET}) %-14s — %s%s\n" \
        "$n" "${STRATEGIES[$i]}" "${DESCRIPTIONS[$i]}" "$mark"
done
echo
read -rp "Выберите стратегию [1-8, Enter = $DEFAULT_INDEX]: " choice
choice="${choice:-$DEFAULT_INDEX}"

if [[ ! "$choice" =~ ^[1-8]$ ]]; then
    log_err "Неверный выбор: $choice"
    exit 1
fi

run_by_index "$choice"
