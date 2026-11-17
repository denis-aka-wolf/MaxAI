typedef ConfigHash = Object;

const String defaultConfigHash =
    '00000000-0000000000000000-00000000-'
    '0000000000000000-0000000000000000-0-'
    '0000000000000000-00000000';

final class SyncState {
  const SyncState({
    this.chatsSync = -1,
    this.contactsSync = -1,
    this.draftsSync = -1,
    this.presenceSync = -1,
    this.configHash = defaultConfigHash,
  });

  final int chatsSync;
  final int contactsSync;
  final int draftsSync;
  final int presenceSync;
  final ConfigHash configHash;

  SyncState copyWith({
    int? chatsSync,
    int? contactsSync,
    int? draftsSync,
    int? presenceSync,
    ConfigHash? configHash,
  }) => SyncState(
        chatsSync: chatsSync ?? this.chatsSync,
        contactsSync: contactsSync ?? this.contactsSync,
        draftsSync: draftsSync ?? this.draftsSync,
        presenceSync: presenceSync ?? this.presenceSync,
        configHash: configHash ?? this.configHash,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.chatsSync == chatsSync &&
      other.contactsSync == contactsSync &&
      other.draftsSync == draftsSync &&
      other.presenceSync == presenceSync &&
      other.configHash == configHash;

  @override
  int get hashCode => Object.hash(
        chatsSync,
        contactsSync,
        draftsSync,
        presenceSync,
        configHash,
      );

  @override
  String toString() => 'SyncState(chatsSync: $chatsSync, contactsSync: $contactsSync, '
      'draftsSync: $draftsSync, presenceSync: $presenceSync, configHashSet: true)';
}
