#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root "$@"

ZAPRET_SRC="$SCRIPT_DIR/zapret-src"

echo "${C_BOLD}${C_BLUE}=== Установка zapret-linux ===${C_RESET}"

DISTRO="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        arch|manjaro|endeavouros|artix|cachyos) DISTRO="arch" ;;
        debian|ubuntu|linuxmint|pop|elementary) DISTRO="debian" ;;
        fedora|rhel|centos|rocky|almalinux)      DISTRO="fedora" ;;
        *)
            case "$ID_LIKE" in
                *arch*)   DISTRO="arch" ;;
                *debian*) DISTRO="debian" ;;
                *fedora*|*rhel*) DISTRO="fedora" ;;
            esac
            ;;
    esac
fi

if [ "$DISTRO" = "unknown" ]; then
    log_warn "Не удалось определить дистрибутив."
    log_warn "Установите вручную: git gcc make iptables ipset libnetfilter_queue (dev)."
else
    log_ok "Дистрибутив: $DISTRO"
fi

install_deps() {
    case "$DISTRO" in
        arch)
            log_info "Установка пакетов через pacman..."
            pacman -Sy --needed --noconfirm \
                git gcc make iptables ipset libnetfilter_queue zlib libcap
            ;;
        debian)
            log_info "Установка пакетов через apt..."
            apt-get update
            apt-get install -y \
                git gcc make iptables ipset \
                libnetfilter-queue-dev zlib1g-dev libcap-dev
            ;;
        fedora)
            log_info "Установка пакетов через dnf..."
            dnf install -y \
                git gcc make iptables ipset \
                libnetfilter_queue-devel zlib-devel libcap-devel
            ;;
        *)
            log_warn "Пропускаю установку зависимостей (неизвестный дистрибутив)."
            ;;
    esac
}
install_deps
log_ok "Зависимости установлены."

if [ ! -d "$ZAPRET_SRC/nfq" ]; then
    log_err "Не найдены исходники nfqws в $ZAPRET_SRC"
    exit 1
fi
log_ok "Исходники: $ZAPRET_SRC"

log_info "Сборка nfqws (make -C nfq)..."
make -C "$ZAPRET_SRC/nfq"

NFQWS_BUILT="$(find "$ZAPRET_SRC" -type f -name nfqws -perm -u+x 2>/dev/null | head -n1)"
if [ -z "$NFQWS_BUILT" ]; then
    log_err "Сборка не дала бинарь nfqws. Проверьте вывод make выше."
    exit 1
fi

cp -f "$NFQWS_BUILT" "$NFQWS_BIN"
chmod +x "$NFQWS_BIN"
log_ok "nfqws скопирован в $NFQWS_BIN"

prepare_bin() {
    local name="$1" dest="$2"
    local src
    src="$(find "$ZAPRET_SRC" -type f -name "$name" 2>/dev/null | head -n1)"
    if [ -n "$src" ] && [ -s "$src" ]; then
        cp -f "$src" "$dest"
        log_ok "Шаблон скопирован: $name ($(stat -c%s "$dest") байт)"
    else
        log_warn "Шаблон $name не найден — создаю заглушку (маскировка будет слабее)."
        : > "$dest"
    fi
}
prepare_bin "quic_initial_www_google_com.bin" "$BIN_QUIC"
prepare_bin "tls_clienthello_www_google_com.bin" "$BIN_TLS"

chmod +x "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/strategies/*.sh "$SCRIPT_DIR"/tg-proxy/*.sh
log_ok "Все .sh сделаны исполняемыми."

echo
log_ok "Сборка завершена."

if [ -n "$(vpn_iface)" ]; then
    log_warn "Похоже, активен VPN — автоподбор стратегии пропущен."
    log_warn "Выключите VPN и запустите: sudo ./youtube-tune.sh"
else
    log_info "Подбираю рабочую стратегию под вашего провайдера (Ctrl-C чтобы пропустить)..."
    "$SCRIPT_DIR/youtube-tune.sh" || log_warn "Автоподбор не завершился — запустите позже: sudo ./youtube-tune.sh"
fi

echo
echo "Дальше:"
echo "  • Запустить обход:          ${C_BOLD}sudo ./start.sh${C_RESET}"
echo "  • Проверить окружение:      ${C_BOLD}sudo ./service.sh check${C_RESET}"
echo "  • Автозапуск при загрузке:  ${C_BOLD}sudo ./service.sh install${C_RESET}"
