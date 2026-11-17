# maxai_protocol

Самостоятельное Dart-протокольное ядро для проекта MaxAI.

## Реализовано

- 10-байтовый TCP-like frame header по формату PyMax `>BBHHI`.
- MessagePack-кодирование и декодирование payload.
- Сборка frame из произвольно фрагментированных byte chunks.
- 16-битный sequence manager с циклическим переполнением.
- Реестр ожидающих запросов с timeout и отменой.
- WebSocket transport и абстрактный контракт транспорта.
- `ProtocolConnection`: отправка REQUEST, сопоставление RESPONSE/ERROR по sequence, обработка EVENT, закрытие и обработка потери соединения.
- `SessionManager`: mobile/web payload для `SESSION_INIT` (opcode 6), проверка ответа handshake и состояния MAX-сессии.
- Модели `MaxUserAgent`, `HandshakeResponse`, `DeviceType` и `SessionState`.
- `HeartbeatManager`: периодический PING (opcode 1), первый запрос сразу после запуска, без параллельных ping.
- Автоматический пропуск занятых sequence ID при выдаче нового запроса.

## SESSION_INIT

Реализация сверена с `SessionService` и payload-моделями исследованной версии PyMax:

- Mobile: `mt_instanceid`, `userAgent`, `clientSessionId` (1..70), `deviceId`.
- Web: `userAgent` с ограниченным набором полей и `deviceId`.
- Opcode: `6`.
- Ответ разбирает `callsSeed` и `app-update-type`; остальные поля сохраняются в `raw`.

`SessionManager` не выполняет SMS/QR авторизацию и не отправляет LOGIN. `HeartbeatManager` реализует отдельный PING-цикл, который можно запускать после успешного handshake.

## Значения command

Значения взяты из `Command` в исследованной версии PyMax:

| Command | Значение |
|---|---:|
| REQUEST | 0 |
| RESPONSE | 1 |
| EVENT | 2 |
| ERROR | 3 |

Ответы RESPONSE и ERROR сопоставляются с ожидающим запросом по sequence. ERROR пока возвращается вызывающему слою как обычный `DecodedProtocolFrame`: интерпретация payload ошибки относится к API-слою.

## Проверка

Из каталога пакета:

```bash
dart pub get
dart analyze
dart test
```

GitHub Actions запускает эти проверки при изменениях в `packages/maxai_protocol/**`.

## Ограничения и неподтверждённые детали

- Совместимость с актуальным сервером MAX не подтверждена.
- Формат и значения command сверены с исходниками PyMax, но сами исходники PyMax не являются официальной спецификацией MAX.
- Транспорт пока не содержит reconnect и авторизацию. Heartbeat реализован отдельным менеджером, но его поведение с актуальным сервером MAX не проверено.
- Предположение о соответствии одного WebSocket message одному бинарному frame требует проверки на реальном сервере. Stream decoder при этом умеет собирать frame из нескольких chunks и разбирать несколько frame подряд.
- Compression flags передаются в frame, но декомпрессия payload пока не реализована.
- Ошибки ERROR не преобразуются в специализированные исключения.
- Повторная отправка запросов после timeout намеренно не выполняется, чтобы не создавать дубли операций.

Реализация предназначена для дальнейшего тестирования на отдельном аккаунте. Не использовать основной аккаунт до проверки протокола и рисков неофициального API.
