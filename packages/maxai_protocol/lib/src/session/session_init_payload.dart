import 'dart:math';

import 'device_type.dart';
import 'max_user_agent.dart';

/// Создаёт payload SESSION_INIT по структуре, используемой PyMax.
final class SessionInitPayload {
  SessionInitPayload._();

  static const String defaultWebHeaderUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

  static Map<String, Object?> mobile({
    required String mtInstanceId,
    required MaxUserAgent userAgent,
    required String deviceId,
    int? clientSessionId,
    Random? random,
  }) {
    if (userAgent.deviceType == DeviceType.web) {
      throw ArgumentError(
          'Mobile SESSION_INIT does not accept WEB device type.');
    }
    final sessionId = clientSessionId ?? ((random ?? Random()).nextInt(70) + 1);
    if (sessionId < 1 || sessionId > 70) {
      throw RangeError.range(sessionId, 1, 70, 'clientSessionId');
    }

    return <String, Object?>{
      'mt_instanceid': mtInstanceId,
      'userAgent': userAgent.toPayload(),
      'clientSessionId': sessionId,
      'deviceId': deviceId,
    };
  }

  static Map<String, Object?> web({
    required MaxUserAgent userAgent,
    required String deviceId,
  }) {
    if (userAgent.deviceType != DeviceType.web) {
      throw ArgumentError('Web SESSION_INIT requires WEB device type.');
    }
    final webUserAgent = userAgent.toWebPayload();
    webUserAgent.putIfAbsent(
      'headerUserAgent',
      () => defaultWebHeaderUserAgent,
    );

    return <String, Object?>{
      'userAgent': webUserAgent,
      'deviceId': deviceId,
    };
  }
}
