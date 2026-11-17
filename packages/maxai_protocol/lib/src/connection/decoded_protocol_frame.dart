import '../frame/protocol_frame.dart';
import 'protocol_command.dart';

/// Frame вместе с декодированным MessagePack payload.
final class DecodedProtocolFrame {
  const DecodedProtocolFrame({
    required this.frame,
    required this.payload,
  });

  final ProtocolFrame frame;
  final Object? payload;

  int get version => frame.version;
  int get command => frame.command;
  int get sequence => frame.sequence;
  int get opcode => frame.opcode;
  int get flags => frame.flags;

  ProtocolCommand? get commandType => ProtocolCommand.fromValue(command);
}
