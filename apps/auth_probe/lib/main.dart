import 'dart:async';
import 'dart:math';

// Flutter SDK marks the Material library deprecated in newer prerelease builds.
// Keep the stable Flutter Material API until its replacement is available in stable.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/windows_dpapi_storage.dart';

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

class AuthProbeScreen extends StatefulWidget {
  const AuthProbeScreen({super.key});

  @override
  State<AuthProbeScreen> createState() => _AuthProbeScreenState();
}

class _AuthProbeScreenState extends State<AuthProbeScreen> {
  static final Uri _defaultUri = Uri.parse('wss://api.oneme.ru/websocket');
  static const String _tokenStorageKey = 'maxai.auth.token';
  static const String _deviceIdStorageKey = 'maxai.auth.device_id';

  final _uriController = TextEditingController(text: _defaultUri.toString());
  final _timezoneController = TextEditingController(text: 'Europe/Helsinki');

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

  @override
  void initState() {
    super.initState();
    _restoreSessionOnStartup();
  }

  Future<void> _restoreSessionOnStartup() async {
    try {
      final token = await WindowsDpapiStorage.read(key: _tokenStorageKey);
      if (!mounted || token == null || token.isEmpty) return;
      _log('Найдена сохранённая авторизация. Пробуем восстановить сессию.');
      await _connectAndStartQr();
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

  Future<void> _connectAndStartQr() async {
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
      final uri = Uri.parse(_uriController.text.trim());
      if (uri.scheme != 'wss' && uri.scheme != 'ws') {
        throw const FormatException('Адрес должен начинаться с ws:// или wss://.');
      }

      final deviceId = await _loadOrCreateDeviceId();
      final userAgent = _createWebUserAgent();
      final frameCodec = const TcpFrameCodec(
        payloadCodec: MessagePackPayloadCodec(),
      );
      final connection = ProtocolConnection(
        transport: WebSocketTransport(
          uri: uri,
          headers: <String, dynamic>{
            'Origin': 'https://web.max.ru',
            if (userAgent.headerUserAgent != null)
              'User-Agent': userAgent.headerUserAgent!,
          },
        ),
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

      _log('Открываем WebSocket: ${uri.host}');
      await connection.connect();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = 'WebSocket подключён';
      });
      _log('WebSocket соединение установлено.');

      final session = SessionManager(connection: connection);
      _sessionManager = session;
      _log('Отправляем SESSION_INIT (opcode 6).');
      final handshake = await session.startWeb(
        userAgent: userAgent,
        deviceId: deviceId,
      );
      _log('SESSION_INIT успешно завершён. callsSeed: ${handshake.callsSeed == null ? "не получен" : "получен"}.');

      final auth = AuthManager(
        connection: connection,
        sessionManager: session,
        deviceType: DeviceType.web,
        deviceId: deviceId,
        onLog: _log,
      );

      final savedToken = await WindowsDpapiStorage.read(key: _tokenStorageKey);
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
              _busy = false;
            });
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

  Future<String?> _requestTwoFactorPassword(String? hint) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
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
                controller: controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Пароль 2FA',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  final password = value.trim();
                  if (password.isNotEmpty) {
                    Navigator.of(dialogContext).pop(password);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final password = controller.text.trim();
                if (password.isNotEmpty) {
                  Navigator.of(dialogContext).pop(password);
                }
              },
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
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
    _log('Токен авторизации и постоянный идентификатор устройства сохранены в зашифрованном хранилище Windows DPAPI.');
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

  @override
  Widget build(BuildContext context) {
    final qr = _qrRequest;
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
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _connectAndStartQr,
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Подключиться / восстановить авторизацию'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _connected || _busy ? _stop : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Остановить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
