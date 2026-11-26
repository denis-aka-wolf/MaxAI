[RU](README.md) | [ENG](ENG_README.md)

# MaxAI

Самостоятельный MAX-клиент и AI-ассистент на Dart + Flutter для Windows.

## Статус разработки

Проект находится на этапе исследования и создания протокольного ядра. Совместимость неофициального внутреннего API MAX с актуальным сервером не подтверждена.

## Структура

- [Документация проекта](docs/README.md) — полный каталог технической документации.
- [Спецификация протокола MAX](docs/MAX_Protocol_Specification.md) — исследование протокола и его структур.
- [Дорожная карта](docs/ROADMAP.md) — этапы и план разработки.
- [Read-only API Probe](docs/READ_ONLY_API_PROBE.md) — описание проверок API в режиме чтения.
- [Настройка TLS-сертификатов Windows](docs/TLS_CERTIFICATE_SETUP.md) — установка и проверка сертификатов для подключения.
- `packages/maxai_protocol/` — самостоятельный Dart-пакет frame, MessagePack, транспортного соединения, handshake, авторизации и начального входа в аккаунт.
- `apps/auth_probe/` — отдельное Flutter Windows-приложение для проверки WebSocket + QR авторизации на реальном сервере MAX.

На текущем этапе реализованы протокольное соединение, mobile/web `SESSION_INIT`, `HeartbeatManager` для PING (opcode 1), базовая SMS/2FA/QR-авторизация и подтверждение регистрации. Добавлены mobile/web `LOGIN` (opcode 19), условный `LOGIN2` (opcode 8), модели ответов и управление sync markers по схемам PyMax 2.5.0. Совместимость с действующим сервером MAX пока не подтверждена.

## Документация

Все документы доступны из [каталога документации](docs/README.md). Основная версия ведётся на русском языке, английские переводы имеют префикс `ENG_`.

## Проверка авторизации MAX

Для запуска диагностического приложения на Windows:

```powershell
cd apps/auth_probe
flutter create . --platforms=windows
flutter pub get
flutter analyze
flutter run -d windows
```

Приложение проверяет WebSocket, SESSION_INIT, QR, LOGIN и условный LOGIN2. TCP + TLS и SMS будут добавлены позже.

## Проверка протокольного пакета

Локальная проверка выполняется командами:

```bash
cd packages/maxai_protocol
dart pub get
dart analyze
dart test
```

## Непрерывная интеграция (CI)

[Dart Protocol CI](https://github.com/denis-aka-wolf/MaxAI/blob/main/.github/workflows/dart_protocol.yml)

При изменении файлов пакета `packages/maxai_protocol/` GitHub Actions автоматически запускает получение зависимостей, статический анализ и тесты.

## Принципы

- Только Dart + Flutter в приложении.
- Секреты не хранятся в исходниках, SQLite или логах.
- Групповые чаты полностью исключаются из AI-обработки.
- Автоотправка выключена по умолчанию и требует явного разрешения для каждого контакта.
- Неизвестные детали протокола помечаются как требующие проверки.
