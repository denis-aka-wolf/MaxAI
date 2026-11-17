/// Значения command из enum Command в исследованном PyMax.
enum ProtocolCommand {
  request(0),
  response(1),
  event(2),
  error(3);

  const ProtocolCommand(this.value);
  final int value;

  static ProtocolCommand? fromValue(int value) {
    for (final command in values) {
      if (command.value == value) return command;
    }
    return null;
  }
}
