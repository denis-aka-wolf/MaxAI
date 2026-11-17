import 'dart:async';
import 'dart:typed_data';

import '../connection/protocol_command.dart';
import '../connection/protocol_connection.dart';
import '../connection/protocol_connection_state.dart';
import '../session/device_type.dart';
import '../session/session_manager.dart';
import '../session/session_state.dart';
import 'auth_models.dart';
import 'auth_payloads.dart';
import 'fingerprint_provider.dart';

typedef AuthLogHandler = void Function(String event);

/// Управляет SMS- и QR-авторизацией поверх установленного SESSION_INIT.
///
/// Класс не сохраняет токены. Полученный токен должен быть передан в отдельное
/// защищённое хранилище приложения. Значения токенов, паролей и SMS-кодов
/// намеренно не попадают в диагностические сообщения.
final class AuthManager {
  AuthManager({
    required this.connection,
    required this.sessionManager,
    required this.deviceType,
    required this.deviceId,
    this.fingerprintProvider,
    this.architecture = 'arm64-v8a',
    this.requestTimeout = const Duration(seconds: 20),
    this.onLog,
  }) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty.');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive.',
      );
    }
  }

  static const int authRequestOpcode = 17;
  static const int authOpcode = 18;
  static const int authConfirmOpcode = 23;
  static const int authLoginCheckPasswordOpcode = 115;
  static const int getQrOpcode = 288;
  static const int getQrStatusOpcode = 289;
  static const int loginByQrOpcode = 291;

  final ProtocolConnection connection;
  final SessionManager sessionManager;
  final DeviceType deviceType;
  final String deviceId;
  final FingerprintProvider? fingerprintProvider;
  final String architecture;
  final Duration requestTimeout;
  final AuthLogHandler? onLog;

  bool _operationInProgress = false;

  Future<SmsCodeRequest> requestSmsCode(String phone) async {
    _ensureReady();
    return _runExclusive(() async {
      Uint8List? mode;
      if (deviceType != DeviceType.web) {
        final seed = sessionManager.handshakeResponse?.callsSeed;
        if (seed == null) {
          throw StateError(
            'Mobile SMS authentication requires callsSeed from SESSION_INIT.',
          );
        }
        final provider = fingerprintProvider;
        if (provider == null) {
          throw StateError(
            'Mobile SMS authentication requires a configured APK fingerprint provider.',
          );
        }
        mode = provider.generate(
          deviceId: deviceId,
          callsSeed: seed,
          architecture: architecture,
        );
      }

      onLog?.call('Запрос SMS-кода авторизации.');
      final payload = await _invoke(
        authRequestOpcode,
        AuthPayloads.requestSmsCode(phone: phone, mode: mode),
      );
      return SmsCodeRequest.fromPayload(payload);
    });
  }

  Future<AuthResult> submitSmsCode({
    required String requestToken,
    required String code,
  }) async {
    _ensureReady();
    return _runExclusive(() async {
      onLog?.call('Отправка кода подтверждения.');
      final payload = await _invoke(
        authOpcode,
        AuthPayloads.submitSmsCode(token: requestToken, code: code),
      );
      return authResultFromPayload(payload);
    });
  }

  Future<AuthResult> submitTwoFactorPassword({
    required PasswordChallenge challenge,
    required String password,
  }) async {
    _ensureReady();
    return _runExclusive(() async {
      onLog?.call('Проверка пароля двухфакторной аутентификации.');
      final payload = await _invoke(
        authLoginCheckPasswordOpcode,
        AuthPayloads.checkPassword(
          trackId: challenge.trackId,
          password: password,
        ),
      );
      final result = authResultFromPayload(payload);
      if (!result.isAuthenticated) {
        throw const FormatException(
          '2FA response did not contain a login token.',
        );
      }
      return result;
    });
  }

  Future<QrLoginRequest> requestQrLogin() async {
    _ensureReady();
    return _runExclusive(() async {
      onLog?.call('Запрос QR-кода авторизации.');
      final payload = await _invoke(getQrOpcode, <String, Object?>{});
      _logQrPayload(payload);
      return QrLoginRequest.fromPayload(payload);
    });
  }

  /// Ожидает подтверждения QR до истечения срока действия ссылки.
  /// Возвращает false при истечении срока и true после подтверждения.
  Future<bool> waitForQrApproval(
    QrLoginRequest request, {
    void Function(QrLoginStatus status)? onStatus,
  }) async {
    while (DateTime.now().millisecondsSinceEpoch < request.expiresAt) {
      final status = await checkQrLogin(request.trackId);
      onStatus?.call(status);
      if (status.loginAvailable == true) return true;
      final remaining = request.expiresAt - DateTime.now().millisecondsSinceEpoch;
      if (remaining <= 0) break;
      final delay = request.pollingInterval < remaining
          ? request.pollingInterval
          : remaining;
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
    return false;
  }

  Future<QrLoginStatus> checkQrLogin(String trackId) async {
    _ensureReady();
    return _runExclusive(() async {
      final payload = await _invoke(
        getQrStatusOpcode,
        AuthPayloads.checkQr(trackId: trackId),
      );
      return QrLoginStatus.fromPayload(payload);
    });
  }

  /// Подтверждает QR после того, как GET_QR_STATUS вернул loginAvailable=true.
  Future<AuthResult> confirmQrLogin(String trackId) async {
    _ensureReady();
    return _runExclusive(() async {
      onLog?.call('Подтверждение QR-авторизации.');
      final payload = await _invoke(
        loginByQrOpcode,
        AuthPayloads.confirmQr(trackId: trackId),
      );
      _logAuthPayload('LOGIN_BY_QR', payload);
      return authResultFromPayload(payload);
    });
  }

  /// Подтверждение регистрации нового аккаунта, если сервер вернул REGISTER.
  Future<AuthResult> confirmRegistration({
    required String firstName,
    String? lastName,
    required String registrationToken,
  }) async {
    _ensureReady();
    return _runExclusive(() async {
      onLog?.call('Подтверждение регистрации аккаунта.');
      final payload = await _invoke(
        authConfirmOpcode,
        AuthPayloads.confirmRegistration(
          firstName: firstName,
          lastName: lastName,
          token: registrationToken,
        ),
      );
      final map = _asStringMap(payload, 'AUTH_CONFIRM');
      final token = map['token'];
      if (token is! String || token.isEmpty) {
        throw const FormatException(
          'AUTH_CONFIRM response does not contain a login token.',
        );
      }
      return AuthResult(stage: AuthStage.authenticated, token: token);
    });
  }

  Future<Object?> _invoke(int opcode, Map<String, Object?> payload) async {
    final response = await connection.request(
      opcode: opcode,
      payload: payload,
      timeout: requestTimeout,
    );

    if (response.commandType == ProtocolCommand.error) {
      // Не выводим серверный payload: он потенциально может содержать токены.
      throw AuthProtocolException(
        'MAX returned ERROR for auth opcode $opcode.',
        opcode: opcode,
      );
    }
    if (response.commandType != ProtocolCommand.response) {
      throw AuthProtocolException(
        'Unexpected command for auth opcode $opcode.',
        opcode: opcode,
      );
    }
    if (response.opcode != opcode) {
      throw AuthProtocolException(
        'Unexpected response opcode ${response.opcode} for auth opcode $opcode.',
        opcode: opcode,
      );
    }
    return response.payload;
  }

  /// Печатает структуру ответа авторизации до разбора моделью.
  ///
  /// Контейнеры tokenAttrs/passwordChallenge раскрываются рекурсивно,
  /// но сами секретные значения (токены, пароли, коды и идентификаторы
  /// QR-сессии) маскируются.
  void _logAuthPayload(String operation, Object? payload) {
    onLog?.call('$operation response payload: '
        '${_formatDiagnosticValue(payload)}');
  }

  /// Печатает структуру ответа GET_QR до разбора моделью.
  ///
  /// Значения, которые позволяют воспользоваться чужой QR-сессией, не
  /// выводятся: qrLink, trackId и любые поля с token/secret/password/code.
  void _logQrPayload(Object? payload) {
    final buffer = StringBuffer('GET_QR response payload: ');
    if (payload is Map) {
      buffer.write('Map(length=${payload.length}) {');
      var index = 0;
      for (final entry in payload.entries) {
        if (index > 0) buffer.write(', ');
        final key = entry.key;
        buffer.write('${_formatDiagnosticValue(key)}: ');
        final keyName = key is String ? key : '';
        buffer.write(_formatDiagnosticValue(entry.value, key: keyName));
        index++;
      }
      buffer.write('}');
    } else {
      buffer.write(_formatDiagnosticValue(payload));
    }
    onLog?.call(buffer.toString());
  }

  String _formatDiagnosticValue(
    Object? value, {
    String key = '',
    int depth = 0,
    bool redactStringValues = false,
  }) {
    final normalizedKey = key.toLowerCase();
    final redactNestedStrings =
        redactStringValues || normalizedKey == 'tokenattrs';
    final isContainer = value is Map || value is List;
    final isSensitiveField = isSensitiveDiagnosticKey(normalizedKey);
    if (isSensitiveField && !isContainer) {
      final details = switch (value) {
        null => 'null',
        String text => 'String(length=${text.length})',
        Uint8List bytes => 'Uint8List(length=${bytes.length})',
        List list => 'List(length=${list.length})',
        Map map => 'Map(length=${map.length})',
        _ => value.runtimeType.toString(),
      };
      return '<REDACTED $details>';
    }

    if (value == null) return 'null (Null)';
    if (value is String) {
      if (redactNestedStrings) {
        return '<REDACTED String(length=${value.length})>';
      }
      final visible = value.length <= 200
          ? value
          : '${value.substring(0, 200)}… (length=${value.length})';
      return '${_quoteDiagnosticString(visible)} (String)';
    }
    if (value is num || value is bool) {
      return '$value (${value.runtimeType})';
    }
    if (value is Uint8List) {
      return 'Uint8List(length=${value.length})';
    }
    if (value is List) {
      if (depth >= 3) return 'List(length=${value.length})';
      final items = value.take(30).map(
        (item) => _formatDiagnosticValue(item, depth: depth + 1),
      );
      final suffix = value.length > 30 ? ', …' : '';
      return '[${items.join(', ')}$suffix] (List length=${value.length})';
    }
    if (value is Map) {
      if (depth >= 3) return 'Map(length=${value.length})';
      final entries = <String>[];
      for (final entry in value.entries.take(30)) {
        final entryKey = entry.key;
        entries.add(
          '${_formatDiagnosticValue(entryKey)}: '
          '${_formatDiagnosticValue(
            entry.value,
            key: entryKey is String ? entryKey : '',
            depth: depth + 1,
            redactStringValues: redactNestedStrings,
          )}',
        );
      }
      if (value.length > 30) entries.add('…');
      return '{${entries.join(', ')}} (Map length=${value.length})';
    }
    return '<${value.runtimeType}>';
  }

  bool isSensitiveDiagnosticKey(String key) {
    return key.contains('token') ||
        key.contains('secret') ||
        key.contains('password') ||
        key.contains('qr') ||
        key.contains('trackid') ||
        key.contains('phone') ||
        key.contains('code') ||
        key.contains('authorization') ||
        key.contains('cookie');
  }

  String _quoteDiagnosticString(String value) {
    return '"${value.replaceAll(r'\\', r'\\\\').replaceAll('"', r'\\"').replaceAll('\n', r'\\n').replaceAll('\r', r'\\r')}"';
  }

  void _ensureReady() {
    if (sessionManager.state != SessionState.ready ||
        !sessionManager.isReady ||
        sessionManager.handshakeResponse == null) {
      throw StateError(
        'SESSION_INIT must complete successfully before authentication.',
      );
    }
    if (connection.state != ProtocolConnectionState.connected ||
        !connection.isConnected) {
      throw StateError('ProtocolConnection is not connected.');
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) async {
    if (_operationInProgress) {
      throw StateError('Another authentication operation is in progress.');
    }
    _operationInProgress = true;
    try {
      return await action();
    } finally {
      _operationInProgress = false;
    }
  }

  static Map<String, Object?> _asStringMap(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('$field response payload must be a map.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$field response contains a non-string key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}

final class AuthProtocolException implements Exception {
  const AuthProtocolException(this.message, {required this.opcode});

  final String message;
  final int opcode;

  @override
  String toString() => 'AuthProtocolException(opcode: $opcode, message: $message)';
}
