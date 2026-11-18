import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Зашифрованное хранилище небольших секретов с использованием Windows DPAPI.
///
/// По умолчанию DPAPI привязывает расшифровку к учётной записи Windows,
/// под которой данные были зашифрованы. Токен не записывается на диск
/// в открытом виде.
class WindowsDpapiStorage {
  WindowsDpapiStorage._();

  static const int _cryptProtectUiForbidden = 0x1;
  static const String _applicationEntropy = 'MaxAI.AuthProbe.Storage.v1';

  static final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(
    Pointer<_DataBlob>,
    Pointer<Utf16>,
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<_DataBlob>,
  ) _cryptProtectData = _crypt32.lookupFunction<
      Int32 Function(
        Pointer<_DataBlob>,
        Pointer<Utf16>,
        Pointer<_DataBlob>,
        Pointer<Void>,
        Pointer<Void>,
        Uint32,
        Pointer<_DataBlob>,
      ),
      int Function(
        Pointer<_DataBlob>,
        Pointer<Utf16>,
        Pointer<_DataBlob>,
        Pointer<Void>,
        Pointer<Void>,
        int,
        Pointer<_DataBlob>,
      )>('CryptProtectData');

  static final int Function(
    Pointer<_DataBlob>,
    Pointer<Pointer<Utf16>>,
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<_DataBlob>,
  ) _cryptUnprotectData = _crypt32.lookupFunction<
      Int32 Function(
        Pointer<_DataBlob>,
        Pointer<Pointer<Utf16>>,
        Pointer<_DataBlob>,
        Pointer<Void>,
        Pointer<Void>,
        Uint32,
        Pointer<_DataBlob>,
      ),
      int Function(
        Pointer<_DataBlob>,
        Pointer<Pointer<Utf16>>,
        Pointer<_DataBlob>,
        Pointer<Void>,
        Pointer<Void>,
        int,
        Pointer<_DataBlob>,
      )>('CryptUnprotectData');

  static final Pointer<Void> Function(Pointer<Void>) _localFree =
      _kernel32.lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)>('LocalFree');

  static Future<String?> read({required String key}) async {
    _ensureWindows();
    final file = _fileForKey(key);
    if (!await file.exists()) return null;

    final encrypted = await file.readAsBytes();
    if (encrypted.isEmpty) return null;

    return utf8.decode(_unprotect(Uint8List.fromList(encrypted)));
  }

  static Future<void> write({
    required String key,
    required String value,
  }) async {
    _ensureWindows();
    final encrypted = _protect(Uint8List.fromList(utf8.encode(value)));
    final file = _fileForKey(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encrypted, flush: true);
  }

  static Future<void> delete({required String key}) async {
    _ensureWindows();
    final file = _fileForKey(key);
    if (await file.exists()) await file.delete();
  }

  static File _fileForKey(String key) {
    const allowedKeys = <String>{
      'maxai.auth.token',
      'maxai.auth.device_id',
      'maxai.auth.mt_instance_id',
      'maxai.auth.method',
    };
    if (!allowedKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Неизвестный ключ хранилища.');
    }

    final basePath = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'];
    if (basePath == null || basePath.isEmpty) {
      throw StateError('Не удалось определить каталог профиля Windows.');
    }

    final fileName = key.replaceAll('.', '_');
    return File('$basePath\\MaxAI\\AuthProbe\\$fileName.dpapi');
  }

  static Uint8List _protect(Uint8List plainText) {
    final inputBytes = calloc<Uint8>(plainText.length);
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final entropyBytes = calloc<Uint8>(_applicationEntropy.length);
    final entropy = calloc<_DataBlob>();
    final description = 'MaxAI Auth Probe'.toNativeUtf16();

    try {
      inputBytes.asTypedList(plainText.length).setAll(0, plainText);
      entropyBytes
          .asTypedList(_applicationEntropy.length)
          .setAll(0, _applicationEntropy.codeUnits);
      input.ref
        ..cbData = plainText.length
        ..pbData = inputBytes;
      entropy.ref
        ..cbData = _applicationEntropy.length
        ..pbData = entropyBytes;

      final success = _cryptProtectData(
        input,
        description,
        entropy,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output,
      );
      if (success == 0) throw _windowsError('CryptProtectData');

      return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
    } finally {
      if (output.ref.pbData != nullptr) _localFree(output.ref.pbData.cast<Void>());
      calloc.free(description);
      calloc.free(entropy);
      calloc.free(entropyBytes);
      calloc.free(output);
      calloc.free(input);
      calloc.free(inputBytes);
    }
  }

  static Uint8List _unprotect(Uint8List encrypted) {
    final inputBytes = calloc<Uint8>(encrypted.length);
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final entropyBytes = calloc<Uint8>(_applicationEntropy.length);
    final entropy = calloc<_DataBlob>();
    final description = calloc<Pointer<Utf16>>();

    try {
      inputBytes.asTypedList(encrypted.length).setAll(0, encrypted);
      entropyBytes
          .asTypedList(_applicationEntropy.length)
          .setAll(0, _applicationEntropy.codeUnits);
      input.ref
        ..cbData = encrypted.length
        ..pbData = inputBytes;
      entropy.ref
        ..cbData = _applicationEntropy.length
        ..pbData = entropyBytes;

      final success = _cryptUnprotectData(
        input,
        description,
        entropy,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output,
      );
      if (success == 0) throw _windowsError('CryptUnprotectData');

      return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
    } finally {
      if (output.ref.pbData != nullptr) _localFree(output.ref.pbData.cast<Void>());
      if (description.value != nullptr) _localFree(description.value.cast<Void>());
      calloc.free(description);
      calloc.free(entropy);
      calloc.free(entropyBytes);
      calloc.free(output);
      calloc.free(input);
      calloc.free(inputBytes);
    }
  }

  static Object _windowsError(String operation) {
    final getLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
    return StateError('$operation завершился ошибкой Windows. Код: ${getLastError()}.');
  }

  static void _ensureWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsDpapiStorage доступен только в Windows.');
    }
  }
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}
