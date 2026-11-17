import 'dart:typed_data';

/// Логический frame: ver:uint8, cmd:uint8, seq:uint16 BE,
/// opcode:uint16 BE, flags:uint8 + payload length:uint24 BE.
final class ProtocolFrame {
  const ProtocolFrame({
    required this.version,
    required this.command,
    required this.sequence,
    required this.opcode,
    required this.payload,
    this.flags = 0,
  });
  final int version;
  final int command;
  final int sequence;
  final int opcode;
  final int flags;
  final Uint8List payload;

  static const int maxPayloadLength = 0xFFFFFF;

  void validate() {
    _check('version', version, 0xFF);
    _check('command', command, 0xFF);
    _check('sequence', sequence, 0xFFFF);
    _check('opcode', opcode, 0xFFFF);
    _check('flags', flags, 0xFF);
    if (payload.length > maxPayloadLength) {
      throw RangeError('Payload exceeds limit of $maxPayloadLength bytes.');
    }
  }

  static void _check(String name, int value, int max) {
    if (value < 0 || value > max) {
      throw RangeError('$name must be in range 0..$max.');
    }
  }
}
