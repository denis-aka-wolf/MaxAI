[RU](README.md) | [ENG](ENG_README.md)

# MaxAI

An independent MAX client and AI assistant built with Dart + Flutter for Windows.

## Development status

The project is currently in the protocol research and core implementation phase. Compatibility of the unofficial internal MAX API with the current MAX server has not yet been confirmed.

## Project structure

- [Project documentation](docs/ENG_README.md) - complete index of technical documentation.
- [MAX Protocol Specification](docs/MAX_Protocol_Specification.md) - protocol research and structures (Russian original; English translation in progress).
- [Roadmap](docs/ENG_ROADMAP.md) - development phases and planned work.
- [Read-only API Probe](docs/ENG_READ_ONLY_API_PROBE.md) - description of read-only API checks.
- [Windows TLS Certificate Setup](docs/ENG_TLS_CERTIFICATE_SETUP.md) - certificate installation and connection verification.
- `packages/maxai_protocol/` - standalone Dart package for frames, MessagePack, transport connections, handshake, authentication and initial account login.
- `apps/auth_probe/` - separate Flutter Windows application for testing WebSocket and QR authentication against the live MAX server.

At this stage, the implementation includes the protocol connection, mobile/web `SESSION_INIT`, `HeartbeatManager` for PING (opcode 1), basic SMS/2FA/QR authentication and registration confirmation. Mobile/web `LOGIN` (opcode 19), conditional `LOGIN2` (opcode 8), response models and sync-marker management based on PyMax 2.5.0 schemas have also been added. Compatibility with the current MAX server has not yet been confirmed.

## Documentation

All documents are available from the [documentation index](docs/ENG_README.md). Russian is the primary documentation language; English translations use the `ENG_` prefix.

## Testing MAX authentication

To run the diagnostic application on Windows:

```powershell
cd apps/auth_probe
flutter create . --platforms=windows
flutter pub get
flutter analyze
flutter run -d windows
```

The application tests WebSocket, SESSION_INIT, QR, LOGIN and conditional LOGIN2. TCP + TLS and SMS support will be added later.

## Testing the protocol package

Run the following commands for local verification:

```bash
cd packages/maxai_protocol
dart pub get
dart analyze
dart test
```

## Continuous integration (CI)

[Dart Protocol CI](https://github.com/denis-aka-wolf/MaxAI/blob/main/.github/workflows/dart_protocol.yml)

Whenever files in `packages/maxai_protocol/` change, GitHub Actions automatically retrieves dependencies and runs static analysis and tests.

## Principles

- Dart + Flutter only in the application.
- Secrets are never stored in source files, SQLite or logs.
- Group chats are completely excluded from AI processing.
- Automatic sending is disabled by default and requires explicit permission for each contact.
- Unknown protocol details are marked as requiring verification.
