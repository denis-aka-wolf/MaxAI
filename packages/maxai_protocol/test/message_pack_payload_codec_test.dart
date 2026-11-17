import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  const codec = MessagePackPayloadCodec();

  test('roundtrips nested MAX-like payload', () {
    final payload = <String, Object?>{
      'chatId': 123456,
      'text': 'Привет, MAX!',
      'flags': <String, Object?>{'interactive': true, 'drafts': false},
      'items': <Object?>[1, 'two', null],
    };
    final decoded = codec.decode(codec.encode(payload));
    expect(decoded, equals(payload));
  });
}
