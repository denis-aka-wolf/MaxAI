# Development Workflow and VS Code Launch

[RU](DEVELOPMENT_WORKFLOW.md) | [ENG](ENG_DEVELOPMENT_WORKFLOW.md)

This document describes automated checks and how to launch the MAX Auth Probe test application from Visual Studio Code.

## Requirements

- Visual Studio Code.
- The **Dart** extension (which also provides Flutter support).
- The `flutter` and `dart` commands installed and available on PATH.
- Flutter SDK with Windows Desktop support.
- The MaxAI repository root opened in VS Code, not an individual app or package directory.

## Configuration files

The repository root contains:

- `.vscode/launch.json` for launch and debug configurations.
- `.vscode/tasks.json` for project validation tasks.

Both configurations use paths relative to `${workspaceFolder}`, so VS Code must open the repository root as the workspace.

## Launching Auth Probe with pre-launch checks

In VS Code, select **Auth Probe: Validate and Launch (Windows)** in the Run and Debug panel and press **F5**.

Before launching the application, VS Code runs these commands sequentially:

1. `flutter analyze` in `apps/auth_probe`.
2. `flutter test` in `apps/auth_probe`.

If either check fails, the pre-launch task fails and the application is not launched. If both checks pass, VS Code launches the Flutter application on the `windows` device under the debugger.

Equivalent terminal command:

```powershell
cd apps/auth_probe
flutter run -d windows
```

## Validating the maxai_protocol package

Package validation is separate from launching Auth Probe.

1. Open the Command Palette: **Ctrl + Shift + P**.
2. Select **Tasks: Run Task**.
3. Run **MaxAI Protocol: Analyze + Test**.

It sequentially runs:

```powershell
cd packages/maxai_protocol
dart analyze
dart test
```

The checks can also be run individually:

- **MaxAI Protocol: Dart Analyze**
- **MaxAI Protocol: Dart Test**

## Available VS Code tasks

| Task name | Working directory | Action |
|---|---|---|
| Auth Probe: Flutter Analyze | `apps/auth_probe` | Static analysis of the Flutter app |
| Auth Probe: Flutter Test | `apps/auth_probe` | Flutter app tests |
| Auth Probe: Analyze + Test | `apps/auth_probe` | Runs both checks sequentially |
| MaxAI Protocol: Dart Analyze | `packages/maxai_protocol` | Static analysis of the Dart package |
| MaxAI Protocol: Dart Test | `packages/maxai_protocol` | Dart package tests |
| MaxAI Protocol: Analyze + Test | `packages/maxai_protocol` | Runs both checks sequentially |

## Notes

- Checks run sequentially, not in parallel.
- Launching Auth Probe with F5 always runs the Flutter checks first.
- `maxai_protocol` checks are intentionally not part of the Auth Probe launch sequence: the package has its own validation cycle.
- If VS Code cannot find `flutter` or `dart`, verify PATH and the Flutter/Dart SDK settings, then restart VS Code.
- If the `windows` device is unavailable, verify the Windows Desktop toolchain with `flutter doctor`.

## Configuration files

- [launch.json](../.vscode/launch.json)
- [tasks.json](../.vscode/tasks.json)
- [Auth Probe application README](../apps/auth_probe/README.md)
