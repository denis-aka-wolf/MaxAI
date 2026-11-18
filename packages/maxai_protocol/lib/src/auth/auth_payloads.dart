import 'dart:typed_data';

/// Payloads авторизационных opcode, приведённые к wire-именам PyMax.
abstract final class AuthPayloads {
  static Map<String, Object?> requestSmsCode({
    required String phone,
    Uint8List? mode,
  }) {
    if (phone.trim().isEmpty) {
      throw ArgumentError.value(phone, 'phone', 'Phone must not be empty.');
    }
    return <String, Object?>{
      'phone': phone,
      'type': 'START_AUTH',
      // PyMax сериализует payload через exclude_none=True:
      // для WEB-клиента mode отсутствует, а не передаётся как null.
      if (mode != null) 'mode': mode,
    };
  }

  static Map<String, Object?> submitSmsCode({
    required String token,
    required String code,
  }) {
    _require(token, 'token');
    _require(code, 'code');
    return <String, Object?>{
      'token': token,
      'verifyCode': code,
      'authTokenType': 'CHECK_CODE',
    };
  }

  static Map<String, Object?> checkPassword({
    required String trackId,
    required String password,
  }) {
    _require(trackId, 'trackId');
    _require(password, 'password');
    return <String, Object?>{
      'trackId': trackId,
      'password': password,
    };
  }

  static Map<String, Object?> checkQr({required String trackId}) {
    _require(trackId, 'trackId');
    return <String, Object?>{'trackId': trackId};
  }

  static Map<String, Object?> confirmQr({required String trackId}) {
    _require(trackId, 'trackId');
    return <String, Object?>{'trackId': trackId};
  }

  static Map<String, Object?> confirmRegistration({
    required String firstName,
    String? lastName,
    required String token,
  }) {
    _require(firstName, 'firstName');
    _require(token, 'token');
    return <String, Object?>{
      'firstName': firstName,
      'lastName': lastName,
      'token': token,
      'tokenType': 'REGISTER',
    };
  }

  static void _require(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty.');
    }
  }
}
