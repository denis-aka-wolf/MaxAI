/// Выдаёт 16-битные sequence numbers; первый номер равен 0.
final class SequenceManager {
  SequenceManager({int initialValue = -1}) : _current = initialValue {
    if (initialValue < -1 || initialValue > 0xFFFF) {
      throw RangeError.value(initialValue, 'initialValue');
    }
  }
  int _current;
  int next() => _current = (_current + 1) & 0xFFFF;
  int get current => _current;
}
