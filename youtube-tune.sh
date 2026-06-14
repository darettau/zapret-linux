#!/bin/bash

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/common.sh"
require_root "$@"

REPORT="$ROOT/youtube-tune-report.txt"
WINNER="$ROOT/lists/youtube-winner.txt"
exec > >(tee "$REPORT") 2>&1

vif="$(vpn_iface)"
if [ -n "$vif" ]; then
    echo "Похоже, активен VPN (интерфейс $vif) — выключите его и повторите."
    exit 1
fi

TLS="$BIN_TLS"
declare -a NAME CARG
add(){ NAME+=("$1"); CARG+=("$2"); }
add "fake,fakedsplit md5sig pos1"        "--dpi-desync=fake,fakedsplit --dpi-desync-fooling=md5sig --dpi-desync-split-pos=1 --dpi-desync-fake-tls=$TLS"
add "fake,fakedsplit rndsni badseq pos1" "--dpi-desync=fake,fakedsplit --dpi-desync-fooling=badseq --dpi-desync-split-pos=1 --dpi-desync-fake-tls=$TLS --dpi-desync-fake-tls-mod=rndsni"
add "fake,multisplit rndsni 1,midsld"    "--dpi-desync=fake,multisplit --dpi-desync-fooling=badseq --dpi-desync-split-pos=1,midsld --dpi-desync-fake-tls=$TLS --dpi-desync-fake-tls-mod=rndsni"
add "fake,multidisorder md5sig 1,midsld" "--dpi-desync=fake,multidisorder --dpi-desync-fooling=md5sig --dpi-desync-split-pos=1,midsld --dpi-desync-fake-tls=$TLS"
add "multisplit seqovl652 sniext"        "--dpi-desync=multisplit --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=sniext+1 --dpi-desync-split-seqovl-pattern=$TLS"
add "fakeddisorder badseq sniext"        "--dpi-desync=fakeddisorder --dpi-desync-fooling=badseq --dpi-desync-split-pos=sniext+1"
add "multidisorder badseq 1,midsld"      "--dpi-desync=multidisorder --dpi-desync-fooling=badseq --dpi-desync-split-pos=1,midsld"
add "fakedsplit datanoack pos1"          "--dpi-desync=fakedsplit --dpi-desync-fooling=datanoack --dpi-desync-split-pos=1"
add "fake,multisplit autottl midsld"     "--dpi-desync=fake,multisplit --dpi-desync-fooling=badseq --dpi-desync-split-pos=midsld --dpi-desync-fake-tls=$TLS --dpi-desync-autottl=-1"

launch(){
    local cargs="$1"; read -ra A <<< "$cargs"
    pkill -x nfqws 2>/dev/null || true; sleep 0.4; rm -f "$PIDFILE"
    "$NFQWS_BIN" --daemon --pidfile="$PIDFILE" --qnum="$QNUM" \
        --filter-udp=443 --ipset-exclude="$IPSET_DOH" \
            --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="$BIN_QUIC" \
        --new \
        --filter-tcp=443 --hostlist="$L_GOOGLE" --ipset-exclude="$IPSET_DOH" "${A[@]}" \
        --new \
        --filter-tcp=80,443 --ipset-exclude="$IPSET_DOH" \
            --dpi-desync=fakedsplit --dpi-desync-fooling=badseq --dpi-desync-split-pos=1 \
        >>"$LOG_FILE" 2>&1
    sleep 1.2
}
probe(){ curl -4 -s -o /dev/null -m 9 -w '%{http_code}' "https://$1" 2>/dev/null; }
good(){ local c="$1"; [ -n "$c" ] && [ "$c" != "000" ]; }

echo "Подбор профиля под YouTube. Маршрут: $(ip route show default | head -1 | awk '{print $5}')"
"$ROOT/stop.sh" >/dev/null 2>&1 || true
setup_iptables >/dev/null 2>&1

best_idx=-1; declare -a R_YT R_RU
printf '\n%-3s %-34s %-10s %-10s\n' "#" "профиль" "youtube" "rutracker"
echo "------------------------------------------------------------------------"
for i in "${!NAME[@]}"; do
    launch "${CARG[$i]}"
    if ! pgrep -x nfqws >/dev/null 2>&1; then
        R_YT[$i]="—"; R_RU[$i]="—"
        printf '%-3s %-34s %-10s %-10s\n' "$((i+1))" "${NAME[$i]}" "nfqws не стартовал" "(опции?)"
        continue
    fi
    yc=$(probe www.youtube.com); rc=$(probe rutracker.org)
    good "$yc" && R_YT[$i]="OK $yc" || R_YT[$i]="FAIL"
    good "$rc" && R_RU[$i]="OK $rc" || R_RU[$i]="FAIL"
    printf '%-3s %-34s %-10s %-10s\n' "$((i+1))" "${NAME[$i]}" "${R_YT[$i]}" "${R_RU[$i]}"
    if good "$yc" && [ "$best_idx" -lt 0 ]; then
        best_idx=$i
    fi
done

echo "------------------------------------------------------------------------"
if [ "$best_idx" -lt 0 ]; then
    echo
    echo "Ни один профиль не пробил YouTube по TCP — вероятно, режут жёстче (или по IP)."
    echo "Оставляю рабочий профиль для остальных сайтов (стратегия 7)."
    "$ROOT/start.sh" 7 >/dev/null 2>&1 || true
    echo "Отчёт: $REPORT"
    exit 2
fi

echo
echo "Победитель: #$((best_idx+1))  ${NAME[$best_idx]}  (youtube=${R_YT[$best_idx]})"
printf '%s\n' "${CARG[$best_idx]}" > "$WINNER"

"$ROOT/start.sh" 8 >/dev/null 2>&1 || true
echo
echo "Профиль записан в $WINNER и применён."
echo "Теперь 'sudo ./start.sh' по умолчанию запускает именно его. Отчёт: $REPORT"
