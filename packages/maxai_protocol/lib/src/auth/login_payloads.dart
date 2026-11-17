import 'dart:typed_data';

import '../session/max_user_agent.dart';
import '../session/sync_state.dart';

/// Payload builders LOGIN / LOGIN2 по схемам PyMax 2.5.0.
abstract final class LoginPayloads {
  static const int defaultWebChatsCount = 40;

  static Map<String, Object?> mobile({
    required MaxUserAgent userAgent,
    required String token,
    required SyncState sync,
    required Uint8List chatCacheFingerprint,
    bool interactive = true,
  }) {
    _require(token, 'token');
    if (userAgent.deviceType.value == 'WEB') {
      throw ArgumentError('Mobile LOGIN requires a non-WEB user agent.');
    }
    return <String, Object?>{
      'userAgent': userAgent.toPayload(),
      'token': token,
      'chatCacheFingerprint': chatCacheFingerprint,
      'chatsSync': sync.chatsSync,
      'contactsSync': sync.contactsSync,
      'draftsSync': sync.draftsSync,
      'interactive': interactive,
      'presenceSync': sync.presenceSync,
      'exp': <String, Object?>{
        'chatsCountGroups': Uint8List.fromList(const <int>[0x0a, 0x32]),
      },
      'configHash': sync.configHash,
    };
  }

  static Map<String, Object?> web({
    required String token,
    required SyncState sync,
    bool interactive = true,
  }) {
    _require(token, 'token');
    // presenceSync не передаётся в конструктор from_sync_state, но модель
    // сериализует значение поля по умолчанию (-1) через model_dump().
    return <String, Object?>{
      'token': token,
      'chatsCount': defaultWebChatsCount,
      'interactive': interactive,
      'chatsSync': sync.chatsSync,
      'contactsSync': sync.contactsSync,
      'draftsSync': sync.draftsSync,
      'presenceSync': -1,
    };
  }

  static Map<String, Object?> login2({
    required SyncState sync,
    required bool profileEnabled,
    required bool contactEnabled,
  }) => <String, Object?>{
        'needProfile': profileEnabled,
        'contactsSync': contactEnabled ? sync.contactsSync : -1,
        'configHash': sync.configHash,
      };

  static void _require(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty.');
    }
  }
}
