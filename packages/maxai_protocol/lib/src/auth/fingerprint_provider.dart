import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Контракт генерации fingerprint, необходимого для mobile AUTH_REQUEST / LOGIN.
abstract interface class FingerprintProvider {
  Uint8List generate({
    required String deviceId,
    required int callsSeed,
    required String architecture,
  });
}

/// Fingerprint-конфигурация конкретной сборки Android MAX.
///
/// Хеши должны соответствовать одной и той же версии APK. Смешивать значения
/// разных версий нельзя. Конфигурация не содержит секретов пользователя.
final class ApkFingerprintConfig {
  const ApkFingerprintConfig({
    required this.certificateMetaSha256,
    required this.dexMetaSha256,
    required this.soMetaSha256,
    required this.sourceVersion,
  });

  final String certificateMetaSha256;
  final String dexMetaSha256;
  final Map<String, String> soMetaSha256;
  final String sourceVersion;

  String hashForArchitecture(String architecture) {
    final value = soMetaSha256[architecture];
    if (value == null) {
      throw UnsupportedError(
        'No APK fingerprint hash for architecture "$architecture".',
      );
    }
    return value;
  }
}

/// Реализация алгоритма PyMax FingerprintGenerator.
///
/// Формула: SHA256(certHash || int64be(callsSeed) || deviceId) +
/// SHA256(dexHash || int64be(callsSeed) || deviceId) +
/// SHA256(soHash[arch] || int64be(callsSeed) || deviceId).
final class Sha256FingerprintProvider implements FingerprintProvider {
  Sha256FingerprintProvider(this.config);

  final ApkFingerprintConfig config;

  @override
  Uint8List generate({
    required String deviceId,
    required int callsSeed,
    required String architecture,
  }) {
    if (deviceId.isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty.');
    }
    if (callsSeed > 0x7fffffffffffffff) {
      throw RangeError.range(
        callsSeed,
        0,
        0x7fffffffffffffff,
        'callsSeed',
      );
    }

    final seed = ByteData(8)..setInt64(0, callsSeed, Endian.big);
    final suffix = <int>[
      ...seed.buffer.asUint8List(),
      ...utf8.encode(deviceId),
    ];

    final certificate = _decodeHash(config.certificateMetaSha256);
    final dex = _decodeHash(config.dexMetaSha256);
    final native = _decodeHash(config.hashForArchitecture(architecture));

    final result = <int>[
      ..._digest(certificate, suffix),
      ..._digest(dex, suffix),
      ..._digest(native, suffix),
    ];
    return Uint8List.fromList(result);
  }

  static List<int> _digest(List<int> prefix, List<int> suffix) =>
      sha256.convert(<int>[...prefix, ...suffix]).bytes;

  static List<int> _decodeHash(String value) {
    if (value.length != 64 || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw FormatException('APK fingerprint hash must be 64 hex characters.');
    }
    final result = <int>[];
    for (var i = 0; i < value.length; i += 2) {
      result.add(int.parse(value.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
