#!/bin/bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

SECRET_FILE="$DIR/secret.txt"
PORT="${TG_PROXY_PORT:-1443}"
HOST="127.0.0.1"

if [ ! -s "$SECRET_FILE" ]; then
    openssl rand -hex 16 > "$SECRET_FILE"
fi
SECRET="$(tr -d '[:space:]' < "$SECRET_FILE")"

echo "============================================================"
echo "  Telegram MTProto proxy"
echo "  Сервер:  127.0.0.1     Порт: $PORT"
echo "  Secret (вводить в Telegram): dd$SECRET"
echo "    tg://proxy?server=127.0.0.1&port=$PORT&secret=dd$SECRET"
echo "============================================================"

exec python3 -m tgproxy.server --host "$HOST" --port "$PORT" --secret "$SECRET"
