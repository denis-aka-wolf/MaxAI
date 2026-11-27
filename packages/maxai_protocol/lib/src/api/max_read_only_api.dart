import '../auth/login_models.dart';
import '../auth/profile_models.dart';
import '../connection/decoded_protocol_frame.dart';
import '../connection/protocol_command.dart';
import '../connection/protocol_connection.dart';

/// Read-only API methods verified against the inspected PyMax payload builders.
final class MaxReadOnlyApi {
  MaxReadOnlyApi({
    required this.connection,
    this.requestTimeout = const Duration(seconds: 30),
  }) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive.',
      );
    }
  }

  static const int contactInfoOpcode = 32;
  static const int chatInfoOpcode = 48;
  static const int chatHistoryOpcode = 49;
  static const int chatsListOpcode = 53;
  static const int chatMembersOpcode = 59;
  static const int messagesGetOpcode = 71;

  final ProtocolConnection connection;
  final Duration requestTimeout;

  /// Profile data is delivered by LOGIN/LOGIN2, not by PROFILE opcode 16.
  /// Opcode 16 changes profile data and must not be used as a read operation.
  MaxUserProfile? profileFromLogin(LoginBootstrapResult login) {
    final payload = login.profile;
    return payload == null ? null : MaxUserProfile.fromPayload(payload);
  }

  /// The contact snapshot is supplied by LOGIN/LOGIN2.
  /// CONTACT_INFO (32) is a separate lookup by contactIds.
  List<Map<String, Object?>> contactsFromLogin(LoginBootstrapResult login) =>
      _mapList(login.contacts, 'LOGIN contacts');

  Future<List<Map<String, Object?>>> getContactInfo(
    List<int> contactIds,
  ) async {
    _requireIds(contactIds, 'contactIds');
    final payload = await _invoke(
      opcode: contactInfoOpcode,
      payload: <String, Object?>{'contactIds': contactIds},
    );
    return _mapList(
        _map(payload, 'CONTACT_INFO')['contacts'] ?? const [], 'contacts');
  }

  Future<List<Map<String, Object?>>> getChats({int? marker}) async {
    final payload = await _invoke(
      opcode: chatsListOpcode,
      payload: <String, Object?>{
        'marker': marker ?? DateTime.now().millisecondsSinceEpoch,
      },
    );
    return _mapList(_map(payload, 'CHATS_LIST')['chats'] ?? const [], 'chats');
  }

  Future<List<Map<String, Object?>>> getChatInfo(List<int> chatIds) async {
    _requireIds(chatIds, 'chatIds');
    final payload = await _invoke(
      opcode: chatInfoOpcode,
      payload: <String, Object?>{'chatIds': chatIds},
    );
    return _mapList(_map(payload, 'CHAT_INFO')['chats'] ?? const [], 'chats');
  }

  /// Fetches specific messages without changing chat state.
  Future<List<Map<String, Object?>>> getMessages({
    required int chatId,
    required List<int> messageIds,
  }) async {
    if (chatId <= 0) {
      throw ArgumentError.value(chatId, 'chatId', 'Must be positive.');
    }
    _requireIds(messageIds, 'messageIds');
    final payload = await _invoke(
      opcode: messagesGetOpcode,
      payload: <String, Object?>{
        'chatId': chatId,
        'messageIds': messageIds,
      },
    );
    return _mapList(
        _map(payload, 'MSG_GET')['messages'] ?? const [], 'messages');
  }

  Future<MaxChatMembersResult> getChatMembers({
    required int chatId,
    int marker = 0,
    int count = 50,
  }) async {
    if (chatId <= 0) {
      throw ArgumentError.value(chatId, 'chatId', 'Must be positive.');
    }
    if (marker < 0 || count < 1) {
      throw ArgumentError('marker must be >= 0 and count must be positive.');
    }
    final payload = await _invoke(
      opcode: chatMembersOpcode,
      payload: <String, Object?>{
        'type': 'MEMBER',
        'chatId': chatId,
        'marker': marker,
        'count': count,
      },
    );
    final map = _map(payload, 'CHAT_MEMBERS');
    final rawMarker = map['marker'];
    if (rawMarker != null && rawMarker is! int) {
      throw const FormatException('CHAT_MEMBERS marker must be an integer.');
    }
    return MaxChatMembersResult(
      members: _mapList(map['members'] ?? const [], 'members'),
      marker: rawMarker as int? ?? 0,
    );
  }

  Future<List<Map<String, Object?>>> getChatHistory({
    required int chatId,
    int forward = 0,
    int backward = 40,
    int backwardTime = 0,
    int forwardTime = 0,
    int? from,
    bool getChat = false,
    bool getMessages = true,
    bool interactive = false,
  }) async {
    if (chatId <= 0) {
      throw ArgumentError.value(chatId, 'chatId', 'Must be positive.');
    }
    if (forward < 0 || backward < 0) {
      throw ArgumentError('forward and backward must be >= 0.');
    }
    final payload = await _invoke(
      opcode: chatHistoryOpcode,
      payload: <String, Object?>{
        'chatId': chatId,
        'forward': forward,
        'backward': backward,
        'backwardTime': backwardTime,
        'forwardTime': forwardTime,
        'getChat': getChat,
        'from': from ?? DateTime.now().millisecondsSinceEpoch,
        'itemType': 'REGULAR',
        'getMessages': getMessages,
        'interactive': interactive,
      },
    );
    return _mapList(
        _map(payload, 'CHAT_HISTORY')['messages'] ?? const [], 'messages');
  }

  Future<Object?> _invoke({
    required int opcode,
    required Map<String, Object?> payload,
  }) async {
    final response = await connection.request(
      opcode: opcode,
      payload: payload,
      timeout: requestTimeout,
    );
    _validateResponse(response, opcode);
    return response.payload;
  }

  void _validateResponse(DecodedProtocolFrame response, int opcode) {
    if (response.commandType == ProtocolCommand.error) {
      throw MaxReadOnlyApiException(
        'MAX returned an ERROR response for opcode $opcode.',
        opcode: opcode,
      );
    }
    if (response.commandType != ProtocolCommand.response ||
        response.opcode != opcode) {
      throw MaxReadOnlyApiException(
        'Unexpected response for opcode $opcode.',
        opcode: opcode,
      );
    }
  }

  static void _requireIds(List<int> ids, String field) {
    if (ids.isEmpty || ids.any((id) => id <= 0)) {
      throw ArgumentError.value(ids, field, 'Must contain positive IDs.');
    }
  }

  static Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('$field response must be a map.');
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

  static List<Map<String, Object?>> _mapList(Object? value, String field) {
    if (value is! List) {
      throw FormatException('$field must be a list.');
    }
    return List<Map<String, Object?>>.unmodifiable(
      value.map(
          (item) => Map<String, Object?>.unmodifiable(_map(item, '$field[]'))),
    );
  }
}

final class MaxChatMembersResult {
  const MaxChatMembersResult({
    required this.members,
    required this.marker,
  });

  final List<Map<String, Object?>> members;
  final int marker;
}

final class MaxReadOnlyApiException implements Exception {
  const MaxReadOnlyApiException(this.message, {required this.opcode});

  final String message;
  final int opcode;

  @override
  String toString() =>
      'MaxReadOnlyApiException(opcode: $opcode, message: $message)';
}
