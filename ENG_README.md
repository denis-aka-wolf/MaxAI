[RU](README.md) | [ENG](ENG_README.md)

# MaxAI

An independent MAX client and AI assistant built with Dart + Flutter for Windows.

## Development status

The project is in the MAX protocol validation and protocol-core completion phase. MAX's internal API is not a public stable specification, so each operation must be validated separately.

## Project structure

- [Project documentation](docs/ENG_README.md) - technical documentation index.
- [MAX Protocol Specification](docs/MAX_Protocol_Specification.md) - protocol structure research (Russian source).
- [Roadmap](docs/ENG_ROADMAP.md) - development phases and planned work.
- [Read-only API Probe](docs/ENG_READ_ONLY_API_PROBE.md) - implemented read operations and their validation procedure.
- [Windows TLS Certificate Setup](docs/ENG_TLS_CERTIFICATE_SETUP.md) - certificate validation and installation for TCP/TLS.
- `packages/maxai_protocol/` - standalone Dart library for the MAX protocol.
- `apps/auth_probe/` - separate Windows laboratory application for authentication, TLS and API testing. It is a test tool, not the main MaxAI application.

## Implemented protocol-core capabilities

- TCP/TLS transport for mobile connections and WebSocket transport for web connections.
- Mobile/web `SESSION_INIT` and Heartbeat.
- QR authentication over WebSocket.
- SMS authentication over TCP/TLS and 2FA handling.
- `LOGIN` / `LOGIN2`, session restoration and local Logout.
- Secure local token and device ID storage through Windows DPAPI.
- Initial read-only API set: profile and contact snapshots from LOGIN/LOGIN2, CONTACT_INFO (32), CHATS_LIST (53), CHAT_INFO (48), CHAT_MEMBERS (59), CHAT_HISTORY (49) and MSG_GET (71).
- TLS certificate diagnostics and separate inspect/install actions in `auth_probe`.

The read-only API implementation and payload schemas are based on PyMax research. Live validation of each method against the MAX server is still pending. An implementation and passing unit tests do not, by themselves, prove server compatibility.

## Run auth_probe on Windows

From the repository root:

```powershell
cd apps/auth_probe
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Use the repository's generated Windows platform files. Run `flutter create .` only if the Windows runner is missing, not as part of every launch.

## Test the protocol package

```powershell
cd packages/maxai_protocol
dart pub get
dart analyze
dart test
```

## Continuous integration

[Dart Protocol CI](https://github.com/denis-aka-wolf/MaxAI/blob/dev/.github/workflows/dart_protocol.yml)

CI is intended to retrieve dependencies, run static analysis and test the `packages/maxai_protocol/` package.

## Project principles

- `auth_probe` remains a separate laboratory and is not a substitute for the main MaxAI application.
- Secrets and personal data must not appear in source files or diagnostic logs.
- TLS certificate validation must never be disabled or bypassed.
- Unknown protocol details are explicitly marked as requiring verification.
- Mutating operations are excluded from the read-only API.
- Group chats are excluded from AI processing according to the project's established requirement.
- Automatic message sending is disabled by default and requires explicit permission.
