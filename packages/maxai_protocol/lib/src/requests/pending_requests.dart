import 'dart:async';

/// Реестр запросов, ожидающих ответ с соответствующим sequence number.
final class PendingRequests<T> {
  final Map<int, Completer<T>> _pending = {};
  final Map<int, Timer> _timers = {};

  Future<T> register(int sequence, {Duration? timeout}) {
    if (sequence < 0 || sequence > 0xFFFF) {
      throw RangeError.range(sequence, 0, 0xFFFF, 'sequence');
    }
    if (_pending.containsKey(sequence)) {
      throw StateError('Sequence $sequence is already pending.');
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }

    final completer = Completer<T>();
    _pending[sequence] = completer;

    if (timeout != null) {
      _timers[sequence] = Timer(timeout, () {
        final current = _pending.remove(sequence);
        _timers.remove(sequence);
        if (current != null && !current.isCompleted) {
          current.completeError(
            TimeoutException('Request $sequence timed out.', timeout),
          );
        }
      });
    }
    return completer.future;
  }

  bool resolve(int sequence, T value) {
    final completer = _pending.remove(sequence);
    if (completer == null || completer.isCompleted) return false;
    _timers.remove(sequence)?.cancel();
    completer.complete(value);
    return true;
  }

  bool fail(int sequence, Object error, [StackTrace? stackTrace]) {
    final completer = _pending.remove(sequence);
    if (completer == null || completer.isCompleted) return false;
    _timers.remove(sequence)?.cancel();
    completer.completeError(error, stackTrace);
    return true;
  }

  void cancelAll([Object? reason]) {
    final error = reason ?? StateError('Connection closed.');
    final entries = _pending.entries.toList(growable: false);
    _pending.clear();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();

    for (final entry in entries) {
      final completer = entry.value;
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  bool contains(int sequence) => _pending.containsKey(sequence);
  int get length => _pending.length;
}
