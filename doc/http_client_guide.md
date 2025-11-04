# httpClient Guide

Complete guide for using `httpClient` function in both Flutter and pure Dart applications.

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
  - [Flutter Setup](#flutter-setup)
  - [Pure Dart / CLI Setup](#pure-dart--cli-setup)
- [Common Usage Patterns](#common-usage-patterns)
  - [Login](#login)
  - [Protected Endpoints](#protected-endpoints)
  - [Logout](#logout)
  - [Error Handling](#error-handling)
- [Complete Examples](#complete-examples)
  - [Flutter App Example](#flutter-app-example)
  - [Pure Dart CLI Example](#pure-dart-cli-example)
- [API Reference](#api-reference)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

`httpClient` is a smart HTTP client designed for **single-user applications** that automatically handles authentication, token management, and token refresh for REST APIs. It eliminates the need to manually manage Bearer tokens and refresh logic.

**What it does automatically:**
- Attaches Bearer tokens to authenticated requests
- Captures and stores access/refresh tokens from login responses
- Detects 401 errors and attempts to refresh the access token
- Retries the original request with the new token
- Throws `AuthReLoginException` when refresh fails (signals re-login needed)

**Single-User Design (v0.0.7+):**
- Optimized for single-user applications (one user at a time)
- No need to pass user identifiers
- Simplified API surface
- Internal management of token storage keys

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Auto Bearer Token** | Automatically adds `Authorization: Bearer <token>` header when `auth: true` |
| **Token Capture** | Captures `access_token` and `refresh_token` from login responses |
| **Auto Refresh** | On 401 error, automatically refreshes token and retries request |
| **Token Storage** | Securely stores refresh tokens using configurable adapters |
| **Re-login Signal** | Throws `AuthReLoginException` when user must log in again |
| **Cross-platform** | Works in Flutter (iOS/Android/Web/Desktop) and pure Dart (CLI/Server) |
| **Single-User Optimized** | Designed for single-user apps - no user identifiers needed |

---

## Quick Start

### Basic Usage

```dart
import 'package:modular_api/modular_api.dart';

// Login - captures tokens automatically
final loginData = await httpClient(
  method: 'POST',
  baseUrl: 'https://api.example.com',
  endpoint: 'api/auth/login',
  body: {'username': 'user', 'password': 'pass'},
  auth: true,  // Enable token auto-capture
);

// Protected endpoint - auto token + auto refresh
try {
  final data = await httpClient(
    method: 'GET',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/users/profile',
    auth: true,  // Auto-attaches Bearer token
  );
  print('User data: $data');
} on AuthReLoginException {
  // Navigate to login screen
  print('Session expired, please login again');
}
```

---

## Configuration

Before using `httpClient` with authentication, configure the `TokenVault` to store refresh tokens securely.

### Flutter Setup

**Step 1:** Add dependency

```yaml
# pubspec.yaml
dependencies:
  modular_api: ^0.0.7
  flutter_secure_storage: ^9.0.0
```

**Step 2:** Create Flutter adapter

```dart
// lib/services/flutter_storage_adapter.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:modular_api/modular_api.dart';

class FlutterStorageAdapter implements TokenStorageAdapter {
  final _storage = const FlutterSecureStorage();

  @override
  Future<void> saveRefresh(String userId, String token) async {
    await _storage.write(key: userId, value: token);
  }

  @override
  Future<String?> readRefresh(String userId) async {
    return await _storage.read(key: userId);
  }

  @override
  Future<void> deleteRefresh(String userId) async {
    await _storage.delete(key: userId);
  }

  @override
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
```

**Step 3:** Configure at app startup

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:modular_api/modular_api.dart';
import 'services/flutter_storage_adapter.dart';

void main() {
  // Configure TokenVault before using httpClient
  TokenVault.configure(FlutterStorageAdapter());
  
  runApp(const MyApp());
}
```

### Pure Dart / CLI Setup

**Step 1:** Add dependency

```yaml
# pubspec.yaml
dependencies:
  modular_api: ^0.0.7
```

**Step 2:** Configure at startup

```dart
// bin/main.dart
import 'dart:io';
import 'package:modular_api/modular_api.dart';

Future<String> _getPassphrase() async {
  final passphrase = Platform.environment['MODULAR_API_PASSPHRASE'];
  if (passphrase == null || passphrase.isEmpty) {
    throw Exception('MODULAR_API_PASSPHRASE environment variable not set');
  }
  return passphrase;
}

Future<void> main() async {
  // Configure encrypted file storage
  TokenVault.configure(
    FileStorageAdapter.encrypted(passphraseProvider: _getPassphrase),
  );
  
  // Now you can use httpClient with auth
  await runApp();
}
```

**Environment variable setup:**

```bash
# Linux/macOS
export MODULAR_API_PASSPHRASE="your-secure-passphrase-here"

# Windows PowerShell
$env:MODULAR_API_PASSPHRASE="your-secure-passphrase-here"
```

---

## Common Usage Patterns

### Login

Login automatically captures and stores both access and refresh tokens.

```dart
try {
  final response = await httpClient(
    method: 'POST',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/auth/login',
    body: {
      'username': 'john.doe',
      'password': 'secure_password_123',
    },
    auth: true,  // Enable auth features - auto-captures tokens
  );
  
  print('Login successful!');
  print('Access token expires in: ${response['expires_in']} seconds');
  
  // Tokens are now stored automatically:
  // - Token.accessToken (in-memory)
  // - Token.accessExp (in-memory)
  // - Refresh token (secure storage via TokenVault)
  
} catch (e) {
  print('Login failed: $e');
}
```

**What happens:**
1. Makes POST request to login endpoint
2. On success (200), extracts `access_token`, `refresh_token`, and `expires_in`
3. Stores `access_token` in memory (`Token.accessToken`)
4. Stores `refresh_token` securely via `TokenVault` (using internal key)
5. Returns the full response body

### Protected Endpoints

Protected endpoints automatically get the Bearer token and auto-refresh on 401.

```dart
try {
  // GET request
  final profile = await httpClient(
    method: 'GET',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/users/profile',
    auth: true,  // Auto-attaches Bearer token
  );
  print('User name: ${profile['name']}');
  
  // POST request
  final result = await httpClient(
    method: 'POST',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/users/update',
    body: {'name': 'John Updated'},
    auth: true,  // Auto-attaches Bearer token
  );
  print('Update result: $result');
  
} on AuthReLoginException {
  // Refresh failed - user must log in again
  print('Session expired. Please log in again.');
  // Navigate to login screen in your UI
} catch (e) {
  // Other errors (network, server error, etc.)
  print('Request failed: $e');
}
```

**What happens:**
1. Adds `Authorization: Bearer <token>` header using `Token.accessToken`
2. Makes the request
3. If response is 401:
   - Reads refresh token from `TokenVault`
   - Calls `POST /api/auth/refresh` with refresh token
   - Updates `Token.accessToken` with new token
   - Retries original request with new token
4. If refresh also fails → throws `AuthReLoginException`

### Logout

Logout revokes the refresh token on the server and clears local session.

```dart
try {
  // Get refresh token for logout
  final refreshToken = await TokenVault.readRefresh();
  
  // Call logout endpoint
  final response = await httpClient(
    method: 'POST',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/auth/logout',
    body: {'refresh_token': refreshToken},
  );
  
  print('Logout successful: ${response['message']}');
  
  // Clear local session
  Token.clear();  // Clears access token from memory
  await TokenVault.deleteRefresh();  // Removes refresh token
  
  // Navigate to login screen
  
} catch (e) {
  print('Logout failed: $e');
  // Still clear local tokens even if server call fails
  Token.clear();
  await TokenVault.deleteRefresh();
}
```

**Logout all sessions:**

```dart
final refreshToken = await TokenVault.readRefresh();

final response = await httpClient(
  method: 'POST',
  baseUrl: 'https://api.example.com',
  endpoint: 'api/auth/logout_all',
  body: {'refresh_token': refreshToken},
);

print('Revoked ${response['revoked_count']} sessions');

// Clear local session
Token.clear();
await TokenVault.deleteRefresh();
```

### Error Handling

Handle different error scenarios appropriately.

```dart
try {
  final data = await httpClient(
    method: 'GET',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/data',
    auth: true,
  );
  
  // Success - process data
  processData(data);
  
} on AuthReLoginException {
  // Session expired, refresh failed
  // Clear session and navigate to login
  Token.clear();
  await TokenVault.deleteRefresh();
  navigateToLogin();
  
} catch (e) {
  // Other errors: network issues, server errors, timeouts
  if (e.toString().contains('Connection error')) {
    showError('Network connection failed. Please check your internet.');
  } else if (e.toString().contains('403')) {
    showError('Access denied. You don\'t have permission.');
  } else if (e.toString().contains('404')) {
    showError('Resource not found.');
  } else {
    showError('An error occurred: $e');
  }
}
```

---

## Complete Examples

### Flutter App Example

**Full authentication flow in a Flutter app:**

```dart
// lib/services/api_service.dart
import 'package:modular_api/modular_api.dart';

class ApiService {
  static const String baseUrl = 'https://api.example.com';
  
  // Login
  Future<bool> login(String username, String password) async {
    try {
      final response = await httpClient(
        method: 'POST',
        baseUrl: baseUrl,
        endpoint: 'api/auth/login',
        body: {'username': username, 'password': password},
        auth: true,  // Auto-captures tokens
      );
      
      return true;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }
  
  // Get user profile
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final profile = await httpClient(
        method: 'GET',
        baseUrl: baseUrl,
        endpoint: 'api/users/profile',
        auth: true,  // Auto-attaches Bearer token
      );
      return profile as Map<String, dynamic>;
    } on AuthReLoginException {
      await logout();
      rethrow;
    }
  }
  
  // Update profile
  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      await httpClient(
        method: 'PATCH',
        baseUrl: baseUrl,
        endpoint: 'api/users/profile',
        body: data,
        auth: true,
      );
    } on AuthReLoginException {
      await logout();
      rethrow;
    }
  }
  
  // Logout
  Future<void> logout() async {
    try {
      final refreshToken = await TokenVault.readRefresh();
      if (refreshToken != null) {
        await httpClient(
          method: 'POST',
          baseUrl: baseUrl,
          endpoint: 'api/auth/logout',
          body: {'refresh_token': refreshToken},
        );
      }
    } catch (e) {
      print('Logout request failed: $e');
    } finally {
      // Always clear local session
      Token.clear();
      await TokenVault.deleteRefresh();
    }
  }
  
  // Check if logged in
  bool get isLoggedIn => Token.isAuthenticated;
}
```

**Using in UI:**

```dart
// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ApiService();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await _apiService.getProfile();
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on AuthReLoginException {
      // Session expired - navigate to login
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $_error'),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Name: ${_profile!['name']}'),
          Text('Email: ${_profile!['email']}'),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await _apiService.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
```

### Pure Dart CLI Example

**Command-line tool with authentication:**

```dart
// bin/cli_app.dart
import 'dart:io';
import 'package:modular_api/modular_api.dart';

const baseUrl = 'https://api.example.com';

Future<String> _getPassphrase() async {
  return Platform.environment['MODULAR_API_PASSPHRASE'] ?? 'default-pass';
}

Future<void> main(List<String> args) async {
  // Configure storage
  TokenVault.configure(
    FileStorageAdapter.encrypted(passphraseProvider: _getPassphrase),
  );

  if (args.isEmpty) {
    print('Usage: dart run bin/cli_app.dart <command>');
    print('Commands: login, profile, logout');
    exit(1);
  }

  final command = args[0];

  try {
    switch (command) {
      case 'login':
        await handleLogin();
        break;
      case 'profile':
        await handleProfile();
        break;
      case 'logout':
        await handleLogout();
        break;
      default:
        print('Unknown command: $command');
        exit(1);
    }
  } on AuthReLoginException {
    print('\n❌ Session expired. Please login again.');
    exit(1);
  } catch (e) {
    print('\n❌ Error: $e');
    exit(1);
  }
}

Future<void> handleLogin() async {
  stdout.write('Username: ');
  final username = stdin.readLineSync() ?? '';
  
  stdout.write('Password: ');
  stdin.echoMode = false;
  final password = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  print('');

  final response = await httpClient(
    method: 'POST',
    baseUrl: baseUrl,
    endpoint: 'api/auth/login',
    body: {'username': username, 'password': password},
    auth: true,  // Auto-captures tokens
  );

  print('✅ Login successful!');
  print('   Token expires in: ${response['expires_in']} seconds');
}

Future<void> handleProfile() async {
  final profile = await httpClient(
    method: 'GET',
    baseUrl: baseUrl,
    endpoint: 'api/users/profile',
    auth: true,  // Auto-attaches Bearer token
  );

  print('📋 Profile:');
  print('   Name: ${profile['name']}');
  print('   Email: ${profile['email']}');
  print('   Role: ${profile['role']}');
}

Future<void> handleLogout() async {
  final refreshToken = await TokenVault.readRefresh();

  if (refreshToken != null) {
    await httpClient(
      method: 'POST',
      baseUrl: baseUrl,
      endpoint: 'api/auth/logout',
      body: {'refresh_token': refreshToken},
    );
  }

  Token.clear();
  await TokenVault.deleteRefresh();

  print('✅ Logged out successfully');
}
```

**Usage:**

```bash
# Set passphrase
export MODULAR_API_PASSPHRASE="my-secure-passphrase"

# Login
dart run bin/cli_app.dart login

# Get profile (auto refreshes token if expired)
dart run bin/cli_app.dart profile

# Logout
dart run bin/cli_app.dart logout
```

---

## API Reference

### httpClient Function

```dart
Future<dynamic> httpClient({
  required String method,        // HTTP method: 'GET', 'POST', 'PATCH'
  required String baseUrl,       // Base URL: 'https://api.example.com'
  required String endpoint,      // Endpoint path: 'api/users/profile'
  Map<String, String>? headers,  // Additional headers (optional)
  Map<String, dynamic>? body,    // Request body for POST/PATCH (optional)
  String errorMessage = 'Error in HTTP request',  // Custom error message
  bool auth = false,             // Enable authentication features
})
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `method` | `String` | Yes | HTTP method: `'GET'`, `'POST'`, or `'PATCH'` |
| `baseUrl` | `String` | Yes | Base URL without trailing slash |
| `endpoint` | `String` | Yes | Endpoint path without leading slash |
| `headers` | `Map<String, String>?` | No | Additional HTTP headers |
| `body` | `Map<String, dynamic>?` | No | Request body (auto-encoded as JSON) |
| `errorMessage` | `String` | No | Custom error message prefix |
| `auth` | `bool` | No | Enable auth features (default: `false`) |

**Returns:** `Future<dynamic>`
- Success: Parsed JSON response as `Map` or `List`
- Null: For empty responses

**Throws:**
- `AuthReLoginException`: When refresh fails (re-login required)
- `Exception`: For other errors (network, server errors, etc.)

### Token Class

In-memory access token storage.

```dart
class Token {
  static String? accessToken;    // Current JWT access token
  static DateTime? accessExp;    // Token expiration time
  
  static void clear();           // Clear session (logout)
  static bool get isAuthenticated;  // Has active token?
  static bool get isExpired;     // Is token expired?
}
```

### TokenVault Class

Secure refresh token storage.

```dart
class TokenVault {
  static void configure(TokenStorageAdapter adapter);
  static Future<void> saveRefresh(String token);      // Save refresh token (no userId needed)
  static Future<String?> readRefresh();               // Read refresh token
  static Future<void> deleteRefresh();                // Delete refresh token
  static Future<void> deleteAll();                    // Delete all tokens
}
```

### AuthReLoginException

Exception signaling re-login is required.

```dart
class AuthReLoginException implements Exception {
  final String message;
  AuthReLoginException([this.message = 'Re-login required']);
}
```

---

## Best Practices

### 1. Always Configure TokenVault at Startup

```dart
void main() {
  // ✅ Good: Configure before any httpClient calls
  TokenVault.configure(FlutterStorageAdapter());
  runApp(MyApp());
}

void main() {
  // ❌ Bad: Using httpClient with auth before configuring
  runApp(MyApp());
}
```

### 2. Single-User Architecture

The framework is optimized for single-user applications where only one user can be logged in at a time.

```dart
// ✅ Good: Simple single-user flow
await httpClient(..., auth: true);  // Login
await httpClient(..., auth: true);  // Protected request
Token.clear();                       // Logout
await TokenVault.deleteRefresh();

// ⚠️ Note: For multi-user apps (multiple simultaneous users),
// you'll need to implement custom user session management
```

### 3. Always Handle AuthReLoginException

```dart
// ✅ Good: Catch and handle re-login
try {
  await httpClient(..., auth: true);
} on AuthReLoginException {
  // Clear session and navigate to login
  Token.clear();
  await TokenVault.deleteRefresh();
  navigateToLogin();
} catch (e) {
  showError(e.toString());
}

// ❌ Bad: Generic catch misses re-login signal
try {
  await httpClient(..., auth: true);
} catch (e) {
  showError(e.toString());
}
```

### 4. Clean Up on Logout

```dart
// ✅ Good: Clear both memory and storage
Future<void> logout() async {
  try {
    // Call server logout
    await httpClient(..., endpoint: 'api/auth/logout');
  } finally {
    // Always clear local session
    Token.clear();
    await TokenVault.deleteRefresh();
  }
}

// ❌ Bad: Only clear one storage location
Future<void> logout() async {
  Token.clear(); // Forgot to clear TokenVault
}
```

### 5. Use Environment Variables for Secrets

```dart
// ✅ Good: Read from environment
Future<String> _getPassphrase() async {
  final pass = Platform.environment['MODULAR_API_PASSPHRASE'];
  if (pass == null) throw Exception('Passphrase not set');
  return pass;
}

// ❌ Bad: Hardcoded secrets
Future<String> _getPassphrase() async {
  return 'my-secret-passphrase'; // Never do this!
}
```

### 6. Set Proper Timeouts

```dart
// httpClient has built-in 30-second timeout
// For longer operations, implement retry logic:

Future<dynamic> longOperation() async {
  int retries = 0;
  while (retries < 3) {
    try {
      return await httpClient(...);
    } catch (e) {
      if (e.toString().contains('timeout') && retries < 2) {
        retries++;
        await Future.delayed(Duration(seconds: 2 * retries));
        continue;
      }
      rethrow;
    }
  }
}
```

### 7. Log Errors Appropriately

```dart
// ✅ Good: Differentiate error types
try {
  await httpClient(...);
} on AuthReLoginException catch (e) {
  logger.info('Session expired, user needs to log in');
  handleReLogin();
} catch (e, stackTrace) {
  logger.error('HTTP request failed', error: e, stackTrace: stackTrace);
  showError(e.toString());
}
```

---

## Troubleshooting

### Issue: "AuthReLoginException thrown immediately"

**Cause:** No refresh token stored or refresh token is invalid.

**Solution:**
1. Ensure user logged in successfully before making protected requests
2. Verify TokenVault is configured correctly
3. Check that login response contains valid tokens

```dart
// Debug: Check token storage
final refreshToken = await TokenVault.readRefresh();
print('Refresh token exists: ${refreshToken != null}');
print('Access token exists: ${Token.accessToken != null}');
```

### Issue: "Token not being attached to requests"

**Cause:** Missing `auth: true` parameter.

**Solution:**
```dart
// ✅ Correct
await httpClient(
  method: 'GET',
  baseUrl: baseUrl,
  endpoint: 'api/protected',
  auth: true,  // Enable auth
);

// ❌ Wrong: Missing auth parameter
await httpClient(
  method: 'GET',
  baseUrl: baseUrl,
  endpoint: 'api/protected',
  // Auth is false by default
);
```

### Issue: "Refresh loop or infinite retries"

**Cause:** Refresh endpoint itself returns 401.

**Solution:** Never use `auth: true` on refresh/logout endpoints:

```dart
// ✅ Correct: Refresh endpoint WITHOUT auth
await httpClient(
  method: 'POST',
  baseUrl: baseUrl,
  endpoint: 'api/auth/refresh',
  body: {'refresh_token': refreshToken},
  // NO auth: true here
);

// ❌ Wrong: Will cause refresh loop
await httpClient(
  method: 'POST',
  baseUrl: baseUrl,
  endpoint: 'api/auth/refresh',
  body: {'refresh_token': refreshToken},
  auth: true,  // Don't do this!
);
```

### Issue: "Token storage not persisting"

**Cause:** Using `MemoryStorageAdapter` (default) which is non-persistent.

**Solution:** Configure a persistent adapter:

```dart
// Flutter: Use flutter_secure_storage
TokenVault.configure(FlutterStorageAdapter());

// CLI/Server: Use encrypted file storage
TokenVault.configure(
  FileStorageAdapter.encrypted(passphraseProvider: _getPassphrase),
);
```

### Issue: "FileStorageAdapter: Passphrase exception"

**Cause:** Environment variable not set.

**Solution:**
```bash
# Linux/macOS
export MODULAR_API_PASSPHRASE="your-passphrase"

# Windows PowerShell
$env:MODULAR_API_PASSPHRASE="your-passphrase"

# Or in .env file
echo 'MODULAR_API_PASSPHRASE=your-passphrase' > .env
```

### Issue: "Connection timeout errors"

**Cause:** Network issues or slow server.

**Solutions:**
1. Check network connectivity
2. Verify baseUrl is correct
3. Ensure server is running and accessible
4. Implement retry logic for transient failures

```dart
Future<dynamic> retryRequest(Future<dynamic> Function() request) async {
  int attempts = 0;
  while (attempts < 3) {
    try {
      return await request();
    } catch (e) {
      attempts++;
      if (attempts >= 3 || !e.toString().contains('timeout')) {
        rethrow;
      }
      await Future.delayed(Duration(seconds: attempts * 2));
    }
  }
}

// Usage
final data = await retryRequest(() => httpClient(...));
```

### Issue: "Mixed user sessions"

**Note:** The framework is designed for single-user applications (v0.0.7+). If you need multi-user support (multiple users logged in simultaneously), you'll need to implement custom session management.

For single-user apps, ensure proper logout:

```dart
Future<void> switchUser(String newUsername, String newPassword) async {
  // First, logout current user
  Token.clear();
  await TokenVault.deleteRefresh();
  
  // Then login new user
  await httpClient(
    method: 'POST',
    baseUrl: baseUrl,
    endpoint: 'api/auth/login',
    body: {'username': newUsername, 'password': newPassword},
    auth: true,
  );
}
```

---

## Summary

`httpClient` simplifies HTTP requests with authentication for single-user applications:

**Key Points:**
- Configure `TokenVault` once at app startup
- Use `auth: true` for authenticated requests (no user parameter needed)
- Login automatically captures and stores tokens
- 401 errors trigger automatic token refresh and retry
- Catch `AuthReLoginException` to detect when re-login is needed
- Always clear both `Token` and `TokenVault` on logout
- Optimized for single-user applications (one user at a time)

**Common Pattern:**
```dart
// 1. Configure storage (once at startup)
TokenVault.configure(YourAdapter());

// 2. Login
await httpClient(..., endpoint: 'auth/login', auth: true);

// 3. Make protected requests (auto token + auto refresh)
try {
  await httpClient(..., auth: true);
} on AuthReLoginException {
  // Navigate to login
}

// 4. Logout
Token.clear();
await TokenVault.deleteRefresh();
```

For more examples, see:
- [E2E Tests](../template/test/e2e/auth_flow_test.dart)
- [Authentication Implementation Guide](./auth_implementation_guide.md)
- [Testing Guide](./testing_guide.md)

---

**Questions or Issues?**

If you encounter problems not covered in this guide:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review E2E test examples in `template/test/e2e/`
3. Open an issue on GitHub with details about your setup and error messages
