import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  const config = ApkFingerprintConfig(
    certificateMetaSha256:
        '1684414033eb263e2c615f8b7df5ed8793850a07656304997fbf07e9e21e1e93',
    dexMetaSha256:
        '40ce6cc7fdd85631210bc2096727f20a12a01da416cfb52b3eb0c3f2585a7367',
    soMetaSha256: {
      'arm64-v8a':
          '657cd4630bc7435e9430f34e968cc7134b8e6d5c9b35f66360025aedd70cc548',
      'x86_64':
          'cbfec115b7a7c19b6a9fd36ec1f066cac829e783f8ceb0ba3314cd8abeb8159d',
    },
    sourceVersion: '26.10.0',
  );

  test('creates 96-byte fingerprint deterministically', () {
    final provider = Sha256FingerprintProvider(config);
    final first = provider.generate(
      deviceId: 'device-123',
      callsSeed: 42,
      architecture: 'arm64-v8a',
    );
    final second = provider.generate(
      deviceId: 'device-123',
      callsSeed: 42,
      architecture: 'arm64-v8a',
    );
    expect(first, hasLength(96));
    expect(second, equals(first));
  });

  test('changes when callsSeed or architecture changes', () {
    final provider = Sha256FingerprintProvider(config);
    final baseline = provider.generate(
      deviceId: 'device-123',
      callsSeed: 42,
      architecture: 'arm64-v8a',
    );
    final otherSeed = provider.generate(
      deviceId: 'device-123',
      callsSeed: 43,
      architecture: 'arm64-v8a',
    );
    final otherArch = provider.generate(
      deviceId: 'device-123',
      callsSeed: 42,
      architecture: 'x86_64',
    );
    expect(otherSeed, isNot(equals(baseline)));
    expect(otherArch, isNot(equals(baseline)));
  });

  test('rejects unsupported architecture', () {
    final provider = Sha256FingerprintProvider(config);
    expect(
      () => provider.generate(
        deviceId: 'device-123',
        callsSeed: 42,
        architecture: 'unknown',
      ),
      throwsUnsupportedError,
    );
  });
}
