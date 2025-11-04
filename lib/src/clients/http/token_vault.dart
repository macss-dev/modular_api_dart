import 'storage/token_storage_adapter.dart';
import 'storage/memory_storage_adapter.dart';

/// Facade for secure storage of refresh tokens.
///
/// Provides a backward-compatible API that delegates to the configured
/// [TokenStorageAdapter]. By default it uses [MemoryStorageAdapter] (non-persistent).
///
/// Platform configuration examples:
///
/// CLI/Server/Desktop:
/// ```dart
/// import 'dart:io';
/// import 'package:modular_api/modular_api.dart';
///
/// Future<String> _passFromEnv() async {
///   final v = Platform.environment['MODULAR_API_PASSPHRASE'];
///   if (v == null || v.isEmpty) {
///     throw Exception('Missing MODULAR_API_PASSPHRASE');
///   }
///   return v;
/// }
///
/// void main() {
///   TokenVault.configure(
///     FileStorageAdapter.encrypted(passphraseProvider: _passFromEnv),
///   );
///   // ...
/// }
/// ```
///
/// Flutter (Android/iOS/Desktop):
/// ```dart
/// // In your Flutter app, create this adapter:
/// class FlutterSecureStorageAdapter implements TokenStorageAdapter {
///   final _storage = FlutterSecureStorage();
///
///   @override
///   Future<void> saveRefresh(String userId, String token) =>
///       _storage.write(key: userId, value: token);
///
///   @override
///   Future<String?> readRefresh(String userId) =>
///       _storage.read(key: userId);
///
///   @override
///   Future<void> deleteRefresh(String userId) =>
///       _storage.delete(key: userId);
///
///   @override
///   Future<void> deleteAll() => _storage.deleteAll();
/// }
///
/// void main() {
///   TokenVault.configure(FlutterSecureStorageAdapter());
///   runApp(MyApp());
/// }
/// ```
final class TokenVault {
  // Active adapter (defaults to memory, non-persistent)
  static TokenStorageAdapter _adapter = MemoryStorageAdapter.shared();

  /// Configures the global storage adapter.
  ///
  /// Should be called at app startup before using [httpClient] with auth.
  ///
  /// CLI/Server example:
  /// ```dart
  /// TokenVault.configure(
  ///   FileStorageAdapter.encrypted(passphraseProvider: _passFromEnv),
  /// );
  /// ```
  ///
  /// Flutter example:
  /// ```dart
  /// TokenVault.configure(FlutterSecureStorageAdapter());
  /// ```
  static void configure(TokenStorageAdapter adapter) {
    _adapter = adapter;
  }

  /// Gets the currently configured adapter.
  ///
  /// Useful if you need to use a different adapter for a specific request:
  /// ```dart
  /// final tempAdapter = MemoryStorageAdapter.shared();
  /// await tempAdapter.saveRefresh('user', 'token');
  /// ```
  static TokenStorageAdapter get adapter => _adapter;

  /// Generates the storage key for a user.
  ///
  /// Prefixes with 'rt:' to differentiate refresh tokens from other data.
  static String _key(String userId) => 'rt:$userId';

  /// Saves a refresh token for the specified user.
  ///
  /// [userId] - Unique identifier for the user (username, email, or ID)
  /// [token] - The refresh token to store securely
  ///
  /// Example:
  /// ```dart
  /// await TokenVault.saveRefresh('user123', refreshToken);
  /// ```
  static Future<void> saveRefresh(String userId, String token) =>
      _adapter.saveRefresh(_key(userId), token);

  /// Reads the refresh token for the specified user.
  ///
  /// Returns `null` if the token is not found.
  ///
  /// Example:
  /// ```dart
  /// final token = await TokenVault.readRefresh('user123');
  /// if (token != null) {
  ///   // Token available
  /// }
  /// ```
  static Future<String?> readRefresh(String userId) =>
      _adapter.readRefresh(_key(userId));

  /// Deletes the refresh token for the specified user.
  ///
  /// Should be called on logout or when the refresh token is invalidated.
  ///
  /// Example:
  /// ```dart
  /// await TokenVault.deleteRefresh('user123');
  /// ```
  static Future<void> deleteRefresh(String userId) =>
      _adapter.deleteRefresh(_key(userId));

  /// Deletes all stored refresh tokens.
  ///
  /// Useful for a full logout of all users.
  ///
  /// Example:
  /// ```dart
  /// await TokenVault.deleteAll();
  /// ```
  static Future<void> deleteAll() => _adapter.deleteAll();
}


