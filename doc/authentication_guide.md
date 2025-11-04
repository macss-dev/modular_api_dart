# Authentication Guide

This guide explains how to use the automatic authentication features in `modular_api` with `httpClient`.

## Overview

The `httpClient` now supports automatic authentication management including:

- ✅ **Automatic Bearer token attachment** for protected endpoints
- ✅ **Token capture** from login responses
- ✅ **Secure refresh token storage** using `flutter_secure_storage`
- ✅ **Auto-retry with token refresh** on 401 responses
- ✅ **Re-login signal** when refresh fails

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  httpClient (auth: true)                                    │
│                                                              │
│  1. Attach Bearer token from Session.accessToken            │
│  2. Make HTTP request                                        │
│  3. If 401 → Try refresh from TokenVault                    │
│  4. Retry with new token                                     │
│  5. If still 401 → Throw AuthReLoginException               │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    Session             TokenVault          AuthReLoginException
   (In-Memory)      (Secure Storage)         (Navigate to login)
```

## Components

### 1. Session (In-Memory)

Keeps the access token in memory during app lifetime. **Never persisted to disk**.

```dart
import 'package:modular_api/modular_api.dart';

// Check authentication status
if (Session.isAuthenticated) {
  print('User is logged in');
}

// Check if token is expired
if (Session.isExpired) {
  print('Token needs refresh');
}

// Clear session on logout
Session.clear();
```

### 2. TokenVault (Platform-Agnostic Storage)

Stores refresh tokens securely using pluggable storage adapters. By default uses `MemoryStorageAdapter` for testing, but can be configured for production use with platform-specific adapters.

```dart
import 'package:modular_api/modular_api.dart';

// Save refresh token (done automatically by httpClient on login)
await TokenVault.saveRefresh('user123', refreshToken);

// Read refresh token (used internally by httpClient)
final token = await TokenVault.readRefresh('user123');

// Delete on logout
await TokenVault.deleteRefresh('user123');

// Delete all tokens (complete cleanup)
await TokenVault.deleteAll();
```

#### Storage Adapters

`TokenVault` uses a **Hybrid Adapter Pattern** allowing different storage strategies per platform:

- **MemoryStorageAdapter** — In-memory storage (default, good for tests)
- **FileStorageAdapter** — File-based with AES-256-GCM encryption (CLI, servers, desktop)
- **FlutterSecureStorageAdapter** — OS keychain/keystore (Flutter mobile/desktop)

#### Configuring Storage Adapter

You must configure the storage adapter before using authentication:

```dart
import 'package:modular_api/modular_api.dart';

void main() async {
  // For CLI/Server apps (Dart pure)
  TokenVault.configure(
    FileStorageAdapter(
      passphrase: Env.getString('TOKEN_PASSPHRASE'),
      // Optional: custom directory
      // directory: '/secure/path/tokens',
    ),
  );

  // Or use memory for testing
  TokenVault.configure(MemoryStorageAdapter.shared());

  // Now authentication works
  await login('user', 'pass');
}
```

#### Platform-Specific Adapters

##### 1. FileStorageAdapter (CLI, Servers, Desktop)

For **Dart-only** applications (CLI tools, servers, desktop apps), use `FileStorageAdapter` with AES-256-GCM encryption:

```dart
import 'package:modular_api/modular_api.dart';

void main() async {
  // Configure with passphrase from environment
  TokenVault.configure(
    FileStorageAdapter(
      passphrase: Env.getString('TOKEN_PASSPHRASE'),
    ),
  );

  // Default storage locations:
  // - Linux: ~/.config/modular_api/tokens.enc
  // - macOS: ~/Library/Application Support/modular_api/tokens.enc
  // - Windows: %APPDATA%\modular_api\tokens.enc
}
```

**Security Features:**
- AES-256-GCM authenticated encryption
- PBKDF2-HMAC-SHA256 key derivation (150,000 iterations)
- Random salt and nonce per encryption
- Atomic file writes (prevents corruption)
- File permissions 600 (Unix) - owner read/write only

**Custom Storage Location:**

```dart
TokenVault.configure(
  FileStorageAdapter(
    passphrase: 'my-secure-passphrase',
    directory: '/secure/custom/path',
  ),
);
```

**Environment Variable Passphrase:**

```bash
# .env file
TOKEN_PASSPHRASE=your-secure-passphrase-here

# Or export
export TOKEN_PASSPHRASE="your-secure-passphrase"
```

##### 2. MemoryStorageAdapter (Testing, Temporary Sessions)

For **tests** or **temporary sessions**, use `MemoryStorageAdapter`:

```dart
import 'package:modular_api/modular_api.dart';

void main() async {
  // Use shared singleton instance
  TokenVault.configure(MemoryStorageAdapter.shared());

  // Tokens stored in memory only
  // Cleared when app terminates
}
```

**Use Cases:**
- Unit tests
- Integration tests
- Temporary CLI sessions
- Debugging

**Helper Methods:**

```dart
final adapter = MemoryStorageAdapter.shared();

// Check token count
print('Tokens stored: ${adapter.tokenCount}');

// List user IDs
print('Users: ${adapter.userIds}');

// Check if specific user has token
print('Has user123: ${adapter.hasTokens}');

// Clear all
await adapter.deleteAll();
```

##### 3. FlutterSecureStorageAdapter (Flutter Mobile/Desktop)

For **Flutter applications** (Android, iOS, macOS, Windows, Linux with Flutter), use `FlutterSecureStorageAdapter`:

```dart
import 'package:modular_api/modular_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure TokenVault with FlutterSecureStorageAdapter
  TokenVault.configure(FlutterSecureStorageAdapter());

  runApp(MyApp());
}

// Implementation
class FlutterSecureStorageAdapter implements TokenStorageAdapter {
  final FlutterSecureStorage _storage;

  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> saveRefresh(String userId, String token) async {
    await _storage.write(key: 'rt:$userId', value: token);
  }

  @override
  Future<String?> readRefresh(String userId) async {
    return await _storage.read(key: 'rt:$userId');
  }

  @override
  Future<void> deleteRefresh(String userId) async {
    await _storage.delete(key: 'rt:$userId');
  }

  @override
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
```

**Platform Support:**
- **Android**: Android Keystore
- **iOS**: Keychain Services
- **macOS**: Keychain Services
- **Windows**: Credential Manager (via `flutter_secure_storage_windows`)
- **Linux**: libsecret (via `flutter_secure_storage_linux`)

**Add Dependency:**

```yaml
dependencies:
  modular_api: ^0.0.7
  flutter_secure_storage: ^9.2.2
```

**Full Flutter Example:**

```dart
import 'package:flutter/material.dart';
import 'package:modular_api/modular_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// FlutterSecureStorageAdapter implementation
class FlutterSecureStorageAdapter implements TokenStorageAdapter {
  final FlutterSecureStorage _storage;

  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> saveRefresh(String userId, String token) async {
    await _storage.write(key: 'rt:$userId', value: token);
  }

  @override
  Future<String?> readRefresh(String userId) async {
    return await _storage.read(key: 'rt:$userId');
  }

  @override
  Future<void> deleteRefresh(String userId) async {
    await _storage.delete(key: 'rt:$userId');
  }

  @override
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure TokenVault for Flutter
  TokenVault.configure(FlutterSecureStorageAdapter());
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LoginScreen(),
    );
  }
}
```

#### Adapter Comparison

| Feature | MemoryStorageAdapter | FileStorageAdapter | FlutterSecureStorageAdapter |
|---------|---------------------|-------------------|----------------------------|
| **Platform** | All (Dart pure) | CLI, Server, Desktop | Flutter (mobile/desktop) |
| **Persistence** | ❌ In-memory only | ✅ File on disk | ✅ OS keychain/keystore |
| **Encryption** | ❌ N/A | ✅ AES-256-GCM | ✅ OS-level encryption |
| **Use Case** | Tests, temp sessions | Production CLI/server | Production Flutter apps |
| **Dependencies** | None | `path`, `cryptography` | `flutter_secure_storage` |
| **Setup Complexity** | Trivial | Moderate (passphrase) | Moderate (platform config) |

#### Migration Guide

If you're upgrading from `modular_api <0.0.4` (which used `flutter_secure_storage` directly):

**Before (< 0.0.4):**
```dart
void main() {
  runApp(MyApp());
  // TokenVault automatically used flutter_secure_storage
}
```

**After (>= 0.0.4):**
```dart
import 'your_adapters.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Explicitly configure adapter
  TokenVault.configure(FlutterSecureStorageAdapter());
  
  runApp(MyApp());
}
```

**Benefits of Migration:**
- ✅ Use modular_api in CLI and server applications
- ✅ Choose storage strategy per platform
- ✅ Test authentication without Flutter framework
- ✅ Custom encryption strategies

### 3. AuthReLoginException

Thrown when authentication fails and the user needs to log in again.

```dart
import 'package:modular_api/modular_api.dart';

try {
  final data = await httpClient(
    method: 'GET',
    baseUrl: BASE_URL,
    endpoint: 'users/me',
    auth: true,
    userId: currentUserId,
  );
} on AuthReLoginException {
  // Navigate to login screen
  await TokenVault.deleteRefresh(currentUserId);
  Session.clear();
  // Navigator.pushReplacementNamed(context, '/login');
}
```

## Usage Examples

### Login Flow

```dart
import 'package:modular_api/modular_api.dart';

Future<void> login(String username, String password) async {
  try {
    // Call login endpoint with auth: true
    // httpClient will automatically capture access_token and refresh_token
    final response = await httpClient(
      method: 'POST',
      baseUrl: 'https://api.example.com',
      endpoint: 'auth/login',
      body: {
        'username': username,
        'password': password,
      },
      auth: true,
      userId: username, // Used as key for TokenVault
    );

    // Tokens are automatically stored:
    // - Session.accessToken (in memory)
    // - Session.accessExp (in memory)
    // - refresh_token via TokenVault (secure storage)

    print('Login successful!');
    print('Access token: ${Session.accessToken}');
    
  } catch (e) {
    print('Login failed: $e');
  }
}
```

**Expected server response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in": 600,
  "refresh_token": "def50200..."
}
```

### Protected Endpoints

```dart
import 'package:modular_api/modular_api.dart';

Future<Map<String, dynamic>> getUserProfile(String userId) async {
  try {
    // httpClient will automatically:
    // 1. Attach Authorization: Bearer {access_token}
    // 2. If 401, try refresh and retry
    // 3. If refresh fails, throw AuthReLoginException
    final profile = await httpClient(
      method: 'GET',
      baseUrl: 'https://api.example.com',
      endpoint: 'users/me',
      auth: true,
      userId: userId,
    );

    return profile as Map<String, dynamic>;
    
  } on AuthReLoginException {
    // Token refresh failed - navigate to login
    await TokenVault.deleteRefresh(userId);
    Session.clear();
    rethrow; // Let UI handle navigation
    
  } catch (e) {
    // Other errors (500, network, etc.)
    print('Error fetching profile: $e');
    rethrow;
  }
}
```

### Logout Flow

```dart
import 'package:modular_api/modular_api.dart';

Future<void> logout(String userId) async {
  try {
    // Optional: Call server logout endpoint
    await httpClient(
      method: 'POST',
      baseUrl: 'https://api.example.com',
      endpoint: 'auth/logout',
      auth: true,
      userId: userId,
    );
  } catch (e) {
    // Continue with local cleanup even if server call fails
    print('Server logout failed: $e');
  } finally {
    // Always clean up local tokens
    await TokenVault.deleteRefresh(userId);
    Session.clear();
    
    // Navigate to login screen
    // Navigator.pushReplacementNamed(context, '/login');
  }
}
```

### Complete Example: Flutter App

```dart
import 'package:flutter/material.dart';
import 'package:modular_api/modular_api.dart';

class AuthService {
  static const String baseUrl = 'https://api.example.com';
  
  Future<bool> login(String username, String password) async {
    try {
      await httpClient(
        method: 'POST',
        baseUrl: baseUrl,
        endpoint: 'auth/login',
        body: {'username': username, 'password': password},
        auth: true,
        userId: username,
      );
      return true;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getProfile(String userId) async {
    return await httpClient(
      method: 'GET',
      baseUrl: baseUrl,
      endpoint: 'users/me',
      auth: true,
      userId: userId,
    ) as Map<String, dynamic>;
  }

  Future<void> logout(String userId) async {
    await TokenVault.deleteRefresh(userId);
    Session.clear();
  }
}

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({required this.userId, super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final authService = AuthService();
  Map<String, dynamic>? profile;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await authService.getProfile(widget.userId);
      setState(() {
        profile = data;
        loading = false;
      });
    } on AuthReLoginException {
      // Token refresh failed - go back to login
      if (mounted) {
        await authService.logout(widget.userId);
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      setState(() {
        loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile == null
          ? const Center(child: Text('No data'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Name: ${profile!['name']}'),
                Text('Email: ${profile!['email']}'),
              ],
            ),
    );
  }
}
```

## Server Requirements

Your authentication API endpoints must return the following JSON format:

### Login Response (`POST /auth/login`)

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 600,
  "refresh_token": "def50200..."
}
```

### Refresh Response (`POST /auth/refresh`)

**Request:**
```json
{
  "refresh_token": "def50200..."
}
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 600,
  "refresh_token": "new-token-if-rotation-enabled"
}
```

> **Note:** The `refresh_token` in the response is optional. Include it only if your API implements token rotation.

## Authentication Flow

```
┌─────────────┐
│ User Login  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ POST /auth/login                     │
│ - Returns access_token & refresh_token  │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ httpClient captures tokens:             │
│ - Session.accessToken (memory)          │
│ - TokenVault.saveRefresh() (secure)     │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ GET /protected-endpoint              │
│ - Attaches Authorization: Bearer token  │
└──────┬──────────────────────────────────┘
       │
       ├─ 200 OK ──────────────► Success
       │
       └─ 401 Unauthorized
            │
            ▼
       ┌─────────────────────────────┐
       │ POST /auth/refresh       │
       │ - Uses TokenVault token     │
       └──────┬──────────────────────┘
              │
              ├─ 200 OK ─► Retry original request
              │
              └─ 401 ─► Throw AuthReLoginException
                         │
                         ▼
                    Navigate to Login
```

## Advanced: Proactive Token Refresh

If you want to refresh tokens before they expire (not just on 401), you can use `Session.accessExp`:

```dart
import 'package:modular_api/modular_api.dart';

Future<void> ensureFreshToken(String userId) async {
  if (Session.accessExp == null) return;
  
  // Refresh 30 seconds before expiration
  final timeUntilExpiry = Session.accessExp!.difference(DateTime.now());
  if (timeUntilExpiry.inSeconds < 30) {
    // Manually trigger refresh by making any auth request
    // (httpClient will handle refresh on 401)
    print('Token expiring soon, will refresh on next request');
  }
}
```

## Error Handling Best Practices

```dart
Future<T> makeAuthenticatedRequest<T>(
  Future<T> Function() request,
  String userId,
) async {
  try {
    return await request();
  } on AuthReLoginException {
    // Clean up and navigate to login
    await TokenVault.deleteRefresh(userId);
    Session.clear();
    // navigationService.goToLogin();
    rethrow;
  } on Exception catch (e) {
    if (e.toString().contains('Connection error')) {
      // Network error - show retry option
      throw Exception('Network error. Please check your connection.');
    }
    // Other errors (500, 404, etc.)
    rethrow;
  }
}
```

## Testing

```dart
import 'package:test/test.dart';
import 'package:modular_api/modular_api.dart';

void main() {
  group('Authentication', () {
    test('Session stores access token', () {
      Session.accessToken = 'test-token';
      expect(Session.isAuthenticated, isTrue);
      
      Session.clear();
      expect(Session.isAuthenticated, isFalse);
    });

    test('AuthReLoginException is thrown', () {
      expect(
        () => throw AuthReLoginException('Test'),
        throwsA(isA<AuthReLoginException>()),
      );
    });
  });
}
```

## Security Notes

1. **Access Token**: Stored in memory only (`Session.accessToken`), cleared on app restart
2. **Refresh Token**: Stored securely using `flutter_secure_storage` (OS keychain/keystore)
3. **Never log tokens**: Avoid printing tokens in production
4. **HTTPS Only**: Always use HTTPS in production for API calls
5. **Token Rotation**: Support optional refresh token rotation from server

## Troubleshooting

### Issue: AuthReLoginException on every request

**Cause**: Server not returning proper token format or `userId` mismatch.

**Solution**: 
- Verify server returns `access_token`, `expires_in`, `refresh_token`
- Ensure same `userId` is used for login and subsequent requests

### Issue: Tokens not persisting

**Cause**: TokenVault uses different `userId` keys.

**Solution**: Use consistent `userId` (username, email, or user ID) across all requests.

### Issue: Refresh loop (continuous 401s)

**Cause**: Refresh token expired or invalidated on server.

**Solution**: `AuthReLoginException` will be thrown - handle it by navigating to login.

---

**Need help?** Check the [issues page](https://github.com/macss-dev/modular_api/issues) or refer to the main [README](../README.md).
