# zapret-linux

Обход DPI-блокировок (Telegram, YouTube, Discord и др.) на Linux.
Трафик перехватывается через `iptables` + NFQUEUE, десинхронизацию делает
демон `nfqws`. Основной дистрибутив — Arch, поддержаны также Debian/Ubuntu и Fedora.

> Инструмент для восстановления доступа к легальным сервисам в обход
> неправомерных блокировок. Используйте по законам своей страны.

## Установка

```bash
git clone https://github.com/darettau/zapret-linux && cd zapret-linux && sudo ./install.sh
```

`install.sh` ставит зависимости, собирает `nfqws` из `zapret-src/` и в конце сам
подбирает рабочую десинхронизацию под вашего провайдера (нужен выключенный VPN).
Дальше `./start.sh` по умолчанию запускает подобранный профиль. Переподобрать
позже: `sudo ./youtube-tune.sh`.

## Запуск

```bash
sudo ./start.sh             # меню выбора стратегии
sudo ./start.sh 8           # сразу по номеру
sudo ./start.sh youtube     # или по имени
sudo ./stop.sh              # остановить и снять правила
```

## Стратегии

| # | Стратегия | Описание |
|---|-----------|----------|
| 1 | `general` | Базовая (`split2`), универсальный старт. |
| 2 | `general_alt` | `multidisorder` — если базовая не помогает. |
| 3 | `general_alt2` | `multisplit` + `seqovl`. |
| 4 | `general_fake` | Поддельный TLS/QUIC. |
| 5 | `simple_fake` | Ко всему трафику, без списков доменов. |
| 6 | `telegram` | Локальный MTProto-прокси для клиента Telegram. |
| 7 | `blockcheck` | Подобрано под провайдера. |
| 8 | `youtube` | Сайты + YouTube/Google, по умолчанию. |

DPI у провайдеров разный — если одна стратегия не помогает, пробуйте другую.

## Автозапуск (systemd)

```bash
sudo ./service.sh install              # стратегия youtube по умолчанию
sudo ./service.sh install general_fake # другая стратегия
sudo ./service.sh remove
systemctl status zapret
```

## Списки доменов

В `lists/`: `list-general.txt` — основной список, `list-general-user.txt` — ваши
домены (не перезаписывается), `list-exclude*.txt` — исключения, `list-google.txt`
— домены Google/YouTube, `ipset-*.txt` — обход и исключения по IP.

Чтобы разблокировать свой сайт — добавьте домен в `list-general-user.txt` и
перезапустите стратегию.

## Дополнительно

```bash
sudo ./service.sh check    # проверка окружения
sudo ./service.sh status   # статус сервиса, демона и правил
sudo bash setup-doh.sh     # шифрованный DNS (dnscrypt), лечит подмену DNS
sudo bash diagnose.sh      # где рвётся доступ: DNS / TCP / TLS
```

Десинхронизация помогает против блокировок по содержимому пакетов (SNI/QUIC).
Если режут по IP-диапазонам — выручит только прокси или VPN.
