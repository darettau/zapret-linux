#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/common.sh"
REPORT="$ROOT/diagnose-report.txt"
exec > >(tee "$REPORT") 2>&1

[ "$(id -u)" -eq 0 ] || { echo "Запускайте через sudo."; exit 1; }

SITES=(rutracker.org www.youtube.com rutube.ru)
sec(){ echo; echo "════════ $* ════════"; }

test_site(){
    local h="$1" code err
    code=$(curl -4 -sS -o /dev/null -m 12 -w '%{http_code}' "https://$h" 2>/tmp/_curlerr) || true
    err=$(grep -ioE 'could not resolve|timed out|refused|reset by peer|ssl|handshake|recv failure|unreachable' /tmp/_curlerr | head -1)
    if [ "$code" != "000" ] && [ -n "$code" ]; then
        printf '  %-22s OK   HTTP %s\n' "$h" "$code"
    else
        printf '  %-22s FAIL (%s)\n' "$h" "${err:-неизвестно}"
    fi
}

sec "0. VPN должен быть выключен"
vif="$(vpn_iface)"
if [ -n "$vif" ]; then
    echo "  Похоже, активен VPN (интерфейс $vif). Выключите его и запустите снова."
    exit 1
fi
echo "  default route: $(ip route show default | head -1)"
echo "  путь к 1.1.1.1: $(ip route get 1.1.1.1 2>/dev/null | head -1)"

sec "1. DNS / DoH"
echo "  служба dnscrypt: $(systemctl is-active dnscrypt-proxy.service 2>/dev/null)"
ss -tulnp 2>/dev/null | grep -q '127.0.0.1:53' && echo "  слушает :53 — да" || echo "  слушает :53 — НЕТ"
echo "  /etc/resolv.conf: $(grep -v '^#' /etc/resolv.conf | tr '\n' ' ')"
for d in "${SITES[@]}"; do
    ip=$(timeout 6 getent ahostsv4 "$d" 2>/dev/null | awk 'NR==1{print $1}')
    printf '  resolve %-20s %s\n' "$d" "${ip:-FAIL (DNS не отвечает)}"
done

sec "2. Без обхода (zapret остановлен)"
bash "$ROOT/stop.sh" >/dev/null 2>&1 || true
sleep 1
for h in "${SITES[@]}"; do test_site "$h"; done

sec "3. Со стратегией 7"
bash "$ROOT/start.sh" 7 >/dev/null 2>&1 || true
sleep 2
pgrep -x nfqws >/dev/null && echo "  nfqws: запущен" || echo "  nfqws: НЕ запущен (!)"
ip=$(timeout 6 getent ahostsv4 dns.google 2>/dev/null | awk 'NR==1{print $1}')
echo "  DNS при обходе (resolve dns.google): ${ip:-сломан обходом!}"
for h in "${SITES[@]}"; do test_site "$h"; done

sec "Итог"
echo "  Сравните разделы 2 и 3:"
echo "   • FAIL в обоих + 'could not resolve' → проблема DNS."
echo "   • FAIL без обхода, OK с обходом       → обход работает."
echo "   • OK без обхода, FAIL с обходом        → обход ломает сайты (нужно мягче)."
echo "   • FAIL в обоих + 'reset/timed out'     → нужна другая десинхронизация."
echo
echo "  Отчёт: $REPORT"
