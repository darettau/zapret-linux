# zapret-linux

Обход DPI-блокировок на Linux — Telegram, YouTube, Discord и прочее.
`iptables` заворачивает трафик в NFQUEUE, `nfqws` ломает распознавание.
Собрано под Arch, работает на Debian/Ubuntu и Fedora.

Форк [bol-van/zapret](https://github.com/bol-van/zapret): оттуда `nfqws` и сетевой код.
Здесь — обвязка сверху: установка, стратегии, systemd, диагностика.

## Установка

```bash
git clone https://github.com/darettau/zapret-linux && cd zapret-linux && sudo ./install.sh
```

Соберёт `nfqws` и в конце сам подберёт десинхронизацию под провайдера —
VPN на это время выключить. Переподобрать потом: `sudo ./youtube-tune.sh`.

## Запуск

```bash
sudo ./start.sh             # меню
sudo ./start.sh 8           # по номеру
sudo ./start.sh youtube     # по имени
sudo ./stop.sh              # выключить и снять правила
```

## Стратегии

| # | | |
|---|---|---|
| 1 | `general` | базовая, `split2` |
| 2 | `general_alt` | `multidisorder` |
| 3 | `general_alt2` | `multisplit` + `seqovl` |
| 4 | `general_fake` | поддельный TLS/QUIC |
| 5 | `simple_fake` | ко всему трафику, без списков |
| 6 | `telegram` | локальный MTProto-прокси |
| 7 | `blockcheck` | подобранное под провайдера |
| 8 | `youtube` | сайты + YouTube/Google, по умолчанию |

DPI у всех разный. Не пошла одна — пробуй следующую.

## Автозапуск

```bash
sudo ./service.sh install              # youtube по умолчанию
sudo ./service.sh install general_fake
sudo ./service.sh remove
systemctl status zapret
```

## Списки

Всё в `lists/`. Свои домены — в `list-general-user.txt`, он не перезаписывается:
добавил, перезапустил стратегию, готово. Рядом `list-general.txt` (основной),
`list-exclude*.txt`, `list-google.txt` и `ipset-*.txt` — то же по IP.

## Если не работает

```bash
sudo bash diagnose.sh      # где рвётся: DNS, TCP или TLS
sudo bash setup-doh.sh     # шифрованный DNS, лечит подмену
sudo ./service.sh status   # что с сервисом, демоном и правилами
```

Десинхронизация работает против блокировок по содержимому — SNI, QUIC.
Режут по IP — не поможет, нужен прокси или VPN.
