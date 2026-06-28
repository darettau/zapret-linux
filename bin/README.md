# bin/

Сюда `install.sh` кладёт собранный бинарь и шаблоны (в git не хранятся):

- `nfqws` — собранный обработчик NFQUEUE, собирается из `../zapret-src/`.
- `quic_initial_www_google_com.bin` — шаблон поддельного QUIC Initial.
- `tls_clienthello_www_google_com.bin` — шаблон поддельного TLS ClientHello.

Если шаблонов нет в исходниках, создаются пустые заглушки — тогда маскировка слабее.
