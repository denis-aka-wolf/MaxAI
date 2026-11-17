import 'dart:typed_data';

import '../connection/protocol_command.dart';
import '../connection/protocol_connection.dart';
import '../connection/protocol_connection_state.dart';
import '../session/device_type.dart';
import '../session/max_user_agent.dart';
import '../session/session_manager.dart';
import '../session/session_state.dart';
import '../session/sync_state.dart';
import 'fingerprint_provider.dart';
import 'login_models.dart';
import 'login_payloads.dart';

typedef LoginLogHandler = void Function(String event);

/// Выполняет LOGIN и условный LOGIN2 после получения auth token.
/// Токен и sync state возвращаются вызывающему слою и здесь не сохраняются.
final class LoginManager {
  LoginManager({
    required this.connection,
    required this.sessionManager,
    required this.deviceType,
    required this.userAgent,
    required this.deviceId,
    this.fingerprintProvider,
    this.architecture = 'arm64-v8a',
    this.interactive = true,
    this.requestTimeout = const Duration(seconds: 30),
    this.onLog,
  }) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty.');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout', 'Must be positive.');
    }
    if (userAgent.deviceType != deviceType) {
      throw ArgumentError('deviceType must match userAgent.deviceType.');
    }
  }

  static const int loginOpcode = 19;
  static const int login2Opcode = 8;

  final ProtocolConnection connection;
  final SessionManager sessionManager;
  final DeviceType deviceType;
  final MaxUserAgent userAgent;
  final String deviceId;
  final FingerprintProvider? fingerprintProvider;
  final String architecture;
  final bool interactive;
  final Duration requestTimeout;
  final LoginLogHandler? onLog;

  bool _inProgress = false;

  Future<LoginBootstrapResult> login({
    required String token,
    SyncState syncState = const SyncState(),
  }) async {
    _ensureReady();
    if (_inProgress) {
      throw StateError('A LOGIN operation is already in progress.');
    }
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'Must not be empty.');
    }

    _inProgress = true;
    try {
      onLog?.call('Отправка LOGIN.');
      final loginRaw = await _invoke(loginOpcode, _buildLoginPayload(token, syncState));
      final loginResponse = LoginResponse.fromPayload(loginRaw);
      var updatedSync = loginResponse.updateSyncState(syncState);

      final refreshedToken = loginResponse.token;
      final effectiveToken = refreshedToken != null && refreshedToken.isNotEmpty
          ? refreshedToken
          : token;

      Login2Response? login2Response;
      final flags = loginResponse.login2Flags;
      if (flags != null && flags.enabled) {
        onLog?.call('LOGIN2 требуется по флагам сервера.');
        final payload = LoginPayloads.login2(
          sync: updatedSync,
          profileEnabled: flags.profileEnabled,
          contactEnabled: flags.contactEnabled,
        );
        login2Response = Login2Response.fromPayload(
          await _invoke(login2Opcode, payload),
        );
        updatedSync = login2Response.updateSyncState(updatedSync);
      }

      return LoginBootstrapResult(
        login: loginResponse,
        login2: login2Response,
        syncState: updatedSync,
        effectiveToken: effectiveToken,
      );
    } finally {
      _inProgress = false;
    }
  }

  Map<String, Object?> _buildLoginPayload(String token, SyncState sync) {
    if (deviceType == DeviceType.web) {
      return LoginPayloads.web(
        token: token,
        sync: sync,
        interactive: interactive,
      );
    }

    final callsSeed = sessionManager.handshakeResponse?.callsSeed;
    if (callsSeed == null) {
      throw StateError('Mobile LOGIN requires callsSeed from SESSION_INIT.');
    }
    final provider = fingerprintProvider;
    if (provider == null) {
      throw StateError('Mobile LOGIN requires a configured FingerprintProvider.');
    }
    final Uint8List fingerprint = provider.generate(
      deviceId: deviceId,
      callsSeed: callsSeed,
      architecture: architecture,
    );
    return LoginPayloads.mobile(
      userAgent: userAgent,
      token: token,
      sync: sync,
      chatCacheFingerprint: fingerprint,
      interactive: interactive,
    );
  }

  Future<Object?> _invoke(int opcode, Map<String, Object?> payload) async {
    final response = await connection.request(
      opcode: opcode,
      payload: payload,
      timeout: requestTimeout,
    );
    if (response.commandType == ProtocolCommand.error) {
      throw LoginProtocolException(
        'MAX returned ERROR for LOGIN opcode $opcode.',
        opcode: opcode,
      );
    }
    if (response.commandType != ProtocolCommand.response) {
      throw LoginProtocolException(
        'Unexpected command for LOGIN opcode $opcode.',
        opcode: opcode,
      );
    }
    if (response.opcode != opcode) {
      throw LoginProtocolException(
        'Unexpected response opcode ${response.opcode} for LOGIN opcode $opcode.',
        opcode: opcode,
      );
    }
    return response.payload;
  }

  void _ensureReady() {
    if (sessionManager.state != SessionState.ready ||
        !sessionManager.isReady ||
        sessionManager.handshakeResponse == null) {
      throw StateError('SESSION_INIT must complete before LOGIN.');
    }
    if (connection.state != ProtocolConnectionState.connected ||
        !connection.isConnected) {
      throw StateError('ProtocolConnection is not connected.');
    }
  }
}

final class LoginProtocolException implements Exception {
  const LoginProtocolException(this.message, {required this.opcode});

  final String message;
  final int opcode;

  @override
  String toString() =>
      'LoginProtocolException(opcode: $opcode, message: $message)';
}
