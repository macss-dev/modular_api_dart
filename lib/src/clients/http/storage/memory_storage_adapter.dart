import 'token_storage_adapter.dart';

/// In-memory storage (non-persistent).
///
/// Ideal for:
/// - Unit and integration tests
/// - Rapid prototypes
/// - Temporary sessions that do not require persistence
///
/// **Note**: Tokens are lost when the application exits.
///
/// Example:
/// ```dart
/// import 'package:modular_api/modular_api.dart';
///
/// void main() {
///   // Configure for tests
///   TokenVault.configure(MemoryStorageAdapter.shared());
///
///   // Tokens will now be stored in memory only
/// }
/// ```
final class MemoryStorageAdapter implements TokenStorageAdapter {
  // Singleton para compartir estado en memoria durante toda la sesión
  MemoryStorageAdapter._();

  /// Instancia compartida del adapter (singleton).
  static final MemoryStorageAdapter instance = MemoryStorageAdapter._();

  /// Factory constructor que retorna la instancia singleton.
  factory MemoryStorageAdapter.shared() => instance;

  // Almacenamiento interno en memoria
  final Map<String, String> _data = <String, String>{};

  @override
  Future<void> saveRefresh(String userId, String token) async {
    _data[userId] = token;
  }

  @override
  Future<String?> readRefresh(String userId) async {
    return _data[userId];
  }

  @override
  Future<void> deleteRefresh(String userId) async {
    _data.remove(userId);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }

  /// Returns whether there are tokens currently stored.
  ///
  /// Useful for debugging and tests.
  bool get hasTokens => _data.isNotEmpty;

  /// Returns the number of tokens stored.
  ///
  /// Useful for debugging and tests.
  int get tokenCount => _data.length;

  /// Lists all userIds that have tokens stored.
  ///
  /// Useful for debugging and tests. **Do not use in production** for security reasons.
  List<String> get userIds => _data.keys.toList();
}
