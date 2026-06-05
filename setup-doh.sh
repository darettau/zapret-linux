#!/bin/bash
set -u
CFG=/etc/dnscrypt-proxy/dnscrypt-proxy.toml
RESOLV_BAK=/etc/resolv.conf.bak.zapret

log(){ printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31m!!! %s\033[0m\n' "$*"; }

if [ "${1:-}" = "--revert" ]; then
    log "Откат: возвращаю системный DNS"
    systemctl disable --now dnscrypt-proxy.service 2>/dev/null || true
    sed -i '/^nohook resolv.conf$/d' /etc/dhcpcd.conf 2>/dev/null || true
    chattr -i /etc/resolv.conf 2>/dev/null || true
    if [ -f "$RESOLV_BAK" ]; then
        cp -a "$RESOLV_BAK" /etc/resolv.conf
    else
        GW="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
        printf 'nameserver %s\n' "${GW:-1.1.1.1}" > /etc/resolv.conf
    fi
    systemctl restart dhcpcd 2>/dev/null || true
    echo "Готово. DNS возвращён к прежнему."
    exit 0
fi

[ "$(id -u)" -eq 0 ] || { err "Запускайте через sudo."; exit 1; }

log "1/6  Устанавливаю dnscrypt-proxy"
pacman -S --needed --noconfirm dnscrypt-proxy || { err "Не удалось установить пакет."; exit 1; }
mkdir -p /var/cache/dnscrypt-proxy /etc/dnscrypt-proxy

log "2/6  Делаю резервные копии"
[ -f "$CFG" ] && cp -a "$CFG" "${CFG}.bak.$(date +%s)"
[ -f "$RESOLV_BAK" ] || cp -a /etc/resolv.conf "$RESOLV_BAK"

log "3/6  Пишу конфиг (DoH: Cloudflare + Google + Quad9)"
cat > "$CFG" <<'TOML'
listen_addresses = ['127.0.0.1:53']
max_clients = 250
ipv4_servers = true
ipv6_servers = false
dnscrypt_servers = false
doh_servers = true
require_dnssec = false
require_nolog = true
require_nofilter = true
server_names = ['cloudflare', 'google', 'quad9-doh-ip4-port443-nofilter']
bootstrap_resolvers = ['9.9.9.9:53', '1.1.1.1:53']
ignore_system_dns = true
netprobe_timeout = 60
netprobe_address = '9.9.9.9:53'
cache = true
cache_size = 4096
[sources]
  [sources.public-resolvers]
    urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
    cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
    minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
    refresh_delay = 73
TOML

log "4/6  Запускаю службу dnscrypt-proxy"
systemctl disable --now dnscrypt-proxy.socket 2>/dev/null || true
systemctl enable dnscrypt-proxy.service >/dev/null 2>&1
systemctl restart dnscrypt-proxy.service
sleep 5

log "5/6  Проверяю, отвечает ли DoH на 127.0.0.1 (до переключения системы)"
ok=0
for i in 1 2 3 4 5 6; do
    if nslookup dns.google 127.0.0.1 >/dev/null 2>&1; then ok=1; break; fi
    sleep 2
done

if [ "$ok" != 1 ]; then
    err "Локальный DoH не отвечает — системный DNS НЕ трогаю (интернет цел)."
    echo "--- статус ---"; systemctl --no-pager -l status dnscrypt-proxy.service | tail -15
    echo "--- журнал ---"; journalctl -u dnscrypt-proxy -n 25 --no-pager
    exit 1
fi

log "6/6  DoH работает — переключаю систему на него"
grep -q '^nohook resolv.conf$' /etc/dhcpcd.conf 2>/dev/null || echo 'nohook resolv.conf' >> /etc/dhcpcd.conf
chattr -i /etc/resolv.conf 2>/dev/null || true
printf 'nameserver 127.0.0.1\noptions edns0\n' > /etc/resolv.conf

echo
echo "==================== РЕЗУЛЬТАТ ===================="
printf "служба dnscrypt-proxy : "; systemctl is-active dnscrypt-proxy.service
printf "слушает порт 53       : "; ss -tulnp 2>/dev/null | grep -q '127.0.0.1:53' && echo "да" || echo "НЕТ"
echo "резолв dns.google     : $(getent hosts dns.google | awk '{print $1}' | tr '\n' ' ')"
echo "резолв rutracker.org  : $(getent hosts rutracker.org | awk '{print $1}' | tr '\n' ' ')"
echo "=================================================="
echo "Если что-то не так — откат: sudo bash $0 --revert"
