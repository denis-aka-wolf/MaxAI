import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

enum WindowsCertificateKind { root, intermediate }

final class WindowsCertificateInfo {
  const WindowsCertificateInfo({
    required this.kind,
    required this.subject,
    required this.issuer,
    required this.thumbprint,
    required this.sha256,
    required this.notBefore,
    required this.notAfter,
    required this.currentUserInstalled,
    required this.localMachineInstalled,
  });

  final WindowsCertificateKind kind;
  final String subject;
  final String issuer;
  final String thumbprint;
  final String sha256;
  final DateTime notBefore;
  final DateTime notAfter;
  final bool currentUserInstalled;
  final bool localMachineInstalled;

  bool get installed => currentUserInstalled || localMachineInstalled;
}

final class WindowsCertificateManager {
  static const String rootCertificateUrl =
      'https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt';
  // The 2024 intermediate is the one presented by api2.oneme.ru.
  // The older generic *_sub_ca_pem.crt endpoint serves a different 2022 CA.
  static const String intermediateCertificateUrl =
      'https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.zip';

  static const String rootThumbprint =
      '8FF915CCAB7BC16F8C5C8099D53E0E115B3AEC2F';
  static const String rootSha256 =
      'D26D2D0231B7C39F92CC738512BA54103519E4405D68B5BD703E9788CA8ECF31';
  static const String intermediateThumbprint =
      '6741AB02CF6598C09652DC34D2DC095904E32B52';
  static const String intermediateSha256 =
      '2155785036C900DBB5F1BB2A1569C80C55595BD6BF94867A29BBDDBC7D88A3F2';

  Future<WindowsCertificateInfo> inspect(WindowsCertificateKind kind) async {
    _requireWindows();
    final path = await _loadVerifiedCertificate(kind);
    final metadata = await _readCertificateMetadata(path, kind);
    final stores = await _readStorePresence(kind);
    final expectedSubject = kind == WindowsCertificateKind.root
        ? 'CN=Russian Trusted Root CA'
        : 'CN=Russian Trusted Sub CA';
    if (!metadata.subject.contains(expectedSubject)) {
      throw StateError('Неожиданный Subject сертификата: ${metadata.subject}');
    }
    if (kind == WindowsCertificateKind.root &&
        metadata.subject != metadata.issuer) {
      throw StateError('Корневой сертификат не является самоподписанным.');
    }
    if (kind == WindowsCertificateKind.intermediate &&
        !metadata.issuer.contains('CN=Russian Trusted Root CA')) {
      throw StateError('Промежуточный сертификат выпущен неизвестным УЦ.');
    }
    return WindowsCertificateInfo(
      kind: kind,
      subject: metadata.subject,
      issuer: metadata.issuer,
      thumbprint: _thumbprint(kind),
      sha256: _sha256(kind),
      notBefore: metadata.notBefore,
      notAfter: metadata.notAfter,
      currentUserInstalled: stores.currentUser,
      localMachineInstalled: stores.localMachine,
    );
  }

  Future<SecurityContext> createTlsContext() async {
    _requireWindows();
    final rootPath = await _loadVerifiedCertificate(
      WindowsCertificateKind.root,
    );
    final rootBytes = await File(rootPath).readAsBytes();
    // Keep the platform roots and add the pinned Russian root. The server
    // must present its intermediate; it is not promoted to a trust anchor.
    return SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(rootBytes);
  }

  Future<void> install(WindowsCertificateKind kind) async {
    _requireWindows();
    final path = await _loadVerifiedCertificate(kind);
    final stores = await _readStorePresence(kind);
    if (stores.currentUser || stores.localMachine) return;

    final store = kind == WindowsCertificateKind.root ? 'Root' : 'CA';
    final args = <String>['-user', '-addstore', store, path];
    final result = await Process.run(
      'certutil.exe',
      args,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'certutil.exe',
        args,
        result.stderr.toString().isEmpty
            ? result.stdout.toString()
            : result.stderr.toString(),
        result.exitCode,
      );
    }
    final verified = await _readStorePresence(kind);
    if (!verified.currentUser && !verified.localMachine) {
      throw StateError('Windows не подтвердила установку сертификата в $store.');
    }
  }

  Future<String> certificatePath(WindowsCertificateKind kind) async {
    _requireWindows();
    return _loadVerifiedCertificate(kind);
  }

  void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Проверка сертификатов доступна только в Windows.');
    }
  }

  String _thumbprint(WindowsCertificateKind kind) =>
      kind == WindowsCertificateKind.root
          ? rootThumbprint
          : intermediateThumbprint;

  String _sha256(WindowsCertificateKind kind) =>
      kind == WindowsCertificateKind.root ? rootSha256 : intermediateSha256;

  String _url(WindowsCertificateKind kind) =>
      kind == WindowsCertificateKind.root
          ? rootCertificateUrl
          : intermediateCertificateUrl;

  String _fileName(WindowsCertificateKind kind) =>
      kind == WindowsCertificateKind.root
          ? 'russian_trusted_root_ca.pem'
          : 'russian_trusted_sub_ca_2024.pem';

  Future<String> _loadVerifiedCertificate(
    WindowsCertificateKind kind,
  ) async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('Не задана переменная LOCALAPPDATA.');
    }
    final directory = Directory(
      '$localAppData${Platform.pathSeparator}MaxAI'
      '${Platform.pathSeparator}AuthProbe'
      '${Platform.pathSeparator}Certificates',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_fileName(kind)}',
    );

    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (!_isExpectedCertificate(existing, kind)) {
        await file.delete();
      }
    }
    if (!await file.exists()) {
      await _downloadCertificate(file, kind);
    }
    final bytes = await file.readAsBytes();
    if (!_isExpectedCertificate(bytes, kind)) {
      throw StateError('Сертификат не прошёл проверку SHA-256.');
    }
    // Parse through Windows CryptoAPI and validate dates and CA constraints.
    await _readCertificateMetadata(file.path, kind);
    return file.path;
  }

  Future<void> _downloadCertificate(
    File destination,
    WindowsCertificateKind kind,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(_url(kind));
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Официальный сервер сертификатов вернул HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final downloaded = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );

      List<int> certificateBytes;
      if (kind == WindowsCertificateKind.root) {
        certificateBytes = downloaded;
      } else {
        final archive = ZipDecoder().decodeBytes(downloaded);
        final matches = archive.files.where((entry) =>
            entry.isFile &&
            entry.name.split('/').last == 'russian_trusted_sub_ca_2024_pem.crt');
        if (matches.length != 1) {
          throw const FormatException(
            'В официальном архиве не найден единственный сертификат Sub CA 2024.',
          );
        }
        certificateBytes = matches.single.content as List<int>;
      }

      if (!_isExpectedCertificate(certificateBytes, kind)) {
        throw const FormatException(
          'Загруженный сертификат не совпадает с закреплённым SHA-256.',
        );
      }
      await destination.writeAsBytes(certificateBytes, flush: true);
    } finally {
      client.close(force: true);
    }
  }

  bool _isExpectedCertificate(
    List<int> bytes,
    WindowsCertificateKind kind,
  ) {
    try {
      final pem = utf8.decode(bytes);
      final match = RegExp(
        r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----',
      ).firstMatch(pem);
      if (match == null) return false;
      final der = base64.decode(
        match.group(1)!.replaceAll(RegExp(r'\s'), ''),
      );
      return sha1.convert(der).toString().toUpperCase() ==
              _thumbprint(kind) &&
          sha256.convert(der).toString().toUpperCase() == _sha256(kind);
    } catch (_) {
      return false;
    }
  }

  Future<_CertificateMetadata> _readCertificateMetadata(
    String path,
    WindowsCertificateKind kind,
  ) async {
    final escapedPath = path.replaceAll("'", "''");
    final script = r'''
$ErrorActionPreference = 'Stop'
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('__PATH__')
$basic = $cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' } | Select-Object -First 1
if (-not $basic) { throw 'Basic Constraints extension is missing' }
$constraints = [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($basic, $basic.Critical)
if (-not $constraints.CertificateAuthority) { throw 'Certificate is not a CA' }
[pscustomobject]@{
  Subject = $cert.Subject
  Issuer = $cert.Issuer
  NotBefore = $cert.NotBefore.ToUniversalTime().ToString('o')
  NotAfter = $cert.NotAfter.ToUniversalTime().ToString('o')
  IsCA = $constraints.CertificateAuthority
} | ConvertTo-Json -Compress
'''.replaceAll('__PATH__', escapedPath);
    final result = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', script],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell.exe',
        const <String>['-NoProfile', '-NonInteractive', '-Command', script],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    final map = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    final notBefore = DateTime.parse(map['NotBefore'] as String).toLocal();
    final notAfter = DateTime.parse(map['NotAfter'] as String).toLocal();
    final now = DateTime.now();
    if (now.isBefore(notBefore) || now.isAfter(notAfter)) {
      throw StateError('Сертификат вне срока действия: $notBefore - $notAfter');
    }
    return _CertificateMetadata(
      subject: map['Subject'] as String,
      issuer: map['Issuer'] as String,
      notBefore: notBefore,
      notAfter: notAfter,
    );
  }

  Future<_StorePresence> _readStorePresence(
    WindowsCertificateKind kind,
  ) async {
    final thumb = _thumbprint(kind);
    final store = kind == WindowsCertificateKind.root ? 'Root' : 'CA';
    final script = r'''
$thumb = '__THUMB__'
$store = '__STORE__'
$current = Get-ChildItem ("Cert:\CurrentUser\" + $store) -ErrorAction SilentlyContinue |
  Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
$machine = Get-ChildItem ("Cert:\LocalMachine\" + $store) -ErrorAction SilentlyContinue |
  Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
[pscustomobject]@{
  CurrentUser = [bool]$current
  LocalMachine = [bool]$machine
} | ConvertTo-Json -Compress
'''.replaceAll('__THUMB__', thumb).replaceAll('__STORE__', store);
    final result = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', script],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell.exe',
        const <String>['-NoProfile', '-NonInteractive', '-Command', script],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    final map = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    return _StorePresence(
      currentUser: map['CurrentUser'] == true,
      localMachine: map['LocalMachine'] == true,
    );
  }
}

final class _CertificateMetadata {
  const _CertificateMetadata({
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
  });

  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;
}

final class _StorePresence {
  const _StorePresence({
    required this.currentUser,
    required this.localMachine,
  });

  final bool currentUser;
  final bool localMachine;
}
