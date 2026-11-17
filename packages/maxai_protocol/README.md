# maxai_protocol

Первый самостоятельный Dart-модуль проекта MaxAI.

## Состав
- TcpFrameCodec: 10-байтовый header PyMax >BBHHI.
- MessagePackPayloadCodec: сериализация payload.
- SequenceManager: 16-битный sequence, первый номер 0.
- PendingRequests: ожидание ответов по sequence.

## Проверка
Из каталога пакета:
```bash
dart pub get
dart analyze
dart test
```

## Ограничения
- Это не готовый MAX-клиент и не реализация авторизации.
- TCP stream reassembly ещё не реализован. decode принимает ровно один полный frame.
- Один WebSocket message пока предполагается содержащим ровно один frame. Это требует проверки.
- Compression flags переносятся в frame, декомпрессия не реализована.
- Сетевые запросы к MAX не выполняются.

Формат frame основан на исследовании исходников PyMax. Совместимость с текущим сервером MAX ещё не подтверждена.
