import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('sequence starts at zero and wraps at uint16 boundary', () {
    final manager = SequenceManager();
    expect(manager.next(), 0);
    expect(manager.next(), 1);
    expect(SequenceManager(initialValue: 0xFFFF).next(), 0);
  });

  test('pending request resolves by sequence', () async {
    final pending = PendingRequests<String>();
    final response = pending.register(42);
    expect(pending.resolve(42, 'ok'), isTrue);
    expect(await response, 'ok');
    expect(pending.length, 0);
  });

  test('duplicate pending sequence is rejected', () async {
    final pending = PendingRequests<String>();
    final first = pending.register(5);
    expect(() => pending.register(5), throwsStateError);
    pending.cancelAll();
    await expectLater(first, throwsStateError);
  });

  test('connection close fails all pending requests', () async {
    final pending = PendingRequests<String>();
    final first = pending.register(1);
    final second = pending.register(2);
    pending.cancelAll(StateError('closed'));
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(pending.length, 0);
  });
}
