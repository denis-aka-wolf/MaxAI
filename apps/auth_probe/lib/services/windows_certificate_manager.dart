import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Verifies and provisions the Russian Trusted Root CA required by api2.oneme.ru.
///
/// The root is added to MaxAI's dedicated TLS context regardless of whether the
/// user chooses to modify the Windows trust store. Installing into Windows is
/// optional and is always preceded by an explicit in-app confirmation.
final class WindowsCertificateManager {
  static const String rootCertificateUrl =
      'https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt';
  static const String rootThumbprint =
      '8FF915CCAB7BC16F8C5C8099D53E0E115B3AEC2F';
  static const String rootSubject = 'Russian Trusted Root CA';
  static final DateTime _notBefore = DateTime.utc(2022, 3, 2);
  static final DateTime _notAfter = DateTime.utc(2032, 2, 28, 0, 4, 15);

  Future<WindowsCertificateSetupResult> prepare({
    required Future<bool> Function() confirmInstall,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Автоматическая настройка сертификатов доступна только в Windows.',
      );
    }

    final pemBytes = await _loadVerifiedRootCertificate();
    final alreadyInstalled = await _isRootInstalled();
    var installed = alreadyInstalled;

    if (!alreadyInstalled && await confirmInstall()) {
      await _installRootCertificate();
      installed = await _isRootInstalled();
      if (!installed) {
        throw StateError(
          'Windows не подтвердила установку Russian Trusted Root CA.',
        );
      }
    }

    // Windows and Dart may use different trust sources depending on the
    // runtime configuration. Add the pinned root directly to this connection
    // context so MaxAI does not depend on a preconfigured PC.
    final context = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(pemBytes);

    return WindowsCertificateSetupResult(
      securityContext: context,
      alreadyInstalled: alreadyInstalled,
      installedInWindowsStore: installed,
      thumbprint: rootThumbprint,
    );
  }

  Future<List<int>> _loadVerifiedRootCertificate() async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('Windows LOCALAPPDATA environment variable is missing.');
    }

    final directory = Directory(
      '$localAppData${Platform.pathSeparator}MaxAI'
      '${Platform.pathSeparator}AuthProbe'
      '${Platform.pathSeparator}Certificates',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}russian_trusted_root_ca.pem',
    );

    List<int> bytes;
    if (await file.exists()) {
      bytes = await file.readAsBytes();
      if (!_isExpectedCertificate(bytes)) {
        await file.delete();
        bytes = await _downloadRootCertificate(file);
      }
    } else {
      bytes = await _downloadRootCertificate(file);
    }

    if (!_isExpectedCertificate(bytes)) {
      throw StateError(
        'Отпечаток скачанного Russian Trusted Root CA не совпадает с закреплённым.',
      );
    }

    final now = DateTime.now().toUtc();
    if (now.isBefore(_notBefore) || now.isAfter(_notAfter)) {
      throw StateError(
        'Russian Trusted Root CA находится вне известного срока действия. '
        'Требуется обновление закреплённых параметров сертификата MaxAI.',
      );
    }
    return bytes;
  }

  Future<List<int>> _downloadRootCertificate(File destination) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(rootCertificateUrl));
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Официальный сервер сертификатов вернул HTTP ${response.statusCode}.',
          uri: Uri.parse(rootCertificateUrl),
        );
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      if (!_isExpectedCertificate(bytes)) {
        throw const FormatException(
          'Скачанный сертификат не прошёл проверку SHA-1 отпечатка.',
        );
      }
      await destination.writeAsBytes(bytes, flush: true);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  bool _isExpectedCertificate(List<int> pemBytes) {
    try {
      final pem = utf8.decode(pemBytes);
      final match = RegExp(
        r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----',
      ).firstMatch(pem);
      if (match == null) return false;
      final base64Body = match.group(1)!.replaceAll(RegExp(r'\s'), '');
      final der = base64.decode(base64Body);
      final thumbprint = sha1.convert(der).toString().toUpperCase();
      return thumbprint == rootThumbprint;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isRootInstalled() async {
    const script = r'''
$thumb = '8FF915CCAB7BC16F8C5C8099D53E0E115B3AEC2F'
$stores = @('Cert:\CurrentUser\Root', 'Cert:\LocalMachine\Root')
foreach ($store in $stores) {
  $found = Get-ChildItem $store -ErrorAction SilentlyContinue |
    Where-Object { $_.Thumbprint -eq $thumb }
  if ($found) { exit 0 }
}
exit 1
''';
    final result = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', script],
      runInShell: false,
    );
    if (result.exitCode == 0) return true;
    if (result.exitCode == 1) return false;
    throw ProcessException(
      'powershell.exe',
      const <String>['-NoProfile', '-NonInteractive', '-Command', script],
      result.stderr.toString(),
      result.exitCode,
    );
  }

  Future<void> _installRootCertificate() async {
    final localAppData = Platform.environment['LOCALAPPDATA']!;
    final certificatePath = '$localAppData${Platform.pathSeparator}MaxAI'
        '${Platform.pathSeparator}AuthProbe'
        '${Platform.pathSeparator}Certificates'
        '${Platform.pathSeparator}russian_trusted_root_ca.pem';

    final result = await Process.run(
      'certutil.exe',
      <String>['-user', '-addstore', 'Root', certificatePath],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'certutil.exe',
        <String>['-user', '-addstore', 'Root', certificatePath],
        result.stderr.toString().isEmpty
            ? result.stdout.toString()
            : result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}

final class WindowsCertificateSetupResult {
  const WindowsCertificateSetupResult({
    required this.securityContext,
    required this.alreadyInstalled,
    required this.installedInWindowsStore,
    required this.thumbprint,
  });

  final SecurityContext securityContext;
  final bool alreadyInstalled;
  final bool installedInWindowsStore;
  final String thumbprint;
}
