import 'device_type.dart';

/// User-Agent payload, используемый при SESSION_INIT.
///
/// Значения задаются приложением. Библиотека не подменяет их случайными
/// идентификаторами или неподтверждёнными fingerprint-параметрами.
final class MaxUserAgent {
  const MaxUserAgent({
    required this.deviceType,
    required this.appVersion,
    required this.osVersion,
    required this.timezone,
    required this.screen,
    required this.locale,
    required this.deviceName,
    required this.deviceLocale,
    this.pushDeviceType,
    this.arch,
    this.buildNumber,
    this.release,
    this.headerUserAgent,
  });

  final DeviceType deviceType;
  final String appVersion;
  final String osVersion;
  final String timezone;
  final String screen;
  final String? pushDeviceType;
  final String? arch;
  final String locale;
  final int? buildNumber;
  final String deviceName;
  final String deviceLocale;
  final int? release;
  final String? headerUserAgent;

  Map<String, Object?> toPayload() {
    final result = <String, Object?>{
      'deviceType': deviceType.value,
      'appVersion': appVersion,
      'osVersion': osVersion,
      'timezone': timezone,
      'screen': screen,
      'locale': locale,
      'deviceName': deviceName,
      'deviceLocale': deviceLocale,
    };

    _putIfNotNull(result, 'pushDeviceType', pushDeviceType);
    _putIfNotNull(result, 'arch', arch);
    _putIfNotNull(result, 'buildNumber', buildNumber);
    _putIfNotNull(result, 'release', release);
    _putIfNotNull(result, 'headerUserAgent', headerUserAgent);
    return result;
  }

  Map<String, Object?> toWebPayload() {
    const webFields = <String>{
      'deviceType',
      'locale',
      'deviceLocale',
      'osVersion',
      'deviceName',
      'headerUserAgent',
      'appVersion',
      'screen',
      'timezone',
    };
    final payload = toPayload()
      ..removeWhere((key, _) => !webFields.contains(key));
    return payload;
  }

  static void _putIfNotNull(
    Map<String, Object?> target,
    String key,
    Object? value,
  ) {
    if (value != null) target[key] = value;
  }
}
