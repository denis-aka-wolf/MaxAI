import 'dart:async';

/// Реестр запросов, ожидающих ответ с соответствующим sequence number.
final class PendingRequests<T> {
  final Map<int, Completer<T>> _pending = {};

  Future<T> register(int sequence, {Duration? timeout}) {
    if (sequence < 0 || sequence > 0xFFFF) {
      throw RangeError.range(sequence, 0, 0xFFFF, 'sequence');
    }
    if (_pending.containsKey(sequence)) {
      throw StateError('Sequence $sequence is already pending.');
    }
    final completer = Completer<T>();
    _pending[sequence] = completer;
    if (timeout == null) return completer.future;
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(sequence);
      throw TimeoutException('Request $sequence timed out.', timeout);
    });
  }

  bool resolve(int sequence, T value) {
    final completer = _pending.remove(sequence);
    if (completer == null || completer.isCompleted) return false;
    completer.complete(value);
    return true;
  }

  bool fail(int sequence, Object error, [StackTrace? stackTrace]) {
    final completer = _pending.remove(sequence);
    if (completer == null || completer.isCompleted) return false;
    completer.completeError(error, stackTrace);
    return true;
  }

  void cancelAll([Object? reason]) {
    final error = reason ?? StateError('Connection closed.');
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in entries) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  bool contains(int sequence) => _pending.containsKey(sequence);
  int get length => _pending.length;
}
