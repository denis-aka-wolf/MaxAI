# Рабочий процесс разработки и запуск через VS Code

[RU](DEVELOPMENT_WORKFLOW.md) | [ENG](ENG_DEVELOPMENT_WORKFLOW.md)

Документ описывает автоматизированные проверки и запуск тестового приложения MAX Auth Probe из Visual Studio Code.

## Требования

- Visual Studio Code.
- Расширение **Dart** (оно также обеспечивает поддержку Flutter).
- Установленные и доступные из PATH команды `flutter` и `dart`.
- Flutter SDK с поддержкой Windows Desktop.
- Открытый в VS Code корень репозитория MaxAI, а не отдельная папка приложения или пакета.

## Конфигурационные файлы

В корне репозитория находятся:

- `.vscode/launch.json` — конфигурации запуска и отладки.
- `.vscode/tasks.json` — задачи проверок проектов.

Обе конфигурации используют пути относительно `${workspaceFolder}`, поэтому рассчитаны на открытие корня репозитория в VS Code.

## Запуск Auth Probe с предварительными проверками

В VS Code выберите конфигурацию **Auth Probe: Validate and Launch (Windows)** в панели Run and Debug и нажмите **F5**.

Перед запуском приложения VS Code последовательно выполнит:

1. `flutter analyze` в `apps/auth_probe`.
2. `flutter test` в `apps/auth_probe`.

Если любая из проверок завершится с ошибкой, цепочка предварительной задачи завершится неуспешно и приложение не будет запущено. Если обе проверки пройдут, VS Code запустит Flutter-приложение на устройстве `windows` под отладчиком.

Эквивалентная команда запуска из терминала:

```powershell
cd apps/auth_probe
flutter run -d windows
```

## Проверка пакета maxai_protocol

Проверка пакета выполняется отдельно от запуска Auth Probe.

1. Откройте палитру команд: **Ctrl + Shift + P**.
2. Выберите **Tasks: Run Task**.
3. Запустите задачу **MaxAI Protocol: Analyze + Test**.

Она последовательно выполняет:

```powershell
cd packages/maxai_protocol
dart analyze
dart test
```

Задачи можно запускать и по отдельности:

- **MaxAI Protocol: Dart Analyze**
- **MaxAI Protocol: Dart Test**

## Доступные задачи VS Code

| Название задачи | Рабочий каталог | Действие |
|---|---|---|
| Auth Probe: Flutter Analyze | `apps/auth_probe` | Статический анализ Flutter-приложения |
| Auth Probe: Flutter Test | `apps/auth_probe` | Тесты Flutter-приложения |
| Auth Probe: Analyze + Test | `apps/auth_probe` | Последовательный запуск двух проверок |
| MaxAI Protocol: Dart Analyze | `packages/maxai_protocol` | Статический анализ Dart-пакета |
| MaxAI Protocol: Dart Test | `packages/maxai_protocol` | Тесты Dart-пакета |
| MaxAI Protocol: Analyze + Test | `packages/maxai_protocol` | Последовательный запуск двух проверок |

## Важные замечания

- Проверки запускаются последовательно, а не параллельно.
- Запуск Auth Probe через F5 всегда предваряется проверками Flutter.
- Проверки `maxai_protocol` намеренно не включены в запуск Auth Probe: это отдельный пакет и отдельный цикл валидации.
- Если VS Code не находит `flutter` или `dart`, проверьте PATH и настройки Flutter/Dart SDK, затем перезапустите VS Code.
- Если устройство `windows` недоступно, проверьте установку Windows Desktop toolchain командой `flutter doctor`.

## Файлы конфигурации

- [launch.json](../.vscode/launch.json)
- [tasks.json](../.vscode/tasks.json)
- [README приложения Auth Probe](../apps/auth_probe/README.md)
