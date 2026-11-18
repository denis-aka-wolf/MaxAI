import 'dart:async';
import 'dart:math';
import 'dart:io';

// Flutter SDK marks the Material library deprecated in newer prerelease builds.
// Keep the stable Flutter Material API until its replacement is available in stable.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/windows_dpapi_storage.dart';
import 'services/windows_certificate_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AuthProbeApp());
}

class AuthProbeApp extends StatelessWidget {
  const AuthProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAX Auth Probe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5267D8)),
        useMaterial3: true,
      ),
      home: const AuthProbeScreen(),
    );
  }
}


class _TwoFactorPasswordDialog extends StatefulWidget {
  const _TwoFactorPasswordDialog({this.hint});

  final String? hint;

  @override
  State<_TwoFactorPasswordDialog> createState() =>
      _TwoFactorPasswordDialogState();
}

class _TwoFactorPasswordDialogState
    extends State<_TwoFactorPasswordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text.trim();
    if (password.isNotEmpty) {
      Navigator.of(context).pop(password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.hint;
    return AlertDialog(
      title: const Text('Подтверждение входа MAX'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Для завершения входа MAX требует пароль двухфакторной аутентификации.',
          ),
          if (hint != null && hint.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Подсказка: $hint'),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Пароль 2FA',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Продолжить'),
        ),
      ],
    );
  }
}


class _SmsCodeDialog extends StatefulWidget {
  const _SmsCodeDialog({required this.codeLength});

  final int codeLength;

  @override
  State<_SmsCodeDialog> createState() => _SmsCodeDialogState();
}

class _SmsCodeDialogState extends State<_SmsCodeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isNotEmpty) {
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Подтверждение по SMS'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.codeLength > 0
                ? 'Введи код из SMS (${widget.codeLength} цифр).'
                : 'Введи код из SMS.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: widget.codeLength > 0 ? widget.codeLength : null,
            decoration: const InputDecoration(
              labelText: 'Код подтверждения',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Подтвердить'),
        ),
      ],
    );
  }
}

class AuthProbeScreen extends StatefulWidget {
  const AuthProbeScreen({super.key});

  @override
  State<AuthProbeScreen> createState() => _AuthProbeScreenState();
}

class _AuthProbeScreenState extends State<AuthProbeScreen> {
  static final Uri _defaultUri = Uri.parse('wss://api.oneme.ru/websocket');
  static const String _tokenStorageKey = 'maxai.auth.token';
  static const String _deviceIdStorageKey = 'maxai.auth.device_id';
  static const String _mtInstanceIdStorageKey = 'maxai.auth.mt_instance_id';
  static const String _authMethodStorageKey = 'maxai.auth.method';

  final _uriController = TextEditingController(text: _defaultUri.toString());
  final _timezoneController = TextEditingController(text: 'Europe/Helsinki');
  final _phoneController = TextEditingController();
  final _apiContactIdController = TextEditingController();
  final _apiChatIdController = TextEditingController();

  ProtocolConnection? _connection;
  SessionManager? _sessionManager;
  QrLoginRequest? _qrRequest;
  Timer? _pollTimer;

  final List<String> _logs = <String>[];
  bool _busy = false;
  bool _connected = false;
  bool _authenticated = false;
  bool _loginComplete = false;
  String _status = 'Не подключено';
  String? _profileSummary;
  MaxAuthenticatedSession? _authenticatedSession;
  String? _error;
  String _rootCertificateStatus = 'Не проверен';
  String _intermediateCertificateStatus = 'Не проверен';
  String _windowsTlsStatus = 'Не проверено';
  String _maxAiTlsStatus = 'Не проверено';
  bool _certificateBusy = false;
  bool _apiBusy = false;
  List<Map<String, Object?>> _lastApiChats = <Map<String, Object?>>[];
  List<Map<String, Object?>> _lastApiContacts = <Map<String, Object?>>[];

  final WindowsCertificateManager _certificateManager =
      WindowsCertificateManager();
  @override
  void initState() {
    super.initState();
    _restoreSessionOnStartup();
  }

  Future<void> _restoreSessionOnStartup() async {
    try {
      final token = await WindowsDpapiStorage.read(key: _tokenStorageKey);
      if (!mounted || token == null || token.isEmpty) return;
      final method = await WindowsDpapiStorage.read(
        key: _authMethodStorageKey,
      );
      _log('Найдена сохранённая авторизация. Пробуем восстановить сессию.');
      await _connectAndStartQr(useSms: method == 'mobile');
    } catch (error) {
      _log('Не удалось прочитать сохранённую авторизацию: ${_safeError(error)}');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _closeConnection();
    _uriController.dispose();
    _timezoneController.dispose();
    _phoneController.dispose();
    _apiContactIdController.dispose();
    _apiChatIdController.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _logs.insert(0, '$stamp  $message');
      if (_logs.length > 300) _logs.removeLast();
    });
  }

  Future<String> _loadOrCreateDeviceId() async {
    final saved = await WindowsDpapiStorage.read(key: _deviceIdStorageKey);
    if (saved != null && saved.isNotEmpty) return saved;

    final random = Random.secure();
    final deviceId = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await WindowsDpapiStorage.write(key: _deviceIdStorageKey, value: deviceId);
    return deviceId;
  }

  Future<String> _loadOrCreateMtInstanceId() async {
    final saved = await WindowsDpapiStorage.read(
      key: _mtInstanceIdStorageKey,
    );
    if (saved != null && saved.isNotEmpty) return saved;

    final random = Random.secure();
    final value = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await WindowsDpapiStorage.write(
      key: _mtInstanceIdStorageKey,
      value: value,
    );
    return value;
  }

  MaxUserAgent _createMobileUserAgent() {
    final timezone = _timezoneController.text.trim();
    if (timezone.isEmpty) {
      throw ArgumentError('Укажи часовой пояс.');
    }
    return MaxUserAgent(
      deviceType: DeviceType.android,
      appVersion: '26.37.1',
      osVersion: 'Android 14',
      timezone: timezone,
      screen: '420dpi 420dpi 1080x2400',
      pushDeviceType: 'GCM',
      arch: 'arm64-v8a',
      locale: 'ru',
      buildNumber: 6900,
      deviceName: 'Google Pixel 8',
      deviceLocale: 'ru',
    );
  }

  FingerprintProvider _createMobileFingerprintProvider() {
    return Sha256FingerprintProvider(
      const ApkFingerprintConfig(
        certificateMetaSha256:
            '1684414033eb263e2c615f8b7df5ed8793850a07656304997fbf07e9e21e1e93',
        dexMetaSha256:
            'dfa98ab26b96aed92da79424d30b71d265a51d8df4d2278c1a53e78a877f647b',
        soMetaSha256: <String, String>{
          'arm64-v8a':
              '09d48edd1d5de5ff00f8dab591b69a5f2bea41d74747a8bbede13a682d3a9aa7',
        },
        sourceVersion: '26.37.1',
      ),
    );
  }

  MaxUserAgent _createWebUserAgent() {
    final timezone = _timezoneController.text.trim();
    if (timezone.isEmpty) {
      throw ArgumentError('Укажи часовой пояс.');
    }
    return MaxUserAgent(
      deviceType: DeviceType.web,
      appVersion: '26.8.4',
      osVersion: 'Linux',
      timezone: timezone,
      screen: '1080x1920 1.0x',
      locale: 'ru',
      deviceName: 'Chrome',
      deviceLocale: 'ru',
      headerUserAgent:
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    );
  }

  Future<SecurityContext> _prepareWindowsTlsContext() async {
    final context = await _certificateManager.createTlsContext();
    _log('TLS-контекст создан: системные корни Windows + закреплённый Russian Trusted Root CA.');
    return context;
  }

  Future<bool> _confirmCertificateInstall(
    WindowsCertificateKind kind,
    WindowsCertificateInfo info,
  ) async {
    if (!mounted) return false;
    final isRoot = kind == WindowsCertificateKind.root;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(isRoot ? 'Установка корневого сертификата' : 'Установка промежуточного сертификата'),
            content: SelectableText(
              '${info.subject}\nSHA-1: ${info.thumbprint}\nSHA-256: ${info.sha256}\n\n'
              'Установка в хранилище текущего пользователя Windows: ${isRoot ? 'Root' : 'CA'}. '
              'Это повлияет на доверие Windows и приложений текущего пользователя. '
              'Права администратора не требуются.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Установить')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runCertificateCheck(WindowsCertificateKind kind) async {
    if (_certificateBusy || _busy) return;
    setState(() => _certificateBusy = true);
    final isRoot = kind == WindowsCertificateKind.root;
    try {
      _log('Проверка ${isRoot ? 'корневого' : 'промежуточного'} сертификата: источник, отпечатки, Subject/Issuer, CA и срок действия.');
      final info = await _certificateManager.inspect(kind);
      final status = info.currentUserInstalled
          ? 'Установлен: CurrentUser'
          : info.localMachineInstalled
              ? 'Установлен: LocalMachine'
              : 'Проверен, не установлен';
      if (mounted) {
        setState(() {
          if (isRoot) {
            _rootCertificateStatus = status;
          } else {
            _intermediateCertificateStatus = status;
          }
        });
      }
      _log(info.subject);
      _log('Issuer: ${info.issuer}');
      _log('SHA-1: ${info.thumbprint}; SHA-256: ${info.sha256}');
      _log('Срок действия: ${info.notBefore} - ${info.notAfter}');
      _log('Windows stores: CurrentUser=${info.currentUserInstalled}, LocalMachine=${info.localMachineInstalled}.');
    } catch (error) {
      _log('Ошибка проверки сертификата: ${_safeError(error)}');
      if (mounted) {
        setState(() {
          if (isRoot) {
            _rootCertificateStatus = 'Ошибка проверки';
          } else {
            _intermediateCertificateStatus = 'Ошибка проверки';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _certificateBusy = false);
    }
  }

  Future<void> _installCertificate(WindowsCertificateKind kind) async {
    if (_certificateBusy || _busy) return;
    setState(() => _certificateBusy = true);
    final isRoot = kind == WindowsCertificateKind.root;
    try {
      final info = await _certificateManager.inspect(kind);
      if (info.installed) {
        _log('Сертификат уже установлен в Windows. Повторная установка не требуется.');
      } else if (await _confirmCertificateInstall(kind, info)) {
        await _certificateManager.install(kind);
        _log(isRoot
            ? 'Russian Trusted Root CA установлен в CurrentUser\\Root.'
            : 'Russian Trusted Sub CA 2024 установлен в CurrentUser\\CA.');
      } else {
        _log('Установка отменена. Хранилище Windows не изменено.');
      }
      final refreshed = await _certificateManager.inspect(kind);
      final status = refreshed.currentUserInstalled
          ? 'Установлен: CurrentUser'
          : refreshed.localMachineInstalled
              ? 'Установлен: LocalMachine'
              : 'Проверен, не установлен';
      if (mounted) {
        setState(() {
          if (isRoot) {
            _rootCertificateStatus = status;
          } else {
            _intermediateCertificateStatus = status;
          }
        });
      }
    } catch (error) {
      _log('Установка сертификата не удалась: ${_safeError(error)}');
    } finally {
      if (mounted) setState(() => _certificateBusy = false);
    }
  }

  Future<void> _checkApiTls({required bool usePinnedRoot}) async {
    if (_certificateBusy || _busy) return;
    setState(() {
      _certificateBusy = true;
      if (usePinnedRoot) {
        _maxAiTlsStatus = 'Проверяется...';
      } else {
        _windowsTlsStatus = 'Проверяется...';
      }
    });
    SecureSocket? socket;
    try {
      _log(usePinnedRoot
          ? 'TLS-проверка api2.oneme.ru:443 через TLS-контекст MaxAI с закреплённым корневым сертификатом.'
          : 'TLS-проверка api2.oneme.ru:443 через стандартный TLS-контекст Dart без дополнительных сертификатов.');
      final tlsContext = usePinnedRoot
          ? await _certificateManager.createTlsContext()
          : null;
      socket = await SecureSocket.connect(
        'api2.oneme.ru',
        443,
        context: tlsContext,
        timeout: const Duration(seconds: 20),
      );
      final peer = socket.peerCertificate;
      _log('TLS handshake успешен: api2.oneme.ru:443.');
      if (peer != null) {
        _log('Leaf: ${peer.subject}');
        _log('Issuer: ${peer.issuer}');
        _log('Срок действия leaf: ${peer.startValidity} - ${peer.endValidity}');
      }
      if (mounted) {
        setState(() {
          if (usePinnedRoot) {
            _maxAiTlsStatus = 'Успешно';
          } else {
            _windowsTlsStatus = 'Успешно';
          }
        });
      }
    } catch (error) {
      _log('TLS-проверка ${usePinnedRoot ? 'MaxAI' : 'Windows'} не пройдена: ${_safeError(error)}');
      if (mounted) {
        setState(() {
          if (usePinnedRoot) {
            _maxAiTlsStatus = 'Ошибка TLS';
          } else {
            _windowsTlsStatus = 'Ошибка TLS';
          }
        });
      }
    } finally {
      socket?.destroy();
      if (mounted) setState(() => _certificateBusy = false);
    }
  }

  Future<void> _connectAndStartQr({bool useSms = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Подключение';
      _qrRequest = null;
      _authenticated = false;
      _loginComplete = false;
      _profileSummary = null;
      _authenticatedSession = null;
    });

    try {
      final Uri? uri;
      if (useSms) {
        uri = null;
      } else {
        uri = Uri.parse(_uriController.text.trim());
        if (uri.scheme != 'wss' && uri.scheme != 'ws') {
          throw const FormatException(
            'Адрес должен начинаться с ws:// или wss://.',
          );
        }
      }

      final deviceId = await _loadOrCreateDeviceId();
      final userAgent = useSms
          ? _createMobileUserAgent()
          : _createWebUserAgent();
      final fingerprintProvider =
          useSms ? _createMobileFingerprintProvider() : null;
      final frameCodec = const TcpFrameCodec(
        payloadCodec: MessagePackPayloadCodec(),
      );
      final SecurityContext? tlsContext =
          useSms && Platform.isWindows ? await _prepareWindowsTlsContext() : null;
      final ProtocolTransport transport = useSms
          ? TcpSocketTransport(
              host: 'api2.oneme.ru',
              port: 443,
              securityContext: tlsContext,
            )
          : WebSocketTransport(
              uri: uri!,
              headers: <String, dynamic>{
                'Origin': 'https://web.max.ru',
                if (userAgent.headerUserAgent != null)
                  'User-Agent': userAgent.headerUserAgent!,
              },
            );
      final connection = ProtocolConnection(
        transport: transport,
        codec: frameCodec,
        onFrame: (frame) {
          if (frame.opcode == AuthManager.getQrOpcode) {
            final rawBytes = frame.frame.payload;
            final decodedBytes = frameCodec.decodePayloadBytes(frame.frame);
            _log(
              'GET_QR FRAME HEADER: version=${frame.version}, '
              'command=${frame.command}, sequence=${frame.sequence}, '
              'opcode=${frame.opcode}, flags=${frame.flags}, '
              'compressedPayloadLength=${rawBytes.length}, '
              'decompressedPayloadLength=${decodedBytes.length}.',
            );
            _log(
              'GET_QR payload bytes captured for diagnostics only; '
              'raw content omitted to protect QR URL and trackId.',
            );
          }
          final payload = frame.payload;
          final payloadDescription = switch (payload) {
            null => 'null',
            int value => 'int($value)',
            bool value => 'bool($value)',
            String value => 'string(length=${value.length})',
            Map value => 'map(keys=${value.keys.take(20).join(",")})',
            List value => 'list(length=${value.length})',
            _ => payload.runtimeType.toString(),
          };
          _log(
            'Входящий frame: command=${frame.command}, '
            'sequence=${frame.sequence}, opcode=${frame.opcode}, '
            'flags=${frame.flags}, payload=$payloadDescription.',
          );
        },
      );
      _connection = connection;

      _log(useSms
          ? 'Открываем TCP/TLS: api2.oneme.ru:443'
          : 'Открываем WebSocket: ${uri!.host}');
      await connection.connect();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = useSms ? 'TCP/TLS подключён' : 'WebSocket подключён';
      });
      _log(useSms
          ? 'TCP/TLS соединение установлено.'
          : 'WebSocket соединение установлено.');

      final session = SessionManager(connection: connection);
      _sessionManager = session;
      _log('Отправляем SESSION_INIT (opcode 6).');
      final HandshakeResponse handshake;
      if (useSms) {
        final mtInstanceId = await _loadOrCreateMtInstanceId();
        handshake = await session.startMobile(
          mtInstanceId: mtInstanceId,
          userAgent: userAgent,
          deviceId: deviceId,
        );
      } else {
        handshake = await session.startWeb(
          userAgent: userAgent,
          deviceId: deviceId,
        );
      }
      _log('SESSION_INIT успешно завершён. callsSeed: ${handshake.callsSeed == null ? "не получен" : "получен"}.');
      final auth = AuthManager(
        connection: connection,
        sessionManager: session,
        deviceType: useSms ? DeviceType.android : DeviceType.web,
        deviceId: deviceId,
        fingerprintProvider: fingerprintProvider,
        architecture: 'arm64-v8a',
        onLog: _log,
      );

      final savedToken = await WindowsDpapiStorage.read(key: _tokenStorageKey);
      if (useSms) {
        if (savedToken != null && savedToken.isNotEmpty) {
          _log('Сохранённый мобильный токен найден. Выполняем LOGIN через TCP (opcode 19).');
          try {
            final login = LoginManager(
              connection: connection,
              sessionManager: session,
              deviceType: DeviceType.android,
              userAgent: userAgent,
              deviceId: deviceId,
              fingerprintProvider: fingerprintProvider,
              architecture: 'arm64-v8a',
              onLog: _log,
            );
            final result = await login.login(token: savedToken);
            await WindowsDpapiStorage.write(
              key: _tokenStorageKey,
              value: result.effectiveToken,
            );
            await WindowsDpapiStorage.write(
              key: _authMethodStorageKey,
              value: 'mobile',
            );
            _applyLoginResult(result);
          } on LoginProtocolException catch (error) {
            if (error.opcode != LoginManager.loginOpcode) rethrow;
            await WindowsDpapiStorage.delete(key: _tokenStorageKey);
            await WindowsDpapiStorage.delete(
              key: _authMethodStorageKey,
            );
            throw StateError(
              'MAX отклонил сохранённый мобильный токен. '
              'Для повторного входа по SMS укажи номер телефона.',
            );
          }
        } else {
          await _runSmsAuthentication(auth, userAgent, deviceId);
        }
        return;
      }

      if (savedToken != null && savedToken.isNotEmpty) {
        _log('Сохранённый токен найден. Выполняем восстановительный LOGIN (opcode 19).');
        try {
          final login = LoginManager(
            connection: connection,
            sessionManager: session,
            deviceType: DeviceType.web,
            userAgent: userAgent,
            deviceId: deviceId,
            onLog: _log,
          );
          final result = await login.login(token: savedToken);
          await WindowsDpapiStorage.write(
            key: _tokenStorageKey,
            value: result.effectiveToken,
          );
          _applyLoginResult(result);
          return;
        } on LoginProtocolException catch (error) {
          if (error.opcode != LoginManager.loginOpcode) rethrow;
          await WindowsDpapiStorage.delete(key: _tokenStorageKey);
          await WindowsDpapiStorage.delete(
            key: _authMethodStorageKey,
          );
          _log('Сервер отклонил сохранённый токен. Он удалён, потребуется новая QR-авторизация.');
        }
      }

      _log('Запрашиваем QR-код (opcode 288).');
      final qr = await auth.requestQrLogin();
      if (!mounted) return;
      setState(() {
        _qrRequest = qr;
        _status = 'Ожидание сканирования QR';
      });
      _log('QR-код получен. Срок действия: ${qr.expiresAtDateTime.toLocal()}.');
      _startPolling(qr, auth, userAgent, deviceId);
    } catch (error) {
      _log('Ошибка: ${_safeError(error)}');
      if (mounted) {
        setState(() {
          _error = _safeError(error);
          _status = 'Ошибка';
          _busy = false;
        });
      }
      await _closeConnection();
    }
  }


  Future<void> _connectAndStartSms() async {
    if (_loginComplete) {
      setState(() {
        _error = 'Сначала выйди из текущего аккаунта.';
      });
      return;
    }
    final savedToken = await WindowsDpapiStorage.read(key: _tokenStorageKey);
    if ((savedToken == null || savedToken.isEmpty) &&
        _phoneController.text.trim().isEmpty) {
      setState(() {
        _error = 'Укажи номер телефона в международном формате.';
      });
      return;
    }
    await _connectAndStartQr(useSms: true);
  }

  Future<void> _runSmsAuthentication(
    AuthManager auth,
    MaxUserAgent userAgent,
    String deviceId,
  ) async {
    final phone = _phoneController.text.trim();
    _log('Запрашиваем SMS-код (AUTH_REQUEST, opcode 17).');
    final smsRequest = await auth.requestSmsCode(phone);

    if (!mounted) return;
    setState(() {
      _status = 'Ожидание SMS-кода';
    });
    _log(
      'Запрос SMS принят. Ожидаем код длиной ${smsRequest.codeLength}; '
      'доступно повторных запросов: ${smsRequest.requestCountLeft}.',
    );

    final code = await _requestSmsCode(smsRequest);
    if (code == null || code.isEmpty) {
      throw StateError('Ввод SMS-кода отменён.');
    }

    _log('Отправляем SMS-код (AUTH, opcode 18).');
    var authResult = await auth.submitSmsCode(
      requestToken: smsRequest.token,
      code: code,
    );

    if (authResult.stage == AuthStage.passwordRequired) {
      final challenge = authResult.challenge;
      if (challenge == null) {
        throw StateError('MAX запросил 2FA, но не передал данные passwordChallenge.');
      }

      _log('SMS-код принят. MAX требует пароль двухфакторной аутентификации.');
      if (!mounted) return;
      setState(() {
        _status = 'Требуется пароль 2FA';
        _error = null;
      });

      final password = await _requestTwoFactorPassword(challenge.hint);
      if (password == null || password.isEmpty) {
        throw StateError('Ввод пароля двухфакторной аутентификации отменён.');
      }

      authResult = await auth.submitTwoFactorPassword(
        challenge: challenge,
        password: password,
      );
    }

    if (!authResult.isAuthenticated || authResult.token == null) {
      throw StateError(
        'SMS-авторизация не завершилась выдачей LOGIN-токена '
        '(этап: ${authResult.stage}).',
      );
    }

    if (!mounted) return;
    setState(() {
      _authenticated = true;
      _status = 'SMS подтверждён, выполняется LOGIN';
    });
    _log('SMS-авторизация завершена. Токен получен; значение скрыто.');

    final login = LoginManager(
      connection: _connection!,
      sessionManager: _sessionManager!,
      deviceType: DeviceType.android,
      userAgent: userAgent,
      deviceId: deviceId,
      fingerprintProvider: _createMobileFingerprintProvider(),
      architecture: 'arm64-v8a',
      onLog: _log,
    );

    _log('Отправляем LOGIN (opcode 19).');
    final result = await login.login(token: authResult.token!);
    await WindowsDpapiStorage.write(
      key: _tokenStorageKey,
      value: result.effectiveToken,
    );
    await WindowsDpapiStorage.write(
      key: _authMethodStorageKey,
      value: 'mobile',
    );
    _log('Мобильный токен авторизации сохранён в зашифрованном хранилище Windows DPAPI.');
    _applyLoginResult(result);
  }

  Future<String?> _requestSmsCode(SmsCodeRequest request) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SmsCodeDialog(codeLength: request.codeLength),
    );
  }

  void _startPolling(
    QrLoginRequest qr,
    AuthManager auth,
    MaxUserAgent userAgent,
    String deviceId,
  ) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(milliseconds: qr.pollingInterval),
      (_) async {
        if (!mounted || !_busy || _authenticated) return;
        try {
          if (DateTime.now().millisecondsSinceEpoch >= qr.expiresAt) {
            _pollTimer?.cancel();
            _log('Срок действия QR-кода истёк.');
            setState(() {
              _status = 'QR-код истёк';
              _busy = false;            });
            return;
          }

          final status = await auth.checkQrLogin(qr.trackId);
          _log('Проверка QR: ${status.loginAvailable == true ? "подтверждён" : "ожидает подтверждения"}.');
          if (status.loginAvailable == true) {
            _pollTimer?.cancel();
            await _completeQrLogin(auth, qr, userAgent, deviceId);
          }
        } catch (error) {
          _pollTimer?.cancel();
          _log('Ошибка проверки QR: ${_safeError(error)}');
          if (mounted) {
            setState(() {
              _error = _safeError(error);
              _status = 'Ошибка проверки QR';
              _busy = false;
            });
          }
        }
      },
    );
  }

  Future<String?> _requestTwoFactorPassword(String? hint) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TwoFactorPasswordDialog(hint: hint),
    );
  }

  Future<void> _completeQrLogin(
    AuthManager auth,
    QrLoginRequest qr,
    MaxUserAgent userAgent,
    String deviceId,
  ) async {
    _log('MAX подтвердил QR. Выполняем LOGIN_BY_QR (opcode 291).');
    var authResult = await auth.confirmQrLogin(qr.trackId);

    // Подтверждение QR может завершиться не выдачей LOGIN-токена,
    // а запросом пароля двухфакторной аутентификации.
    if (authResult.stage == AuthStage.passwordRequired) {
      final challenge = authResult.challenge;
      if (challenge == null) {
        throw StateError('MAX запросил 2FA, но не передал данные passwordChallenge.');
      }

      _log('QR подтверждён. MAX требует пароль двухфакторной аутентификации.');
      if (!mounted) return;
      setState(() {
        _status = 'Требуется пароль 2FA';
        _error = null;
      });

      final password = await _requestTwoFactorPassword(challenge.hint);
      if (password == null || password.isEmpty) {
        throw StateError('Ввод пароля двухфакторной аутентификации отменён.');
      }

      authResult = await auth.submitTwoFactorPassword(
        challenge: challenge,
        password: password,
      );
    }

    if (!authResult.isAuthenticated || authResult.token == null) {
      throw StateError(
        'MAX не выдал токен LOGIN после завершения QR/2FA-авторизации '
        '(этап: ${authResult.stage}).',
      );
    }

    if (!mounted) return;
    setState(() {
      _authenticated = true;
      _status = 'Авторизация подтверждена, выполняется LOGIN';
    });
    _log('Токен авторизации получен. Значение токена скрыто.');

    final connection = _connection!;
    final session = _sessionManager!;
    final login = LoginManager(
      connection: connection,
      sessionManager: session,
      deviceType: DeviceType.web,
      userAgent: userAgent,
      deviceId: deviceId,
      onLog: _log,
    );

    _log('Отправляем LOGIN (opcode 19).');
    final result = await login.login(token: authResult.token!);
    await WindowsDpapiStorage.write(
      key: _tokenStorageKey,
      value: result.effectiveToken,
    );
    await WindowsDpapiStorage.write(
      key: _authMethodStorageKey,
      value: 'web',
    );
    _log('Web-токен авторизации сохранён в зашифрованном хранилище Windows DPAPI.');
    _applyLoginResult(result);
  }

  void _applyLoginResult(LoginBootstrapResult result) {
    if (!mounted) return;

    final flags = result.login.login2Flags;
    final authenticatedSession = MaxAuthenticatedSession.fromLogin(result);
    final profileText = authenticatedSession.profile == null
        ? 'Профиль не передан в ответе LOGIN/LOGIN2.'
        : _summarizeProfile(authenticatedSession.profile!);

    setState(() {
      _loginComplete = true;
      _busy = false;
      _status = 'Авторизация и LOGIN завершены';
      _profileSummary = profileText;
      _authenticatedSession = authenticatedSession;
    });

    _log('LOGIN завершён. Чатов: ${result.login.chats.length}; контактов: ${result.contacts.length}; сообщений в начальном ответе: ${result.login.messages.length}.');
    if (flags != null) {
      _log('Флаги LOGIN2: config=${flags.configEnabled}, contacts=${flags.contactEnabled}, profile=${flags.profileEnabled}.');
    } else {
      _log('Сервер не передал login2Flags. LOGIN2 не выполнялся.');
    }
    if (result.login2 != null) {
      _log('LOGIN2 завершён успешно.');
    }
    _log('Восстановление/проверка авторизации завершены. Токен хранится в защищённом хранилище.');
  }

  String _summarizeProfile(MaxUserProfile profile) {
    final contact = profile.contact;
    return <String>[
      if (profile.displayName != null) 'Имя: ${profile.displayName}',
      if (contact?.id != null) 'ID: ${contact!.id}',
      if (contact?.country != null) 'Страна: ${contact!.country}',
      'Имен: ${contact?.names.length ?? 0}',
      'Опций профиля: ${profile.profileOptions.length}',
    ].join('\n');
  }

  String _safeError(Object error) {
    final text = error.toString();
    // Не показываем потенциально чувствительные payload и значения токенов.
    return text.length > 500 ? text.substring(0, 500) : text;
  }


  Future<void> _runApiCheck(
    String label,
    Future<String> Function() operation,
  ) async {
    if (_apiBusy || _busy || !_loginComplete || _connection?.isConnected != true) {
      return;
    }
    setState(() => _apiBusy = true);
    final stopwatch = Stopwatch()..start();
    _log('API Probe: $label. Запрос выполняется...');
    try {
      final result = await operation();
      stopwatch.stop();
      _log('API Probe: $label завершён за ${stopwatch.elapsedMilliseconds} мс. $result');
    } catch (error) {
      stopwatch.stop();
      _log('API Probe: $label завершился ошибкой за ${stopwatch.elapsedMilliseconds} мс: ${_safeError(error)}');
    } finally {
      if (mounted) setState(() => _apiBusy = false);
    }
  }

  MaxReadOnlyApi _createReadOnlyApi() {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      throw StateError('Нет активного соединения с MAX.');
    }
    return MaxReadOnlyApi(connection: connection);
  }

  Future<String> _probeProfileSnapshot() async {
    final session = _authenticatedSession;
    if (session == null) throw StateError('Нет данных LOGIN.');
    final profile = _createReadOnlyApi().profileFromLogin(session.login);
    if (profile == null) return 'Профиль отсутствует в LOGIN/LOGIN2.';
    return 'Профиль получен из LOGIN/LOGIN2; имя задано: ${profile.displayName != null}; contact ID задан: ${profile.contact?.id != null}.';
  }

  Future<String> _probeContactsSnapshot() async {
    final session = _authenticatedSession;
    if (session == null) throw StateError('Нет данных LOGIN.');
    final contacts = _createReadOnlyApi().contactsFromLogin(session.login);
    if (mounted) setState(() => _lastApiContacts = contacts);
    return 'Контактов в snapshot LOGIN/LOGIN2: ${contacts.length}.';
  }

  Future<String> _probeContactInfo() async {
    final id = int.tryParse(_apiContactIdController.text.trim());
    if (id == null || id <= 0) {
      throw const FormatException('Укажи положительный числовой Contact ID.');
    }
    final contacts = await _createReadOnlyApi().getContactInfo(<int>[id]);
    return 'CONTACT_INFO вернул записей: ${contacts.length}.';
  }

  Future<String> _probeChatsList() async {
    final chats = await _createReadOnlyApi().getChats();
    if (mounted) setState(() => _lastApiChats = chats);
    return 'CHATS_LIST вернул чатов: ${chats.length}. Укажи Chat ID для следующих проверок.';
  }

  Future<String> _probeChatInfo() async {
    final id = int.tryParse(_apiChatIdController.text.trim());
    if (id == null || id <= 0) {
      throw const FormatException('Укажи положительный числовой Chat ID.');
    }
    final chats = await _createReadOnlyApi().getChatInfo(<int>[id]);
    return 'CHAT_INFO вернул чатов: ${chats.length}.';
  }

  Future<String> _probeChatMembers() async {
    final id = int.tryParse(_apiChatIdController.text.trim());
    if (id == null || id <= 0) {
      throw const FormatException('Укажи положительный числовой Chat ID.');
    }
    final result = await _createReadOnlyApi().getChatMembers(chatId: id);
    return 'CHAT_MEMBERS вернул участников: ${result.members.length}; следующий marker: ${result.marker}.';
  }

  Future<String> _probeChatHistory() async {
    final id = int.tryParse(_apiChatIdController.text.trim());
    if (id == null || id <= 0) {
      throw const FormatException('Укажи положительный числовой Chat ID.');
    }
    final messages = await _createReadOnlyApi().getChatHistory(
      chatId: id,
      backward: 20,
    );
    return 'CHAT_HISTORY вернул сообщений: ${messages.length}. Текст сообщений не выводится в журнал.';
  }

  Future<void> _stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _closeConnection();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _connected = false;
      _authenticated = false;
      _loginComplete = false;
      _qrRequest = null;
      _authenticatedSession = null;
      _status = 'Остановлено';
    });
    _log('Соединение закрыто пользователем.');
  }

  Future<void> _logout() async {
    if (_busy && !_loginComplete) return;

    setState(() {
      _busy = true;
      _status = 'Выход из аккаунта';
      _error = null;
    });

    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      await _closeConnection();
      await WindowsDpapiStorage.delete(key: _tokenStorageKey);
      await WindowsDpapiStorage.delete(key: _authMethodStorageKey);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _connected = false;
        _authenticated = false;
        _loginComplete = false;
        _qrRequest = null;
        _authenticatedSession = null;
        _profileSummary = null;
        _status = 'Выполнен выход';
      });
      _log('Выход выполнен. Сохранённый токен удалён; идентификатор устройства сохранён.');
    } catch (error) {      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _safeError(error);
        _status = 'Ошибка выхода';
      });
      _log('Не удалось завершить выход: ${_safeError(error)}');
    }
  }

  Future<void> _closeConnection() async {
    final connection = _connection;
    _connection = null;
    _sessionManager = null;
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {
        // Ошибка закрытия не должна перекрывать исходную ошибку проверки.
      }
    }
  }

  Widget _certificateStatusRow(String label, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(status, textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qrRequest;
    final apiContactIds = _lastApiContacts
        .map((contact) => contact['id'])
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final apiChatIds = _lastApiChats
        .map((chat) => chat['id'])
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAX Auth Probe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Chip(
                avatar: Icon(
                  _loginComplete
                      ? Icons.verified
                      : _connected
                          ? Icons.link
                          : Icons.link_off,
                  size: 18,
                ),
                label: Text(_status),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                            Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Подключение WebSocket + QR',
                                          style: Theme.of(context).textTheme.titleMedium),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _uriController,
                                        enabled: !_busy,
                                        decoration: const InputDecoration(
                                          labelText: 'WebSocket URL',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _timezoneController,
                                        enabled: !_busy,
                                        decoration: const InputDecoration(
                                          labelText: 'Часовой пояс',
                                          hintText: 'Например, Europe/Helsinki',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _phoneController,
                                        enabled: !_busy,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(
                                          labelText: 'Номер телефона для SMS-входа',
                                          hintText: '+358...',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Диагностика TLS и сертификатов Windows',
                                              style: Theme.of(context).textTheme.titleSmall),
                                          const SizedBox(height: 8),
                                          _certificateStatusRow('Russian Trusted Root CA', _rootCertificateStatus),
                                          _certificateStatusRow('Russian Trusted Sub CA 2024', _intermediateCertificateStatus),
                                          _certificateStatusRow('TLS стандартный контекст', _windowsTlsStatus),
                                          _certificateStatusRow('TLS MaxAI / pinned Root', _maxAiTlsStatus),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: _busy || _certificateBusy ? null : () => _runCertificateCheck(WindowsCertificateKind.root),
                                                icon: const Icon(Icons.search),
                                                label: const Text('Проверить Root'),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: _busy || _certificateBusy ? null : () => _runCertificateCheck(WindowsCertificateKind.intermediate),
                                                icon: const Icon(Icons.search),
                                                label: const Text('Проверить Sub CA'),
                                              ),
                                              FilledButton.tonalIcon(
                                                onPressed: _busy || _certificateBusy ? null : () => _installCertificate(WindowsCertificateKind.root),
                                                icon: const Icon(Icons.download),
                                                label: const Text('Установить Root'),
                                              ),
                                              FilledButton.tonalIcon(
                                                onPressed: _busy || _certificateBusy ? null : () => _installCertificate(WindowsCertificateKind.intermediate),
                                                icon: const Icon(Icons.download),
                                                label: const Text('Установить Sub CA'),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: _busy || _certificateBusy
                                                    ? null
                                                    : () => _checkApiTls(usePinnedRoot: false),
                                                icon: const Icon(Icons.shield_outlined),
                                                label: const Text('TLS: Default'),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: _busy || _certificateBusy
                                                    ? null
                                                    : () => _checkApiTls(usePinnedRoot: true),
                                                icon: _certificateBusy
                                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                                    : const Icon(Icons.verified_user_outlined),
                                                label: const Text('TLS: MaxAI'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: _busy || _apiBusy ? null : _connectAndStartQr,
                                            icon: const Icon(Icons.qr_code),
                                            label: const Text('Подключиться / восстановить авторизацию'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _busy || _apiBusy || _loginComplete
                                                ? null
                                                : _connectAndStartSms,
                                            icon: const Icon(Icons.sms_outlined),
                                            label: const Text('Войти по SMS'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _connected || _busy ? _stop : null,
                                            icon: const Icon(Icons.stop),
                                            label: const Text('Остановить'),
                                          ),
                                          if (_loginComplete)
                                            OutlinedButton.icon(
                                              onPressed: _busy || _apiBusy ? null : _logout,
                                              icon: const Icon(Icons.logout),
                                              label: const Text('Выйти из аккаунта'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              if (_loginComplete) ...[
                                const SizedBox(height: 12),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Read-only API Probe',
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Безопасные проверки чтения. Профиль и список контактов берутся из LOGIN; остальные операции отправляют отдельные запросы.',
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _apiContactIdController,
                                          enabled: !_apiBusy,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'Contact ID',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        if (apiContactIds.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<int>(
                                            value: apiContactIds.contains(int.tryParse(_apiContactIdController.text))
                                                ? int.tryParse(_apiContactIdController.text)
                                                : null,
                                            decoration: const InputDecoration(
                                              labelText: 'Контакт из LOGIN snapshot',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: apiContactIds.map((id) => DropdownMenuItem<int>(
                                              value: id,
                                              child: Text('Contact $id'),
                                            )).toList(),
                                            onChanged: _apiBusy ? null : (id) {
                                              if (id != null) setState(() => _apiContactIdController.text = id.toString());
                                            },
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _apiChatIdController,
                                          enabled: !_apiBusy,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'Chat ID',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        if (apiChatIds.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<int>(
                                            value: apiChatIds.contains(int.tryParse(_apiChatIdController.text))
                                                ? int.tryParse(_apiChatIdController.text)
                                                : null,
                                            decoration: const InputDecoration(
                                              labelText: 'Чат из последнего списка',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: apiChatIds.map((id) => DropdownMenuItem<int>(
                                              value: id,
                                              child: Text('Chat $id'),
                                            )).toList(),
                                            onChanged: _apiBusy ? null : (id) {
                                              if (id != null) setState(() => _apiChatIdController.text = id.toString());
                                            },
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('PROFILE snapshot', _probeProfileSnapshot),
                                              child: const Text('Профиль из LOGIN'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('CONTACTS snapshot', _probeContactsSnapshot),
                                              child: const Text('Контакты из LOGIN'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('CONTACT_INFO (32)', _probeContactInfo),
                                              child: const Text('Информация о контакте'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('CHATS_LIST (53)', _probeChatsList),
                                              child: const Text('Список чатов'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('CHAT_INFO (48)', _probeChatInfo),
                                              child: const Text('Информация о чате'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('CHAT_MEMBERS (59)', _probeChatMembers),
                                              child: const Text('Участники чата'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _apiBusy ? null : () => _runApiCheck('CHAT_HISTORY (49)', _probeChatHistory),
                                              child: const Text('История сообщений'),
                                            ),
                                          ],
                                        ),
                                        if (_apiBusy) ...[
                                          const SizedBox(height: 10),
                                          const LinearProgressIndicator(),
                                        ],
                                        if (_lastApiChats.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'Последний список чатов: ${_lastApiChats.length}. ID и названия не выводятся автоматически.',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (qr != null) ...[
                                const SizedBox(height: 12),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        QrImageView(
                                          data: qr.qrLink,
                                          size: 210,
                                          backgroundColor: Colors.white,
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Отсканируй QR в приложении MAX',
                                                  style: Theme.of(context).textTheme.titleMedium),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Оставь это окно открытым. Приложение автоматически проверяет подтверждение QR и после него выполняет LOGIN.',
                                              ),
                                              const SizedBox(height: 8),
                                              SelectableText(
                                                'Действителен до: ${qr.expiresAtDateTime.toLocal()}',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 8),
                                Material(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(_error!),
                                  ),
                                ),
                              ],
                              if (_profileSummary != null) ...[
                                const SizedBox(height: 8),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Результат', style: Theme.of(context).textTheme.titleMedium),
                                        const SizedBox(height: 6),
                                        Text(_profileSummary!),
                                        if (_authenticatedSession != null) ...[
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Токен авторизации сохранён в зашифрованном хранилище Windows DPAPI '
                                            'и будет использован при следующем запуске.',
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('Журнал проверки',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            TextButton(
                              onPressed: _logs.isEmpty
                                  ? null
                                  : () => setState(_logs.clear),
                              child: const Text('Очистить'),
                            ),
                          ],
                        ),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _logs.isEmpty
                                ? const Center(child: Text('Здесь появятся этапы проверки.'))
                                : ListView.builder(
                                    reverse: true,
                                    padding: const EdgeInsets.all(12),
                                    itemCount: _logs.length,
                                    itemBuilder: (context, index) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: SelectableText(
                                        _logs[index],
                                        style: const TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
          ],
        ),
      ),
    );
  }
}