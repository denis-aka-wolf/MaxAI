# MaxAI

Самостоятельный MAX-клиент и AI-ассистент на Dart + Flutter для Windows.

## Статус разработки

Проект находится на этапе исследования и создания протокольного ядра. Совместимость неофициального внутреннего API MAX с актуальным сервером не подтверждена.

## Структура

- `docs/MAX_Protocol_Specification.md` — исследование протокола.
- `packages/maxai_protocol/` — самостоятельный Dart-пакет frame, MessagePack, транспортного соединения и начального MAX handshake (`SESSION_INIT`).

На текущем этапе реализованы протокольное соединение и `SessionManager` для mobile/web `SESSION_INIT`. SMS/QR авторизация, LOGIN, heartbeat и проверка совместимости с действующим сервером MAX ещё не реализованы.

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

При изменении файлов пакета `packages/maxai_protocol/` GitHub Actions автоматически запускает:

1. `dart pub get` — получение зависимостей.
2. `dart analyze` — статический анализ кода.
3. `dart test` — запуск тестов.

## Принципы

- Только Dart + Flutter в приложении.
- Секреты не хранятся в исходниках, SQLite или логах.
- Групповые чаты полностью исключаются из AI-обработки.
- Автоотправка выключена по умолчанию и требует явного разрешения для каждого контакта.
- Неизвестные детали протокола помечаются как требующие проверки.
