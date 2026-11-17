import 'dart:typed_data';
abstract interface class PayloadCodec {
  Uint8List encode(Object? payload);
  Object? decode(Uint8List bytes);
}
