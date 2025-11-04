import 'token_storage_adapter.dart';

/// Type for passphrase providers.
///
/// The function should return the passphrase from a secure source
/// (environment variable, secret manager, etc.).
typedef PassphraseProvider = Future<String> Function();

/// Interface for token encryption/decryption.
///
/// Allows pluggable implementations of encryption algorithms.
abstract interface class TokenEncryptor {
  /// Encrypt plain bytes.
  Future<List<int>> encrypt(List<int> plain);

  /// Decrypt cipher bytes.
  Future<List<int>> decrypt(List<int> cipher);
}

/// Stub implementation of AesGcmEncryptor for platforms without dart:io.
///
/// This class exists only so the code compiles on platforms such as web
/// where using a FileStorageAdapter is not recommended for security reasons.
final class AesGcmEncryptor implements TokenEncryptor {
  /// Stub constructor that accepts a passphraseProvider for API compatibility.
  AesGcmEncryptor({required PassphraseProvider passphraseProvider});

  Never _err() => throw UnsupportedError(
        'AesGcmEncryptor is not available on this platform. '
        'This functionality requires dart:io (CLI/server/desktop).',
      );

  @override
  Future<List<int>> encrypt(List<int> plain) async => _err();

  @override
  Future<List<int>> decrypt(List<int> cipher) async => _err();
}

/// Stub implementation of FileStorageAdapter for platforms without dart:io.
///
/// This class exists only so the code compiles on platforms such as web.
///
/// Important: Do NOT use FileStorageAdapter on the web for security reasons.
/// Instead:
/// - Flutter Web: implement a custom adapter backed by IndexedDB (not recommended for tokens)
/// - Web in general: prefer server-side sessions or a secure backend storage
///   (sessionStorage/localStorage are not secure for long-lived refresh tokens)
final class FileStorageAdapter implements TokenStorageAdapter {
  /// Stub constructor accepting parameters for API compatibility.
  FileStorageAdapter.encrypted({
    required PassphraseProvider passphraseProvider,
    String? baseDir,
    String fileName = 'refresh_tokens.enc',
  });

  Never _err() => throw UnsupportedError(
        'FileStorageAdapter is not available on this platform. '
        'This functionality requires dart:io (CLI/server/desktop). '
        '\n\nFor web apps, consider:'
        '\n- Using server-side sessions (recommended)'
        '\n- Implementing a custom adapter that stores tokens on a secure backend'
        '\n- Using MemoryStorageAdapter for temporary sessions',
      );

  @override
  Future<void> saveRefresh(String userId, String token) async => _err();

  @override
  Future<String?> readRefresh(String userId) async => _err();

  @override
  Future<void> deleteRefresh(String userId) async => _err();

  @override
  Future<void> deleteAll() async => _err();
}
