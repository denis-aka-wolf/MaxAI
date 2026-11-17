# MAX Protocol Specification

> **Статус:** исследовательская спецификация, версия 0.1  
> **Дата:** 2026-11-17  
> **Назначение:** проектирование самостоятельного MAX-клиента на Dart для приложения MaxAI.  
> **Источники:** форки `denis-aka-wolf/PyMax` и `denis-aka-wolf/max-user-api`.

## 1. Статус и границы достоверности

MAX не предоставляет в рассмотренных репозиториях публичную стабильную спецификацию пользовательского протокола. Описанное ниже основано на чтении исходного кода двух неофициальных реализаций. Это не гарантия совместимости с текущим сервером MAX.

В документе используются пометки:

- **Подтверждено исходником** — непосредственно видно в указанном файле.
- **Наблюдение второй реализации** — присутствует в max-user-api, но не подтверждено PyMax.
- **Требует проверки** — нельзя считать стабильным контрактом до теста на отдельном аккаунте и сверки реального обмена.
- **Решение MaxAI** — предлагаемая архитектура реализации на Dart, а не утверждение о внутреннем устройстве сервера.

Репозиторий MaxAI не должен копировать Python-код. Исходники используются как исследовательский материал для независимой реализации на Dart. Необходимо учитывать условия использования MAX, риски блокировки аккаунта и изменения внутреннего API. Не проводить нагрузочное тестирование и не использовать основной пользовательский аккаунт на ранних этапах.

## 2. Исследованные репозитории

### 2.1 PyMax

Исследуемый форк: https://github.com/denis-aka-wolf/PyMax

PyMax содержит две отдельные клиентские реализации:

- `Client`: TCP-транспорт и штатный SMS-flow.
- `WebClient`: WebSocket-транспорт и QR-flow.

Ключевые исходники:

| Область | Файл |
|---|---|
| SMS авторизация | `src/pymax/auth/sms.py` |
| QR авторизация | `src/pymax/auth/qr.py` |
| API авторизации | `src/pymax/api/auth/service.py` |
| Payload авторизации | `src/pymax/api/auth/payloads.py` |
| TCP транспорт | `src/pymax/transport/tcp.py` |
| WebSocket транспорт | `src/pymax/transport/websocket.py` |
| TCP framing | `src/pymax/protocol/tcp/framing.py` |
| TCP protocol | `src/pymax/protocol/tcp/protocol.py` |
| MessagePack codec | `src/pymax/protocol/tcp/payload.py` |
| WebSocket protocol | `src/pymax/protocol/ws/protocol.py` |
| Opcode / command | `src/pymax/protocol/enums.py` |
| Handshake payload | `src/pymax/api/session/payloads.py` |
| Handshake service | `src/pymax/api/session/service.py` |
| Состояние синхронизации | `src/pymax/types/domain/sync.py` |
| Хранилище сессии | `src/pymax/session/store.py` |
| Клиент TCP | `src/pymax/client.py` |
| Клиент WebSocket | `src/pymax/client_web.py` |
| Базовый клиент / lifecycle | `src/pymax/base.py` |
| История и отправка сообщений | `src/pymax/api/messages/service.py` |
| Payload сообщений | `src/pymax/api/messages/payloads.py` |
| Описание lifecycle | `docs/client.rst` |

### 2.2 max-user-api

Исследуемый форк: https://github.com/denis-aka-wolf/max-user-api

Ключевые исходники:

- `max_user_api/connection.py` — WebSocket-соединение, receiver, ping, reconnect.
- `max_user_api/client.py` — публичный API клиента и обработчики событий.
- `max_user_api/request/builder.py` — сборка request frame.
- `max_user_api/request/payloads.py` — payload init/auth/history.
- `max_user_api/enums.py` — opcode и типы сообщений.
- `max_user_api/models.py` — модели профиля, чатов, сообщений и вложений.
- `max_user_api/parsers/message.py` — разбор текста и вложений.
- `readme/ru/README.md` — ограничения и способ настройки.

В README max-user-api прямо обозначен как ранний экспериментальный проект с неполной документацией. Он ожидает уже имеющиеся `token` и `device_id`, а README предлагает получать их через Local Storage или анализ сетевого трафика. MaxAI не должен строить штатную авторизацию на извлечении токена из браузера: предпочтительны отдельные документированные в PyMax SMS- и QR-flow, с независимым хранением сессий.

## 3. Архитектурное решение MaxAI

Не объединять SMS и QR в один транспорт с переключателем. Это разные сценарии:

1. SMS-вариант в PyMax построен на TCP и mobile-подобном handshake.
2. QR-вариант построен на WebSocket и web-handshake.

Предлагаемая структура Dart:

```text
MaxClient
├── Auth
│   ├── SmsAuthAdapter
│   └── QrAuthAdapter
├── Transport
│   ├── TcpTransport
│   └── WebSocketTransport
├── Protocol
│   ├── TcpFrameCodec
│   ├── MessagePackCodec
│   └── WebSocketFrameCodec
├── Session
│   ├── SessionManager
│   └── SessionRepository
├── Api
│   ├── AuthApi
│   ├── SessionApi
│   ├── ContactsApi
│   ├── ChatsApi
│   ├── MessagesApi
│   └── HistoryApi
├── Sync
│   ├── SyncManager
│   └── SyncState
└── Events
    ├── EventDispatcher
    └── EventModels
```

Общие доменные интерфейсы могут быть едиными, но transport, handshake и auth-flow должны оставаться раздельными. На первом этапе следует выбрать один поток для полноценной реализации и стабилизации, не смешивая состояния двух клиентов.

## 4. Общая модель frame

### 4.1 Поля frame

В PyMax базовые модели протокола используют следующие поля:

| Поле | Значение |
|---|---|
| `ver` | версия протокола frame |
| `cmd` | тип команды |
| `seq` | номер запроса / корреляционный номер |
| `opcode` | операция |
| `payload` | данные операции |

Значения `Command` в `src/pymax/protocol/enums.py`:

| Имя | Число |
|---|---:|
| REQUEST | 0 |
| RESPONSE | 1 |
| EVENT | 2 |
| ERROR | 3 |

В PyMax `TcpProtocol.version = 10`, а `WsProtocol.version = 11`. max-user-api также собирает WebSocket frame с `ver = 11`. Версии нельзя считать взаимозаменяемыми без проверки сервером.

### 4.2 TCP frame

**Подтверждено исходником:** `src/pymax/protocol/tcp/framing.py`.

Заголовок кодируется big-endian структурой `>BBHHI`, то есть 10 байт:

| Смещение | Размер | Поле |
|---:|---:|---|
| 0 | 1 | ver |
| 1 | 1 | cmd |
| 2 | 2 | seq |
| 4 | 2 | opcode |
| 6 | 4 | packed length |

Поле packed length разделяется на:

- старший байт: `flags`;
- младшие 24 бита: длина payload.

Формула PyMax:

```text
packed_len = ((flags & 0xFF) << 24) | (payload_length & 0x00FFFFFF)
```

После заголовка идёт payload указанной длины. Фреймер умеет определить неполный пакет, если буфер содержит меньше 10 байт или меньше полного размера заголовка с payload.

Важное замечание для Dart: TCP — поток байтов. Нельзя предполагать, что один вызов socket.read() вернёт ровно один frame. Нужен буферизованный декодер: сначала накопить 10 байт заголовка, вычислить длину, затем дочитать ровно payload; после извлечения frame продолжить обработку остатка буфера. Ограничить максимальный допустимый размер payload, чтобы избежать неконтролируемого выделения памяти.

### 4.3 TCP payload

**Подтверждено исходником:** `src/pymax/protocol/tcp/payload.py`.

PyMax сериализует payload через MessagePack (`msgpack.packb`, `use_bin_type=True`). Enum значения перед сериализацией преобразуются в их числовые/строковые значения. Пустой payload кодируется пустой последовательностью байтов.

Декодер поддерживает MessagePack extension code 1 как обёрнутые значения. В проекте также присутствуют LZ4 и Zstandard декодеры. При этом текущий `TcpProtocol.encode()` в изученном исходнике не включает компрессию: код компрессии закомментирован. Флаги компрессии и точные условия применения нужно выяснять отдельно, не включать компрессию в Dart «на всякий случай».

Реализация Dart должна иметь отдельный MessagePack codec и тестовые бинарные fixtures. Нельзя подменять MessagePack JSON-сериализацией для TCP.

### 4.4 WebSocket frame

В `src/pymax/protocol/ws/protocol.py` WebSocket frame сериализуется в JSON через модель frame. max-user-api строит объект:

```json
{
  "ver": 11,
  "cmd": 0,
  "seq": 0,
  "opcode": 6,
  "payload": {}
}
```

Это иллюстративная форма envelope, а не полный реальный payload. WebSocket payload может приходить как bytes или string. Требуется проверять тип сообщения и корректно декодировать JSON.

**Особенность PyMax:** `WebClient._build_connection()` создаёт `WSReader` и `WebSocketTransport`, но передаёт в ConnectionManager `TcpProtocol()`, а не `WsProtocol()`. Это важная деталь конкретной реализации: нельзя автоматически считать, что web transport всегда использует JSON codec из `WsProtocol`. Следует проверить reader, connection manager и реальные сообщения WebClient до реализации совместимого Dart-потока.

## 5. Transport и соединение

### 5.1 TCP

В `src/pymax/transport/tcp.py` PyMax:

- открывает TCP-соединение к настроенным host/port;
- по умолчанию использует TLS;
- загружает корневой сертификат из ресурсов пакета;
- поддерживает proxy;
- отправляет байты через write/drain;
- читает фиксированное число байтов через readexactly;
- закрывает соединение с timeout и abort при зависшем закрытии.

Для Dart необходимы `Socket`/`SecureSocket`, корректная проверка TLS-сертификата и отдельный потоковый frame decoder. Не отключать проверку сертификата для «починки» соединения.

### 5.2 WebSocket

В `src/pymax/transport/websocket.py` PyMax:

- открывает WebSocket по настроенному URL;
- задаёт Origin `https://web.max.ru`;
- допускает proxy;
- ограничивает размер сообщения 10 MiB;
- отправляет и получает сообщения WebSocket;
- отслеживает состояние закрытия.

max-user-api также использует WebSocket с Origin `https://web.max.ru`, User-Agent и web-заголовками. Его реализация использует собственную логику receiver/ping/reconnect. URL, заголовки и параметры handshake являются изменяемыми параметрами, а не вечными константами.

## 6. SMS авторизация (TCP Client)

**Подтверждено исходником:** `src/pymax/auth/sms.py` и `src/pymax/api/auth/service.py`.

Установленная последовательность на уровне PyMax:

1. Создать TCP transport.
2. Выполнить session handshake (см. раздел 8).
3. Вызвать `AUTH_REQUEST` с номером телефона.
4. Получить временный auth token / challenge-данные.
5. Запросить у пользователя SMS-код через UI.
6. Вызвать проверку кода (`send_code`, opcode `AUTH`).
7. Обработать один из результатов:
   - `login_token` — авторизация завершена;
   - `password_challenge` — требуется пароль 2FA;
   - `register_token` — требуется отдельный flow регистрации, если он поддержан конфигурацией;
   - отсутствие ожидаемых полей — ошибка авторизации.
8. При 2FA запросить пароль и вызвать проверку пароля с `track_id`.
9. Полученный login token передать SessionManager для безопасного сохранения.

В `RequestCodePayload` видны поля `phone`, `type` (по умолчанию START_AUTH) и `mode`. Для mobile-варианта PyMax генерирует fingerprint на основе `device_id`, `calls_seed` из handshake и архитектуры устройства. Это означает, что mobile-подобная авторизация не сводится к отправке только номера телефона.

Точные request/response payload и их обязательность необходимо переносить по конкретным моделям `src/pymax/api/auth/payloads.py`, `src/pymax/types/domain/auth.py` и тестам `tests/api/test_auth_service.py`, а не реконструировать по названиям методов.

## 7. QR авторизация (WebClient)

**Подтверждено исходником:** `src/pymax/auth/qr.py`.

Последовательность PyMax:

1. Открыть WebSocket transport.
2. Выполнить web handshake.
3. Запросить QR: `request_qr()`.
4. Получить QR-данные, включая `track_id`, `qr_link`, `polling_interval`, `expires_at`.
5. Показать QR в Flutter UI.
6. Периодически вызывать `check_qr(track_id)` с интервалом, полученным от сервера.
7. Завершить polling по истечении `expires_at`.
8. При доступности входа вызвать `confirm_qr(track_id)`.
9. Если ответ содержит challenge 2FA, запросить пароль и выполнить проверку.
10. Сохранить итоговый login token.

Не зашивать интервал polling и TTL QR в приложение: использовать значения ответа сервера. Добавить отмену пользователем, обработку истечения QR, сетевых ошибок и повторный запрос QR.

QR-flow и SMS-flow должны иметь независимые состояния UI и независимые реализации AuthAdapter. Точный QR link следует отображать как QR-код, не отправляя его в логи и аналитику.

## 8. Handshake и login/sync

**Подтверждено исходником:** `src/pymax/api/session/service.py` и `src/pymax/api/session/payloads.py`.

Для mobile handshake PyMax вызывает `SESSION_INIT` с payload, включающим:

- `mt_instanceid`;
- `user_agent`;
- `client_session_id` (генерируется в модели);
- `device_id`.

Для web handshake payload содержит:

- `userAgent` в web-формате;
- `deviceId`.

Web user-agent сериализуется ограниченным набором aliases: `deviceType`, `locale`, `deviceLocale`, `osVersion`, `deviceName`, `headerUserAgent`, `appVersion`, `screen`, `timezone`.

После handshake auth/login использует token и sync-параметры. В PyMax присутствуют отдельные `SyncPayload` и `WebSyncPayload`. Mobile payload включает user-agent, token, chat cache fingerprint, chats count, sync markers, interactive, presence и config hash. Web payload включает token, chats count и маркеры чатов/контактов/presence/drafts.

В max-user-api request builder использует `ver=11`, `cmd=0`, возрастающий `seq`, `opcode` и `payload`. Его init payload содержит web user-agent и deviceId, а authenticate payload — interactive, token, chatsCount и маркеры sync.

**Требует проверки:** точная последовательность opcode между SESSION_INIT, QR/SMS auth и login/sync, а также отличия TCP и WebSocket на уровне frame codec. Проверить по полному lifecycle в `src/pymax/app.py`, `src/pymax/base.py`, API services и protocol tests. Не считать, что успешный handshake автоматически означает авторизацию.

## 9. Сессия и device identity

PyMax `SessionStore` хранит в SQLite сведения сессии. По исходнику `src/pymax/session/store.py` в набор колонок входят:

- token;
- device_id;
- phone;
- mt_instance_id;
- chats_sync;
- contacts_sync;
- drafts_sync;
- presence_sync;
- config_hash;
- user_agent.

Для MaxAI это ориентир по структуре данных, но не основание хранить секреты открытым текстом.

**Решение MaxAI:**

- token хранить в Windows Credential Manager;
- в SQLite хранить только ссылку/ключ credential entry и несекретные метаданные;
- device_id создавать один раз на профиль установки и сохранять устойчиво;
- не генерировать новый device_id при каждом запуске;
- не логировать token, QR link, SMS-код, пароль 2FA или полный auth payload;
- предусмотреть явный logout и удаление credential entry;
- различать серверный token, device_id и локальный внутренний ID профиля.

Сессионное хранилище должно быть версионируемым и поддерживать миграции. При повреждении sync state нельзя молча терять локальную историю сообщений.

## 10. Sync и reconnect

PyMax описывает SyncState следующими полями (`src/pymax/types/domain/sync.py`):

- `chats_sync`;
- `contacts_sync`;
- `drafts_sync`;
- `presence_sync`;
- `config_hash`.

Значения по умолчанию в модели PyMax — маркеры `-1` и DEFAULT_CONFIG_HASH. Эти значения не следует интерпретировать как универсальные серверные константы без проверки.

PyMax документирует long-running `start()` с reconnect и разовый `connect()`. max-user-api содержит receiver task, ping task, reconnect lock, backoff delay и callbacks до/после reconnect.

**Решение MaxAI:**

1. Хранить sync cursor отдельно для каждого аккаунта и категории данных.
2. Записывать входящие события и новый cursor транзакционно, насколько позволяет семантика ответа.
3. Дедуплицировать события по серверному ID/комбинации идентификаторов.
4. После reconnect сначала восстановить transport и выполнить handshake/login, затем продолжить синхронизацию с сохранённых маркеров.
5. Не считать кеш чатов или сообщения, пришедшие при login, полной историей.
6. Историю каждого личного чата загружать отдельными страницами до исчерпания доступных данных; хранить исходные сообщения, редактирования и удаления.
7. Применять exponential backoff с jitter и верхним пределом; ручная остановка должна прерывать reconnect.
8. Обеспечить single-flight reconnect и блокировку конкурирующих запросов, если протокол этого требует.

Точные значения маркеров, семантика cursor, границы страниц, подтверждение доставки событий и поведение при пропуске событий требуют экспериментальной проверки.

## 11. Список известных opcode

Ниже — фрагмент enum из `src/pymax/protocol/enums.py`. Значения относятся к версии исходника на момент исследования и могут измениться.

| Opcode | Значение | Назначение по имени |
|---|---:|---|
| PING | 1 | ping |
| RECONNECT | 3 | reconnect |
| SESSION_INIT | 6 | session handshake |
| LOGIN2 | 8 | login variant |
| PROFILE | 16 | profile |
| AUTH_REQUEST | 17 | запрос SMS-кода |
| AUTH | 18 | проверка auth-кода |
| LOGIN | 19 | login |
| LOGOUT | 20 | logout |
| SYNC | 21 | sync |
| CONFIG | 22 | config |
| AUTH_CONFIRM | 23 | auth confirm |
| CONTACT_INFO | 32 | contact info |
| CONTACT_LIST | 36 | contacts |
| CHAT_INFO | 48 | chat info |
| CHAT_HISTORY | 49 | chat history |
| CHATS_LIST | 53 | chats list |
| CHAT_MEMBERS | 59 | chat members |
| MSG_SEND | 64 | send message |
| MSG_TYPING | 65 | typing |
| MSG_DELETE | 66 | delete message |
| MSG_EDIT | 67 | edit message |
| MSG_GET | 71 | get messages |
| PHOTO_UPLOAD | 80 | photo upload |
| VIDEO_UPLOAD | 82 | video upload |
| FILE_UPLOAD | 87 | file upload |
| FILE_DOWNLOAD | 88 | file download |
| NOTIF_MESSAGE | 128 | incoming message notification |
| NOTIF_TYPING | 129 | typing notification |
| NOTIF_MARK | 130 | mark/read notification |
| NOTIF_CONTACT | 131 | contact notification |
| NOTIF_PRESENCE | 132 | presence notification |
| NOTIF_CHAT | 135 | chat notification |

Не реализовывать весь enum сразу. Сначала нужны только handshake/auth/login/sync, список личных чатов, история, новые сообщения, отправка текста и read state. Для каждого opcode создать типизированный request/response/event и тестовый fixture.

## 12. История и отправка сообщений

### 12.1 Получение истории

В `src/pymax/api/messages/payloads.py` PyMax описывает `ChatHistoryPayload` с полями:

- `chat_id`;
- `forward`;
- `backward` (по умолчанию 40);
- `backward_time`;
- `forward_time`;
- `get_chat`;
- `from`;
- `item_type`;
- `get_messages`;
- `interactive`.

В max-user-api `get_chat_messages_payload` использует `chatId`, `from`, `forward`, `backward`, `getMessages=true`.

Пагинация должна быть адаптером над реальной серверной семантикой. Значение backward=40 в модели — дефолт библиотеки, не доказанный максимум API. Нужно проверить, что означает from (ID, timestamp или другой маркер) и как сервер интерпретирует forward/backward.

### 12.2 Отправка сообщения

PyMax формирует сообщение в `MessageService._prepare_message()`:

- проверяет, что есть текст или вложения;
- преобразует markdown в текст и formatting elements;
- загружает вложения до отправки сообщения;
- создаёт `cid` на основе текущего времени в миллисекундах с монотонным увеличением;
- формирует объект сообщения с text, cid, elements, attaches и optional reply link.

`SendMessagePayload` содержит `chat_id`, вложенный `message` и `notify` (default false). Reply link имеет type `REPLY` и message_id.

Для MaxAI необходимо сохранять локальную запись исходящего сообщения до сетевой отправки со статусом pending, затем обновлять её по серверному подтверждению. При timeout нельзя автоматически повторять отправку без проверки результата: повтор может создать дубль. Использовать cid/client-generated correlation ID, если серверная семантика подтверждена тестами.

### 12.3 Форматирование и вложения

В моделях сообщения присутствуют `text`, `elements`, `attaches`, `link`, `cid`, временные поля, sender/chat IDs и статусы. В max-user-api парсер форматирования конвертирует смещения элементов из UTF-16 в индексы Python. Для Dart учитывать UTF-16 semantics при работе с форматирующими offsets, не полагаться на индексы Unicode code points.

Поддержка медиа требует отдельного исследования upload handshake, upload endpoint, токенов файлов и привязки результата к сообщению. Не включать медиа в первый вертикальный срез.

## 13. События и классификация чатов

PyMax enum содержит отдельные notification opcode для сообщений, typing, read marks, контактов, presence и чатов. max-user-api заявляет обработку новых, отредактированных и удалённых сообщений.

MaxAI должен разделять:
- транспортные события;
- protocol frames;
- доменные события;
- события UI;
- команды оркестратора.

**Критическое продуктовое правило MaxAI:** до передачи сообщения в AI Engine Policy Engine должен определить тип чата и статус контакта. Групповые чаты полностью исключаются из AI-процессинга: не передавать их сообщения в LLM, не извлекать факты и не генерировать предложения. Личные чаты также проходят allowlist/blocklist и global pause. Право автоотправки перепроверяется непосредственно перед отправкой.

Серверные поля, по которым надёжно различается личный и групповой чат, требуется подтвердить по моделям Chat и реальным ответам API. Не определять тип чата только по числу участников, если модель/тип чата содержит явный признак.

## 14. Безопасность

- Не записывать токены, коды подтверждения, пароли, QR links, cookies и полные секретные payload в логи.
- Хранить токены MAX и OpenRouter в Windows Credential Manager.
- TLS certificate validation обязательна.
- Ограничивать размеры входящих frame и JSON/MessagePack payload.
- Валидировать типы, обязательные поля и диапазоны числовых значений.
- Не исполнять команды из текста сообщений, вложений, профилей или метаданных.
- Содержимое переписки считать недоверенными данными; защищать PromptBuilder от prompt injection.
- Секреты и персональные данные не включать в crash reports.
- Предусмотреть экспорт/удаление локальной истории и резервное копирование с шифрованием.
- Отделять технические логи от содержимого переписки; по умолчанию не логировать тексты сообщений.

## 15. План верификации протокола

До реализации production-клиента создать набор проверок на тестовом аккаунте:

1. TCP TLS connect и разбор одного frame.
2. Разбор нескольких frame в одном TCP chunk.
3. Разбор frame, разделённого на несколько TCP reads.
4. MessagePack round-trip для простых map/list/string/int/bin/null.
5. Проверка response correlation по seq.
6. Handshake mobile и web отдельно.
7. SMS request-code → send-code → login token.
8. QR request → polling → confirm → login token.
9. 2FA challenge и ошибки неверного пароля.
10. Восстановление сессии после перезапуска.
11. Login/sync с пустым и сохранённым sync state.
12. Получение списка чатов и проверка типа каждого чата.
13. Постраничная загрузка истории до старейшего доступного сообщения.
14. События нового сообщения, edit, delete и read.
15. Отправка текста в личный тестовый чат и сопоставление cid с серверным message ID.
16. Разрыв соединения, reconnect, дедупликация и отсутствие потери событий.
17. Проверка, что group chat исключён из AI pipeline на уровне Policy Engine.

Для каждой проверки сохранять sanitized fixture: удалять токены, телефоны, имена, ID реальных пользователей и содержимое личной переписки. Бинарные frame fixtures должны быть синтетическими или обезличенными.

## 16. Этапы реализации Dart

### Этап A — протокольные примитивы

- TCP frame parser/encoder;
- MessagePack codec;
- WebSocket JSON envelope codec;
- command/opcode enums;
- seq correlation;
- unit tests и fixtures.

### Этап B — соединения и handshake

- TcpTransport;
- WebSocketTransport;
- mobile/web handshake payload;
- connect/close lifecycle;
- ping/pong и keepalive после уточнения фактической семантики.

### Этап C — авторизация

- SmsAuthAdapter с UI для кода и 2FA;
- QrAuthAdapter с QR widget, polling, expiry и 2FA;
- SessionManager;
- Windows Credential Manager integration.

### Этап D — read-only API

- профиль;
- список контактов;
- список чатов;
- chat metadata;
- история сообщений;
- SQLite persistence и sync cursor.

### Этап E — realtime и отправка

- event dispatcher;
- reconnect;
- deduplication;
- личные сообщения;
- read state;
- отправка текста только после подтверждения политикой MaxAI.

### Этап F — интеграция с AI

Только после стабилизации MAX Client подключать OpenRouter, Memory Engine, Policy Engine и Orchestrator. AI не должен зависеть от деталей транспорта и протокола.

## 17. Неизвестные вопросы и технический долг

Следующие пункты нельзя считать закрытыми по текущему исследованию:

1. Точные host/port TCP и WebSocket URL, их актуальность и региональные различия.
2. Точная схема TLS и сертификатная цепочка, используемая актуальным сервисом.
3. Полная последовательность handshake → auth → login → sync для обоих вариантов.
4. Различие frame codec для WebClient в PyMax: WebClient использует WSReader, но в ConnectionManager получает TcpProtocol; требуется анализ reader/manager и реального трафика.
5. Полная таблица request/response payload для нужных opcode.
6. Семантика seq, повторов, timeout, server push и error frame.
7. Точная семантика sync markers и гарантии replay после reconnect.
8. Семантика параметров истории `from`, `forward`, `backward`, `backward_time`, `forward_time`.
9. Поля, надёжно различающие direct, group и channel chats.
10. Upload/download протоколы и срок жизни media URLs.
11. Ограничения частоты запросов и официальные условия использования неофициальных клиентов.

Эти пункты закрываются отдельными тестами и дополнительным чтением исходников. Не добавлять предположительные значения в production-конфигурацию.

## 18. Ссылки на исходники

- PyMax fork: https://github.com/denis-aka-wolf/PyMax
- PyMax protocol enums: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/protocol/enums.py
- PyMax TCP framing: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/protocol/tcp/framing.py
- PyMax TCP payload codec: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/protocol/tcp/payload.py
- PyMax SMS auth: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/auth/sms.py
- PyMax QR auth: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/auth/qr.py
- PyMax auth service: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/api/auth/service.py
- PyMax session payloads: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/api/session/payloads.py
- PyMax session store: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/session/store.py
- PyMax message payloads: https://github.com/denis-aka-wolf/PyMax/blob/main/src/pymax/api/messages/payloads.py
- PyMax client lifecycle docs: https://github.com/denis-aka-wolf/PyMax/blob/main/docs/client.rst
- max-user-api: https://github.com/denis-aka-wolf/max-user-api
- max-user-api connection: https://github.com/denis-aka-wolf/max-user-api/blob/main/max_user_api/connection.py
- max-user-api request builder: https://github.com/denis-aka-wolf/max-user-api/blob/main/max_user_api/request/builder.py
- max-user-api request payloads: https://github.com/denis-aka-wolf/max-user-api/blob/main/max_user_api/request/payloads.py
- max-user-api Russian README: https://github.com/denis-aka-wolf/max-user-api/blob/main/readme/ru/README.md

---

**Итог:** источники подтверждают наличие двух различных путей подключения (TCP/SMS и WebSocket/QR), бинарного TCP frame с 10-байтовым заголовком и MessagePack payload, а также JSON-подобного WebSocket envelope во второй реализации. Это достаточная основа для декомпозиции Dart-клиента, но недостаточно для объявления протокола полностью специфицированным. Следующий инженерный шаг — верификация полного lifecycle и протокольных fixtures, затем реализация транспортного слоя и handshake.
