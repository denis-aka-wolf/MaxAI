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
- Модели `MaxUserAgent`, `HandshakeResponse`, `DeviceType`, `SessionState` и `SyncState`.
- `HeartbeatManager`: периодический PING (opcode 1), первый запрос сразу после запуска, без параллельных ping.
- Автоматический пропуск занятых sequence ID при выдаче нового запроса.

## Авторизация

Добавлен базовый `AuthManager` поверх успешного `SESSION_INIT`:

- SMS: `AUTH_REQUEST` (17) и `AUTH` (18).
- Проверка пароля 2FA: `AUTH_LOGIN_CHECK_PASSWORD` (115).
- QR: `GET_QR` (288), `GET_QR_STATUS` (289), `LOGIN_BY_QR` (291).
- Регистрация: `AUTH_CONFIRM` (23).
- Проверка command/opcode ответа и timeout.
- Результаты различаются: токен входа, пароль 2FA или регистрация.
- Секретные значения не включаются в диагностические сообщения.

Для mobile SMS-запроса и mobile LOGIN требуется `FingerprintProvider`. Реализован `Sha256FingerprintProvider`, повторяющий формулу `FingerprintGenerator` PyMax. Он требует хеши APK одной конкретной версии MAX; произвольные или смешанные значения не подходят.

## LOGIN и LOGIN2

Добавлен `LoginManager`, сверенный с исходниками PyMax **2.5.0** (`dev/2.5.0`):

- Mobile LOGIN: opcode `19`, payload `SyncPayload`, включая userAgent, token, fingerprint, sync markers, `exp` и `configHash`.
- Web LOGIN: opcode `19`, payload `WebSyncPayload`. Поле `presenceSync` намеренно не отправляется: фактический `from_sync_state()` PyMax 2.5.0 его не передаёт.
- LOGIN2: opcode `8`, отправляется только если хотя бы один из флагов `configEnabled`, `contactEnabled`, `profileEnabled` равен true.
- LOGIN2 payload содержит `needProfile`, `contactsSync` и `configHash`. При выключенном `contactEnabled` значение `contactsSync` равно `-1`.
- `LoginResponse` и `Login2Response` сохраняют исходные поля payload; чаты, профиль, сообщения и контакты пока представлены исходными структурами MessagePack.
- Sync markers обновляются по `time` из LOGIN; LOGIN2 обновляет только `configHash`.
- Обновлённый токен используется только если сервер вернул непустую строку. Иначе сохраняется исходный токен.
- `LoginBootstrapResult` возвращает итоговый токен, sync state, профиль и контакты с учётом флагов.

`AuthManager` возвращает токен вызывающему слою и не сохраняет его. Аналогично `LoginManager` не сохраняет токен или sync state: их нужно записать в защищённое хранилище сессии после успешного завершения bootstrap.

## SESSION_INIT

Реализация сверена с `SessionService` и payload-моделями исследованной версии PyMax:

- Mobile: `mt_instanceid`, `userAgent`, `clientSessionId` (1..70), `deviceId`.
- Web: `userAgent` с ограниченным набором полей и `deviceId`.
- Opcode: `6`.
- Ответ разбирает `callsSeed` и `app-update-type`; остальные поля сохраняются в `raw`.

## Значения command

Значения взяты из `Command` в исследованной версии PyMax:

| Command | Значение |
|---|---:|
| REQUEST | 0 |
| RESPONSE | 1 |
| EVENT | 2 |
| ERROR | 3 |

Ответы RESPONSE и ERROR сопоставляются с ожидающим запросом по sequence. ERROR возвращается вызывающему слою как frame, чтобы API-слой мог интерпретировать payload ошибки.

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
- Формат и значения command сверены с исходниками PyMax 2.5.0, но исходники PyMax не являются официальной спецификацией MAX.
- Доменные модели чатов, профиля, сообщений и пользователей ещё не реализованы: LOGIN ответы сохраняются без потери исходных полей.
- Транспорт пока не содержит reconnect. Heartbeat, авторизация и LOGIN не проверены на реальном сервере MAX.
- Предположение о соответствии одного WebSocket message одному бинарному frame требует проверки на реальном сервере.
- Compression flags передаются в frame, но декомпрессия payload пока не реализована.
- Повторная отправка запросов после timeout намеренно не выполняется, чтобы не создавать дубли операций.

Реализация предназначена для дальнейшего тестирования на отдельном аккаунте. Не использовать основной аккаунт до проверки протокола и рисков неофициального API.
