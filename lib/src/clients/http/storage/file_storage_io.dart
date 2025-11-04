import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:cryptography/cryptography.dart';

import 'token_storage_adapter.dart';

/// Type for passphrase providers.
///
/// The function must return the passphrase from a secure source
/// (environment variable, secret manager, etc.).
///
/// Example:
/// ```dart
/// Future<String> _passFromEnv() async {
///   final v = Platform.environment['MODULAR_API_PASSPHRASE'];
///   if (v == null || v.isEmpty) {
///     throw Exception('Missing MODULAR_API_PASSPHRASE');
///   }
///   return v;
/// }
/// ```
typedef PassphraseProvider = Future<String> Function();

/// Interface for token encryption/decryption.
///
/// Allows pluggable implementations of encryption algorithms.
abstract interface class TokenEncryptor {
  /// Encrypts plain data.
  Future<List<int>> encrypt(List<int> plain);

  /// Decrypts encrypted data.
  Future<List<int>> decrypt(List<int> cipher);
}

/// AES-GCM encryptor with PBKDF2-HMAC-SHA256 key derivation.
///
/// Security:
/// - Encrypts/decrypts full bytes (the tokens JSON).
/// - Uses AES-256-GCM (authenticated, non-malleable).
/// - Derives key from passphrase using PBKDF2 with HMAC-SHA256.
/// - Stores a JSON "envelope" on disk with metadata:
///   `{v, kdf, i, s, n, c, t}` where:
///   - `v`: format version (currently 1)
///   - `kdf`: key derivation function used (PBKDF2-HMAC-SHA256)
///   - `i`: PBKDF2 iterations
///   - `s`: salt (base64)
///   - `n`: AES-GCM nonce (base64)
///   - `c`: ciphertext (base64)
///   - `t`: MAC tag (base64)
///
/// Performance:
/// - Default PBKDF2 iterations: 150,000
/// - Tune according to your hardware (security vs latency)
/// - Typical target: 20-60ms per operation
final class AesGcmEncryptor implements TokenEncryptor {
  /// Creates an AES-GCM encryptor.
  ///
  /// [passphraseProvider] - Function that returns the passphrase
  /// [pbkdf2Iterations] - PBKDF2 iterations (more = more secure, but slower)
  /// [saltLength] - Salt length in bytes (16 = 128 bits)
  /// [algorithm] - AES-GCM algorithm to use (defaults to AES-256-GCM)
  AesGcmEncryptor({
    required this.passphraseProvider,
    this.pbkdf2Iterations = 150000,
    this.saltLength = 16,
    AesGcm? algorithm,
  }) : algorithm = algorithm ?? AesGcm.with256bits();

  /// Passphrase provider
  final PassphraseProvider passphraseProvider;

  /// PBKDF2 iterations (tune according to hardware)
  final int pbkdf2Iterations;

  /// Salt length in bytes
  final int saltLength;

  /// AES-GCM algorithm
  final AesGcm algorithm;

  // Cryptographically secure random number generator
  final Random _rng = Random.secure();

  /// Generates cryptographically secure random bytes.
  Uint8List _randomBytes(int len) {
    final b = Uint8List(len);
    for (var i = 0; i < len; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  /// Derives a cryptographic key from the passphrase using PBKDF2.
  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pbkdf2Iterations,
      bits: 256, // AES-256
    );
    return pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
  }

  @override
  Future<List<int>> encrypt(List<int> plain) async {
    final pass = await passphraseProvider();
    if (pass.isEmpty) {
      throw const TokenStorageException('Empty passphrase for encryption');
    }

    // Generate random salt and nonce
    final salt = _randomBytes(saltLength);
    final key = await _deriveKey(pass, salt);
    final nonce = _randomBytes(12); // AES-GCM estándar: 96-bit nonce

    // Encrypt with AES-GCM
    final box = await algorithm.encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
    );

    // Create JSON envelope with metadata + ciphertext + MAC
    final envelope = <String, dynamic>{
      'v': 1, // format version
      'kdf': 'PBKDF2-HMAC-SHA256',
      'i': pbkdf2Iterations,
      's': base64Encode(salt),
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      't': base64Encode(box.mac.bytes),
    };

    return utf8.encode(jsonEncode(envelope));
  }

  @override
  Future<List<int>> decrypt(List<int> cipher) async {
    final pass = await passphraseProvider();
    if (pass.isEmpty) {
      throw const TokenStorageException('Empty passphrase for decryption');
    }

    // Parse envelope JSON
    Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(cipher)) as Map<String, dynamic>;
    } on Object catch (e, st) {
      throw TokenStorageException(
        'File content is not valid JSON',
        cause: e,
        stackTrace: st,
      );
    }

    // Verify envelope version
    final v = env['v'];
    if (v != 1) {
      throw TokenStorageException('Unsupported envelope version: $v');
    }

    try {
  // Extract envelope components
      final salt = base64Decode(env['s'] as String);
      final nonce = base64Decode(env['n'] as String);
      final ciph = base64Decode(env['c'] as String);
      final tag = base64Decode(env['t'] as String);

  // Derive key and decrypt
      final key = await _deriveKey(pass, salt);
      final box = SecretBox(ciph, nonce: nonce, mac: Mac(tag));
      final plain = await algorithm.decrypt(box, secretKey: key);
      return plain;
    } on SecretBoxAuthenticationError catch (e, st) {
      throw TokenStorageException(
        'Authentication failure: incorrect passphrase or tampered file',
        cause: e,
        stackTrace: st,
      );
    } on Object catch (e, st) {
      throw TokenStorageException(
        'Error while decrypting: ${e.toString()}',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

/// File-based storage adapter with AES-GCM encryption at rest.
///
/// Features:
/// - Atomic writes (tmp + rename) to avoid corruption
/// - AES-256-GCM encryption with PBKDF2 key derivation
/// - Restrictive permissions (600 on Unix)
/// - Cross-platform default paths:
///   - Linux: `~/.config/modular_api/refresh_tokens.enc`
///   - macOS: `~/Library/Application Support/modular_api/refresh_tokens.enc`
///   - Windows: `%APPDATA%\modular_api\refresh_tokens.enc`
///
/// CLI Example:
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
/// void main() async {
///   TokenVault.configure(
///     FileStorageAdapter.encrypted(
///       passphraseProvider: _passFromEnv,
///     ),
///   );
///
///   // Now httpClient can persist refresh tokens
///   await httpClient(
///     method: 'POST',
///     endpoint: 'auth/login',
///     body: {'username': 'admin', 'password': 'secret'},
///     auth: true,
///     userId: 'admin',
///   );
/// }
/// ```
///
/// Security:
/// - **NEVER** hardcode the passphrase in source code
/// - Use environment variables or a secret manager
/// - On Unix, file permissions are set to 600 (owner read/write only)
/// - On Windows, manage ACLs at the folder level
final class FileStorageAdapter implements TokenStorageAdapter {
  /// Creates a file adapter with encryption.
  ///
  /// [passphraseProvider] - Function that returns the passphrase securely
  /// [baseDir] - Base directory (null = use platform default)
  /// [fileName] - Name of the encrypted file
  /// [setPosix600] - Try to set 600 permissions on Unix (recommended)
  FileStorageAdapter.encrypted({
    required PassphraseProvider passphraseProvider,
    String? baseDir,
    String fileName = 'refresh_tokens.enc',
    this.setPosix600 = true,
  })  : _dir = Directory(baseDir ?? _defaultBaseDir()),
        _file = File(p.join(baseDir ?? _defaultBaseDir(), fileName)),
        _encryptor = AesGcmEncryptor(passphraseProvider: passphraseProvider) {
    // Create directory if it does not exist
    _dir.createSync(recursive: true);
  }

  final Directory _dir;
  final File _file;
  final TokenEncryptor _encryptor;
  final bool setPosix600;

  /// Returns the default base directory according to the platform.
  ///
  /// [appName] - Application name used in the path
  ///
  /// Linux: `~/.config/appName/`
  /// macOS: `~/Library/Application Support/appName/`
  /// Windows: `%APPDATA%\appName\`
  static String _defaultBaseDir({String appName = 'modular_api'}) {
    final isWindows = Platform.isWindows;
    final home = Platform.environment[isWindows ? 'USERPROFILE' : 'HOME'] ?? '.';

    if (isWindows) {
      return p.join(home, 'AppData', 'Roaming', appName);
    }

    if (Platform.isMacOS) {
      return p.join(home, 'Library', 'Application Support', appName);
    }

    // Linux/Unix: use XDG_CONFIG_HOME if defined
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    return p.join(xdg ?? p.join(home, '.config'), appName);
  }

  /// Reads all tokens from the encrypted file.
  Future<Map<String, String>> _readAll() async {
    if (!await _file.exists()) {
      return <String, String>{};
    }

    final raw = await _file.readAsBytes();
    if (raw.isEmpty) {
      return <String, String>{};
    }

    // Decrypt
    final plain = await _encryptor.decrypt(raw);

    // Parse JSON
    final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v as String));
  }

  /// Writes all tokens to the encrypted file atomically.
  Future<void> _writeAll(Map<String, String> data) async {
  // Serialize to JSON
    final content = jsonEncode(data);
    final plainBytes = utf8.encode(content);


    // Encrypt
    final encBytes = await _encryptor.encrypt(plainBytes);

  // Atomic write: write to .tmp and then rename
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsBytes(encBytes, flush: true);

    // Best effort: set permissions to 600 on Unix (owner read/write only)
    if (setPosix600 && !Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmp.path]);
      } catch (_) {
        // Ignore if chmod is not available
      }
    }

    // Atomic rename (overwrite existing file if present)
    if (await _file.exists()) {
      await _file.delete();
    }
    await tmp.rename(_file.path);

    // Best effort: reinforce permissions on the final file
    if (setPosix600 && !Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', _file.path]);
      } catch (_) {
        // Ignore if it fails
      }
    }
  }

  @override
  Future<void> saveRefresh(String userId, String token) async {
    final map = await _readAll();
    map[userId] = token;
    await _writeAll(map);
  }

  @override
  Future<String?> readRefresh(String userId) async {
    final map = await _readAll();
    return map[userId];
  }

  @override
  Future<void> deleteRefresh(String userId) async {
    final map = await _readAll();
    map.remove(userId);
    await _writeAll(map);
  }

  @override
  Future<void> deleteAll() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}
