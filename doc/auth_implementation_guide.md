# Authentication Implementation Guide for modular_api

This guide explains how to implement a full JWT authentication system with refresh tokens using `modular_api`.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Overview](#system-overview)
3. [Database Setup](#database-setup)
4. [Required Dependencies](#required-dependencies)
5. [File Layout](#file-layout)
6. [Step-by-step Implementation](#step-by-step-implementation)
7. [Client Usage (Flutter / Dart)](#client-usage-flutter--dart)
  - [Option 1: Using httpClient (Recommended)](#option-1-using-httpclient-recommended)
  - [Option 2: Manual http (Traditional)](#option-2-manual-http-traditional)
8. [Testing](#testing)
  - [UseCase Unit Tests](#usecase-unit-tests)
  - [E2E Tests with httpClient](#e2e-tests-with-httpclient)
  - [Testing Patterns with httpClient](#testing-patterns-with-httpclient)
9. [Security and Best Practices](#security-and-best-practices)

---

## Prerequisites

- Dart SDK 3.8.1 or newer
- PostgreSQL 12 or newer
- Basic knowledge of JWT
- Basic SQL knowledge

---

## System Overview

The authentication system implements:

- ✅ **Login**: Authenticate with username/password → returns access token + refresh token
- ✅ **Refresh**: Exchange a refresh token for a new access token
- ✅ **Logout**: Revoke a specific refresh token (log out a device/session)
- ✅ **Logout All**: Revoke all refresh tokens for a user (log out all sessions)
- ✅ **Token Rotation**: Optional; issue a new refresh token on each refresh for extra security
- ✅ **Password Hashing**: bcrypt with cost factor 12
- ✅ **Token Storage**: SHA-256 hashes stored in the database

### Token Flow

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       │ 1. POST /api/auth/login
       │    {username, password}
       ▼
┌─────────────────────────────┐
│         Server              │
│  ┌─────────────────────┐    │
│  │ LoginUseCase        │    │
│  │ - Verify credentials│    │
│  │ - Generate tokens   │    │
│  │ - Save hash         │    │
│  └─────────────────────┘    │
└──────┬──────────────────────┘
       │
       │ 2. Response: {access_token, refresh_token, expires_in}
       ▼
┌─────────────┐
│   Client    │
│ Stores both │
│   tokens    │
└──────┬──────┘
       │
       │ (15 minutes later, access token expires)
       │
       │ 3. POST /api/auth/refresh
       │    {refresh_token}
       ▼
┌─────────────────────────────┐
│         Server              │
│  ┌─────────────────────┐   │
│  │ RefreshUseCase      │   │
│  │ - Verify token      │   │
│  │ - Check DB hash     │   │
│  │ - Generate new AT   │   │
│  │ - (Rotate RT)       │   │
│  └─────────────────────┘   │
└──────┬──────────────────────┘
       │
       │ 4. Response: {access_token, [refresh_token], expires_in}
       ▼
┌─────────────┐
│   Client    │
│  Updates    │
│   tokens    │
└─────────────┘
```

---

## Database Setup

### 1. Create the Schema

```sql
-- Create schema auth
CREATE SCHEMA IF NOT EXISTS auth;
```

### 2. Table: auth.user

Stores basic user information.

```sql
CREATE TABLE auth.user (
  id               INTEGER GENERATED ALWAYS AS IDENTITY,
  username         VARCHAR(16)     NOT NULL,
  full_name        VARCHAR(250)    NOT NULL,
  created_at       TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

  -- Constraints
  CONSTRAINT user_username_key UNIQUE (username),
  CONSTRAINT user_pkey PRIMARY KEY (id)
);

-- Indexes
CREATE INDEX ix_user_username   ON auth.user(username);
CREATE INDEX ix_user_full_name  ON auth.user(full_name);
```

**Fields:**
- `id`: Unique identifier (auto-increment)
- `username`: Unique username (3-16 characters recommended)
- `full_name`: User full name
- `created_at`: Creation timestamp

### 3. Table: auth.password

Stores password hashes (bcrypt).

```sql
CREATE TABLE auth.password (
  id                  INTEGER GENERATED ALWAYS AS IDENTITY,
  id_user             INTEGER NOT NULL,
  password_hash       VARCHAR(255) NOT NULL,
  created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT password_id_user_fkey FOREIGN KEY (id_user) 
    REFERENCES auth.user(id) ON DELETE CASCADE,
  CONSTRAINT password_id_user_unique UNIQUE (id_user),
  CONSTRAINT password_pkey PRIMARY KEY (id)
);

-- Index
CREATE INDEX ix_password_id_user ON auth.password(id_user);
```

**Fields:**
- `id`: Unique identifier
- `id_user`: Reference to the user (FK)
- `password_hash`: bcrypt hash of the password (60 characters)
- `created_at`: Creation timestamp
- `updated_at`: Last update timestamp

**IMPORTANT**: 1:1 relation with `auth.user` (one user, one password).

### 4. Table: auth.refresh_token

Stores refresh token hashes and an audit trail.

```sql
CREATE TABLE auth.refresh_token (
  id               INTEGER GENERATED ALWAYS AS IDENTITY,
  id_user          INTEGER NOT NULL,
  token_hash       VARCHAR(255) NOT NULL,
  previous_id      INTEGER NULL,
  revoked          BOOLEAN DEFAULT FALSE,
  created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at       TIMESTAMP NOT NULL,
  
  CONSTRAINT refresh_token_id_user_fkey FOREIGN KEY (id_user) 
    REFERENCES auth.user(id) ON DELETE CASCADE,
  CONSTRAINT refresh_token_previous_id_fkey FOREIGN KEY (previous_id) 
    REFERENCES auth.refresh_token(id) ON DELETE SET NULL,
  CONSTRAINT refresh_token_pkey PRIMARY KEY (id)
);

-- Indexes
CREATE INDEX ix_refresh_token_user ON auth.refresh_token(id_user);
CREATE INDEX ix_refresh_token_hash ON auth.refresh_token(token_hash);
CREATE INDEX ix_refresh_token_revoked ON auth.refresh_token(revoked);
```

**Fields:**
- `id`: Unique identifier (included in JWT as `jti`)
- `id_user`: Reference to the user (FK)
- `token_hash`: SHA-256 hash of the refresh token (64 hex chars)
- `previous_id`: Previous token ID (for token rotation chain)
- `revoked`: Indicates if the token was revoked (soft delete)
- `created_at`: Token creation timestamp
- `expires_at`: Token expiration timestamp (7 days by default)

**Relation 1:N with `auth.user`**: A user can have multiple active refresh tokens (multiple devices/sessions).

### 5. Seed Data (Example)

```sql
-- Example users
INSERT INTO auth.user (username, full_name) VALUES
  ('example', 'Example User'),
  ('admin', 'Administrator User'),
  ('testuser', 'Test User Demo');

-- Passwords (bcrypt hashes)
-- example: abc123
-- admin: password123
-- testuser: password123
INSERT INTO auth.password (id_user, password_hash) VALUES
  (1, '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYHNqJzS0yG'),
  (2, '$2b$12$fR8Qg3JZ0Ih7LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5'),
  (3, '$2b$12$fR8Qg3JZ0Ih7LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5');
```

---

## Required Dependencies

### Server (Dart Backend)

Add to `pubspec.yaml`:

```yaml
dependencies:
  modular_api: ^0.0.7       # Complete framework includes:
                            # - UseCase pattern
                            # - httpClient with auto-auth
                            # - JwtHelper, PasswordHasher, TokenHasher
                            # - bcrypt, dart_jsonwebtoken, crypto
  postgres: ^3.0.0          # PostgreSQL client
  
dev_dependencies:
  test: ^1.24.0             # Testing
  http: ^1.5.0              # HTTP client for E2E tests
```

### Flutter Client

Add to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  modular_api: ^0.0.7                 # Includes httpClient, Token, TokenVault, etc.
  flutter_secure_storage: ^9.2.2     # Secure token storage
  http: ^1.5.0                        # HTTP client (fallback if not using httpClient)
```

**IMPORTANT**: If you use the bundled `httpClient` (recommended), you don't need `package:http` in your Flutter client — `httpClient` handles HTTP requests for you.

### Pure Dart Server (No Flutter)

For pure Dart servers or CLIs, `modular_api` includes `FileStorageAdapter` to store tokens on disk:

```yaml
dependencies:
  modular_api: ^0.0.7
  postgres: ^3.0.0
```

Configure TokenVault with FileStorage:

```dart
import 'package:modular_api/modular_api.dart';

void main() {
  // FileStorageAdapter is included in modular_api
  // By default it saves tokens under a .tokens/ directory

  runApp();
}
```

---

## File Layout

```
lib/
├── db/
│   └── postgres_client.dart          # PostgreSQL client
└── modules/
    └── auth/
        ├── auth_builder.dart         # Endpoint registration
        ├── auth_repository.dart      # DB operations
        └── usecases/
            ├── login.dart            # POST /auth/login
            ├── refresh.dart          # POST /auth/refresh
            ├── logout.dart           # POST /auth/logout
            └── logout_all.dart       # POST /auth/logout_all

db/
└── auth/
    ├── auth.sql                      # Complete schema
    └── tables/
        ├── user.sql
        ├── password.sql
        └── refreshToken.sql

test/
└── auth/
    ├── login_test.dart
    ├── refresh_test.dart
    ├── logout_test.dart
    ├── logout_all_test.dart
    └── auth_repository_test.dart
```

---

## Step-by-step Implementation

### Step 1: Core Utilities

**IMPORTANT**: The `JwtHelper` and `PasswordHasher` utilities are included in the `modular_api` package since version 0.0.7. You only need to import them:

```dart
import 'package:modular_api/modular_api.dart';

// You now have access to:
// - JwtHelper: JWT generation and validation
// - JwtException: Exception for JWT errors
// - PasswordHasher: Password hashing and verification with bcrypt
```

#### 1.1 JwtHelper (included in modular_api)

The `JwtHelper` included in the framework provides:

**Methods:**
- `generateAccessToken({required int userId, required String username})` - Generate access token (15 min)
- `generateRefreshToken({required int userId, required int tokenId})` - Generate refresh token (7 days)
- `verifyToken(String token)` - Verify and decode a JWT token
- `calculateRefreshTokenExpiration()` - Calculate refresh token expiration date
- `accessTokenExpiresIn` - Getter for access token expiration time (in seconds)

**Configuration:**
- `JwtHelper` reads the JWT secret from the `JWT_SECRET` environment variable
- Access tokens: 15 minutes duration
- Refresh tokens: 7 days duration

**Usage example:**
```dart
// Generate access token
final accessToken = JwtHelper.generateAccessToken(
  userId: 1,
  username: 'example',
);

// Generate refresh token
final refreshToken = JwtHelper.generateRefreshToken(
  userId: 1,
  tokenId: 123,
);

// Verify token
try {
  final payload = JwtHelper.verifyToken(accessToken);
  print('User ID: ${payload['sub']}');
  print('Type: ${payload['type']}'); // 'access' or 'refresh'
} on JwtException catch (e) {
  print('Invalid token: $e');
}
```

#### 1.2 PasswordHasher (included in modular_api)

The `PasswordHasher` included in the framework provides:

**Methods:**
- `hash(String password, {int cost = 12})` - Generate bcrypt hash of password
- `verify(String password, String hash)` - Verify password against hash
- `needsRehash(String hash, {int cost = 12})` - Determine if hash needs updating

#### 1.3 TokenHasher (included in modular_api)

The `TokenHasher` included in the framework provides secure SHA-256 hashing for storing tokens:

**Methods:**
- `hash(String token)` - Generate SHA-256 hash of token (64 hexadecimal characters)
- `verify(String token, String expectedHash)` - Verify token against stored hash

**Purpose:**
Refresh tokens should be stored hashed in the database for security. If the database is compromised, original tokens cannot be recovered from the hash.

**Usage example:**
```dart
// Hash refresh token before saving to DB
final refreshToken = JwtHelper.generateRefreshToken(
  userId: userId,
  tokenId: tokenId,
);
final hashedToken = TokenHasher.hash(refreshToken);

await repo.saveRefreshToken(
  userId: userId,
  hash: hashedToken,
  expiresAt: expiresAt,
);

// Verify received token against stored hash
final incomingTokenHash = TokenHasher.hash(receivedToken);
final storedToken = await repo.getRefreshToken(incomingTokenHash);

// Or use convenience method
if (TokenHasher.verify(receivedToken, storedToken.hash)) {
  // Valid token
}
```

**Configuration:**
- Default cost factor: 12 (adjustable depending on hardware)
- Uses bcrypt internally

**Usage example:**
```dart
// Hash password
final hash = PasswordHasher.hash('abc123');
// $2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYHNqJzS0yG

// Verify password
final isValid = PasswordHasher.verify('abc123', hash);
print(isValid); // true

// Check if rehash needed (e.g., if cost factor changed)
final needsUpdate = PasswordHasher.needsRehash(hash, cost: 13);
```

**Advantages of using included utilities:**
- ✅ No additional dependencies (already in modular_api)
- ✅ Secure default configuration
- ✅ Documented and tested
- ✅ Compatible with rest of framework
- ✅ Maintained and updated with package

### Step 2: Repository

#### 2.1 Auth Repository (`lib/modules/auth/auth_repository.dart`)

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:modular_api/modular_api.dart';  // Import JwtHelper and PasswordHasher
import '../../db/postgres_client.dart';

class AuthRepository {
  final PostgresClient _db;

  AuthRepository(this._db);

  /// Get user by username
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final results = await _db.query(
      '''
      SELECT id, username, full_name, created_at
      FROM auth.user
      WHERE username = @username
      ''',
      {'username': username},
    );
    return results.isEmpty ? null : results.first;
  }

  /// Verify password
  Future<bool> verifyPassword(int userId, String password) async {
    final results = await _db.query(
      '''
      SELECT password_hash
      FROM auth.password
      WHERE id_user = @userId
      ''',
      {'userId': userId},
    );

    if (results.isEmpty) return false;

    final storedHash = results.first['password_hash'] as String;
    return PasswordHasher.verify(password, storedHash);
  }

  /// Authenticate user
  Future<Map<String, dynamic>?> authenticate(
    String username,
    String password,
  ) async {
    final user = await getUserByUsername(username);
    if (user == null) return null;

    final userId = user['id'] as int;
    final isValid = await verifyPassword(userId, password);
    
    return isValid ? user : null;
  }

  /// Save refresh token
  Future<int> saveRefreshToken({
    required int userId,
    required String tokenHash,
    required DateTime expiresAt,
    int? previousId,
  }) async {
    final results = await _db.query(
      '''
      INSERT INTO auth.refresh_token (id_user, token_hash, expires_at, previous_id)
      VALUES (@userId, @tokenHash, @expiresAt, @previousId)
      RETURNING id
      ''',
      {
        'userId': userId,
        'tokenHash': tokenHash,
        'expiresAt': expiresAt.toIso8601String(),
        'previousId': previousId,
      },
    );
    return results.first['id'] as int;
  }

  /// Get refresh token by hash
  Future<Map<String, dynamic>?> getRefreshToken(String tokenHash) async {
    final results = await _db.query(
      '''
      SELECT id, id_user, token_hash, revoked, expires_at, created_at
      FROM auth.refresh_token
      WHERE token_hash = @tokenHash
        AND revoked = false
      ''',
      {'tokenHash': tokenHash},
    );
    return results.isEmpty ? null : results.first;
  }

  /// Revoke refresh token
  Future<void> revokeRefreshToken(int tokenId) async {
    await _db.execute(
      '''
      UPDATE auth.refresh_token
      SET revoked = true
      WHERE id = @tokenId
      ''',
      {'tokenId': tokenId},
    );
  }

  /// Revoke all tokens for a user
  Future<void> revokeAllUserTokens(int userId) async {
    await _db.execute(
      '''
      UPDATE auth.refresh_token
      SET revoked = true
      WHERE id_user = @userId
        AND revoked = false
      ''',
      {'userId': userId},
    );
  }

  /// Count active tokens for a user
  Future<int> countActiveUserTokens(int userId) async {
    final results = await _db.query(
      '''
      SELECT COUNT(*) as count
      FROM auth.refresh_token
      WHERE id_user = @userId
        AND revoked = false
      ''',
      {'userId': userId},
    );
    return results.first['count'] as int;
  }
}
```

### Step 3: Use Cases

#### 3.1 Login (`lib/modules/auth/usecases/login.dart`)

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:modular_api/modular_api.dart';  // Import UseCase, Input, Output, JwtHelper
import '../../../db/postgres_client.dart';
import '../auth_repository.dart';

class LoginInput implements Input {
  final String username;
  final String password;

  LoginInput({required this.username, required this.password});

  factory LoginInput.fromJson(Map<String, dynamic> json) {
    return LoginInput(
      username: json['username'] as String,
      password: json['password'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
      };

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'username': {
          'type': 'string',
          'description': 'Username (3-16 characters)',
          'minLength': 3,
          'maxLength': 16,
        },
        'password': {
          'type': 'string',
          'description': 'Password (minimum 6 characters)',
          'minLength': 6,
        },
      },
      'required': ['username', 'password'],
    };
  }
}

class LoginOutput implements Output {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String refreshToken;

  LoginOutput({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshToken,
  });

  factory LoginOutput.fromJson(Map<String, dynamic> json) {
    return LoginOutput(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'token_type': tokenType,
        'expires_in': expiresIn,
        'refresh_token': refreshToken,
      };

  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'access_token': {
          'type': 'string',
          'description': 'JWT access token',
        },
        'token_type': {
          'type': 'string',
          'description': 'Token type',
          'enum': ['Bearer'],
        },
        'expires_in': {
          'type': 'integer',
          'description': 'Access token expiration time in seconds',
        },
        'refresh_token': {
          'type': 'string',
          'description': 'JWT refresh token',
        },
      },
      'required': ['access_token', 'token_type', 'expires_in', 'refresh_token'],
    };
  }
}

class LoginUseCase extends UseCase<LoginInput, LoginOutput> {
  LoginUseCase(super.input);

  final PostgresClient _db = PostgresClient();
  late final AuthRepository _repository = AuthRepository(_db);

  static LoginUseCase factory(Map<String, dynamic> json) {
    return LoginUseCase(LoginInput.fromJson(json));
  }

  @override
  String? validate() {
    if (input.username.isEmpty) {
      return 'Username cannot be empty';
    }
    if (input.username.length < 3 || input.username.length > 16) {
      return 'Username must be between 3 and 16 characters';
    }
    if (input.password.isEmpty) {
      return 'Password cannot be empty';
    }
    if (input.password.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  @override
  Future<LoginOutput> execute() async {
    // Authenticate user
    final user = await _repository.authenticate(
      input.username,
      input.password,
    );

    if (user == null) {
      throw ArgumentError('Invalid username or password');
    }

    final userId = user['id'] as int;
    final username = user['username'] as String;

    // Generate access token
    final accessToken = JwtHelper.generateAccessToken(
      userId: userId,
      username: username,
    );

    // Generate refresh token (first save to DB to get ID)
    final tokenHash = sha256.convert(utf8.encode(DateTime.now().toString())).toString();
    final expiresAt = JwtHelper.calculateRefreshTokenExpiration();
    
    final tokenId = await _repository.saveRefreshToken(
      userId: userId,
      tokenHash: tokenHash,
      expiresAt: expiresAt,
    );

    final refreshToken = JwtHelper.generateRefreshToken(
      userId: userId,
      tokenId: tokenId,
    );

    // Update token hash in DB
    final actualTokenHash = sha256.convert(utf8.encode(refreshToken)).toString();
    await _db.execute(
      'UPDATE auth.refresh_token SET token_hash = @hash WHERE id = @id',
      {'hash': actualTokenHash, 'id': tokenId},
    );

    return LoginOutput(
      accessToken: accessToken,
      tokenType: 'Bearer',
      expiresIn: JwtHelper.accessTokenExpiresIn,
      refreshToken: refreshToken,
    );
  }

  @override
  Map<String, dynamic> toJson() => output.toJson();
}
```

#### 3.2 Refresh (`lib/modules/auth/usecases/refresh.dart`)

```dart
// Similar structure to Login
// Implements optional token rotation and refresh token validation
```

#### 3.3 Logout and Logout All

Implement these following similar patterns to Login and Refresh.

### Step 4: Register Module

#### 4.1 Auth Builder (`lib/modules/auth/auth_builder.dart`)

```dart
import 'package:modular_api/modular_api.dart';
import 'usecases/login.dart';
import 'usecases/refresh.dart';
import 'usecases/logout.dart';
import 'usecases/logout_all.dart';

void buildAuthModule(ModuleBuilder m) {
  m.usecase('login', LoginUseCase.factory);
  m.usecase('refresh', RefreshUseCase.factory);
  m.usecase('logout', LogoutUseCase.factory);
  m.usecase('logout_all', LogoutAllUseCase.factory);
}
```

#### 4.2 Register in ModularApi (`bin/main.dart`)

```dart
import 'package:modular_api/modular_api.dart';
import '../lib/modules/auth/auth_builder.dart';

Future<void> main() async {
  final api = ModularApi(basePath: '/api');

  // Register auth module
  api.module('auth', buildAuthModule);

  // Middlewares
  api.use(cors());
  api.use(apiKey()); // Optional

  await api.serve(port: 3456);
  print('🚀 Server running at http://localhost:3456');
  print('📚 API Docs at http://localhost:3456/docs');
}
```

### Step 5: Environment Variables

Create `.env` file:

```env
# Server
PORT=3456

# Database
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=your_database
POSTGRES_USER=your_user
POSTGRES_PASSWORD=your_password

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-in-production
JWT_EXPIRES_IN=900
REFRESH_TOKEN_DAYS=7
```

**IMPORTANT**: Generate a secure key for JWT:
```bash
openssl rand -base64 32
```

---

## Usage from Client (Flutter/Dart)

`modular_api` includes an intelligent HTTP client called `httpClient` that significantly simplifies interaction with authenticated endpoints. This client automatically handles:

- ✅ Attaching authorization tokens
- ✅ Capturing and storing login tokens
- ✅ Automatic retry with refresh token on 401
- ✅ Throwing `AuthReLoginException` when re-login is required

### Option 1: Using httpClient (Recommended) 🌟

The `httpClient` is included in `package:modular_api/modular_api.dart` and provides a simplified API with automatic authentication handling.

#### httpClient Features

**Signature:**
```dart
Future<dynamic> httpClient({
  required String method,
  required String baseUrl,
  required String endpoint,
  Map<String, String>? headers,
  Map<String, dynamic>? body,
  String? errorMessage,
  bool auth = false,
})
```

**Parameters:**
- `method`: HTTP method ('GET', 'POST', 'PATCH')
- `baseUrl`: Server base URL (e.g., 'http://localhost:3456')
- `endpoint`: Relative endpoint (e.g., 'api/auth/login')
- `headers`: Optional additional headers
- `body`: JSON request body (for POST/PATCH)
- `errorMessage`: Custom error message
- `auth`: If `true`, automatically attaches Bearer token and manages refresh (user managed by `SessionManager`)

**Return:**
- Returns parsed body as `Map<String, dynamic>` or `List` depending on response
- Throws `Exception` if status code != 2xx
- Throws `AuthReLoginException` if refresh fails (signal for re-login)

**Note:** For single-user applications, `httpClient` uses `SessionManager` internally to track the authenticated user. Call `SessionManager.setUser(userId)` after successful login.

#### Step 1: Configure TokenVault

`TokenVault` is the persistent storage for refresh tokens. For Flutter, use `FlutterSecureStorageAdapter`:

Create `lib/auth/flutter_secure_storage_adapter.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Adapter for TokenVault using FlutterSecureStorage
class FlutterTokenVault {
  static final _storage = const FlutterSecureStorage();

  static Future<void> saveRefresh(String userId, String token) =>
      _storage.write(key: 'refresh_token_$userId', value: token);

  static Future<String?> readRefresh(String userId) =>
      _storage.read(key: 'refresh_token_$userId');

  static Future<void> deleteRefresh(String userId) =>
      _storage.delete(key: 'refresh_token_$userId');

  static Future<void> deleteAll() => _storage.deleteAll();
}
```

Initialize TokenVault in your app:

```dart
import 'package:modular_api/modular_api.dart';
import 'auth/flutter_secure_storage_adapter.dart';

void main() {
  // Configure TokenVault with Flutter adapter
  TokenVault.saveRefresh = FlutterTokenVault.saveRefresh;
  TokenVault.readRefresh = FlutterTokenVault.readRefresh;
  TokenVault.deleteRefresh = FlutterTokenVault.deleteRefresh;

  runApp(MyApp());
}
```

#### Step 2: Implement AuthService with httpClient

Create `lib/auth/auth_service.dart`:

```dart
import 'package:modular_api/modular_api.dart';

class AuthService {
  final String baseUrl;

  AuthService({required this.baseUrl});

  /// Login - httpClient automatically captures and stores tokens
  Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    try {
      final body = await httpClient(
        method: 'POST',
        baseUrl: baseUrl,
        endpoint: 'api/auth/login',
        body: {
          'username': username,
          'password': password,
        },
        auth: true,  // Enable automatic token capture
      ) as Map<String, dynamic>;

      return LoginResponse(
        accessToken: body['access_token'] as String,
        tokenType: body['token_type'] as String,
        expiresIn: body['expires_in'] as int,
        refreshToken: body['refresh_token'] as String,
      );
    } on AuthReLoginException {
      throw AuthException('Re-login required');
    } catch (e) {
      throw AuthException('Login failed: $e');
    }
  }

  /// Logout - Revoke refresh token on server and clear local session
  Future<void> logout() async {
    try {
      final refreshToken = await TokenVault.readRefresh('current_user');
      if (refreshToken != null) {
        await httpClient(
          method: 'POST',
          baseUrl: baseUrl,
          endpoint: 'api/auth/logout',
          body: {'refresh_token': refreshToken},
          auth: true,
        );
      }
    } catch (e) {
      // Continue even if server fails
    } finally {
      await TokenVault.deleteRefresh('current_user');
      Token.clear();
    }
  }

  /// Logout from all sessions
  Future<void> logoutAll() async {
    try {
      final refreshToken = await TokenVault.readRefresh('current_user');
      if (refreshToken != null) {
        await httpClient(
          method: 'POST',
          baseUrl: baseUrl,
          endpoint: 'api/auth/logout_all',
          body: {'refresh_token': refreshToken},
          auth: true,
        );
      }
    } catch (e) {
      // Continue
    } finally {
      await TokenVault.deleteRefresh('current_user');
      Token.clear();
    }
  }

  /// Authenticated request - httpClient handles tokens automatically
  Future<dynamic> authenticatedRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
  }) async {
    try {
      return await httpClient(
        method: method,
        baseUrl: baseUrl,
        endpoint: endpoint,
        body: body,
        auth: true,  // Attach Bearer token automatically
      );
    } on AuthReLoginException {
      throw AuthException('Session expired - please login again');
    }
  }

  /// Check if authenticated (has access token in memory)
  bool get isAuthenticated => Token.isAuthenticated;

  /// Clear all session data
  Future<void> clearSession() async {
    await TokenVault.deleteRefresh('current_user');
    Token.clear();
  }
}

class LoginResponse {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String refreshToken;

  LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshToken,
  });
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
```

#### Step 3: Usage in Flutter

```dart
import 'package:modular_api/modular_api.dart';
import 'auth/auth_service.dart';

// Initialize
final authService = AuthService(baseUrl: 'http://localhost:3456');

// Login - httpClient automatically captures tokens
try {
  final response = await authService.login(
    username: 'example',
    password: 'abc123',
  );
  print('✅ Login successful! Token expires in ${response.expiresIn}s');
} on AuthException catch (e) {
  print('❌ Login failed: $e');
}

// Request to protected endpoint - Automatic auth handling
try {
  final profile = await authService.authenticatedRequest(
    method: 'POST',
    endpoint: 'api/users/profile',
    body: {'user_id': 123},
  );
  print('Profile: $profile');
} on AuthException catch (e) {
  // Session expired, redirect to login
  print('Session expired: $e');
  // Navigator.pushReplacementNamed(context, '/login');
}

// Logout
await authService.logout();

// Logout from all sessions
await authService.logoutAll();
```

#### Advantages of httpClient

✅ **Cleaner code**: No need to handle headers manually  
✅ **Auto-refresh**: Automatically retries with refresh token on 401  
✅ **Automatic capture**: Login captures and saves tokens without extra code  
✅ **Single-user optimized**: Uses internal key for token storage - no user management needed  
✅ **Error handling**: `AuthReLoginException` signals when re-login is needed  
✅ **Type-safe**: Returns parsed JSON directly  

#### httpClient Flow with auth=true

```
┌─────────────────────────────────────────────────────────────┐
│ httpClient(auth=true, ...)                                  │
│ (Single-user design with internal 'current_user' key)      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
         Does Token.accessToken exist in memory?
                         │
           ┌─────────────┴─────────────┐
           │ YES                       │ NO
           ▼                           ▼
   Attach Bearer token      Is endpoint /auth/login?
   in Authorization              │
           │                ┌────┴────┐
           │                │ YES     │ NO
           │                ▼         ▼
           │          Continue    Continue
           │                │         │
           ▼                ▼         ▼
   Execute HTTP request
           │
           ▼
    Status 200 + /auth/login?
           │
      ┌────┴────┐
      │ YES     │ NO
      ▼         ▼
  Capture   Continue
  tokens      │
      │       │
      ▼       │
  Token.accessToken = access    │
  TokenVault.saveRefresh('current_user', refresh)
      │       │
      └───────┴────────┐
                       │
                       ▼
                Status 200?
                       │
            ┌──────────┴──────────┐
            │ YES                │ NO (401)
            ▼                    ▼
        Return JSON      Try POST /auth/refresh
                         with TokenVault.readRefresh('current_user')
                                │
                          Refresh OK?
                                │
                              ┌─────────┴─────────┐
                              │ YES               │ NO
                              ▼                   ▼
                        Update tokens           Throw
                        Retry request      AuthReLoginException
                              │
                        Return JSON
```

### Option 2: Using Manual HTTP (Traditional)

If you prefer to handle tokens manually without `httpClient`, you can use the traditional approach with `package:http`.

<details>
<summary>View manual implementation with package:http</summary>

#### Step 1: Create Adapter for Flutter Secure Storage

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FlutterSecureStorageAdapter {
  FlutterSecureStorageAdapter({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) : _storage = FlutterSecureStorage(
          iOptions: iOptions,
          aOptions: aOptions,
          lOptions: lOptions,
          mOptions: mOptions,
          wOptions: wOptions,
          webOptions: webOptions,
        );

  final FlutterSecureStorage _storage;

  Future<void> saveRefresh(String userId, String token) =>
      _storage.write(key: 'refresh_token_$userId', value: token);

  Future<String?> readRefresh(String userId) =>
      _storage.read(key: 'refresh_token_$userId');

  Future<void> deleteRefresh(String userId) =>
      _storage.delete(key: 'refresh_token_$userId');

  Future<void> deleteAll() => _storage.deleteAll();

  Future<void> saveAccess(String userId, String token) =>
      _storage.write(key: 'access_token_$userId', value: token);

  Future<String?> readAccess(String userId) =>
      _storage.read(key: 'access_token_$userId');
}
```

#### Step 2: Manual Authentication Service

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'flutter_secure_storage_adapter.dart';

class AuthService {
  final String baseUrl;
  final FlutterSecureStorageAdapter _storage;
  String? _currentUserId;
  String? _currentAccessToken;

  AuthService({
    required this.baseUrl,
    FlutterSecureStorageAdapter? storage,
  }) : _storage = storage ?? FlutterSecureStorageAdapter();

  Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      throw AuthException('Login failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final loginResponse = LoginResponse.fromJson(data);

    final userId = _extractUserIdFromToken(loginResponse.accessToken);
    await _storage.saveAccess(userId, loginResponse.accessToken);
    await _storage.saveRefresh(userId, loginResponse.refreshToken);

    _currentUserId = userId;
    _currentAccessToken = loginResponse.accessToken;

    return loginResponse;
  }

  Future<void> refreshToken() async {
    if (_currentUserId == null) {
      throw AuthException('No user logged in');
    }

    final refreshToken = await _storage.readRefresh(_currentUserId!);
    if (refreshToken == null) {
      throw AuthException('No refresh token found');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    if (response.statusCode != 200) {
      throw AuthException('Token refresh failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final newAccessToken = data['access_token'] as String;
    await _storage.saveAccess(_currentUserId!, newAccessToken);
    _currentAccessToken = newAccessToken;

    if (data.containsKey('refresh_token')) {
      final newRefreshToken = data['refresh_token'] as String;
      await _storage.saveRefresh(_currentUserId!, newRefreshToken);
    }
  }

  Future<void> logout() async {
    if (_currentUserId == null) return;

    final refreshToken = await _storage.readRefresh(_currentUserId!);
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        );
      } catch (e) {
        // Continue even if it fails
      }
    }

    await _storage.deleteRefresh(_currentUserId!);
    await _storage.deleteAccess(_currentUserId!);
    _currentUserId = null;
    _currentAccessToken = null;
  }

  Future<String?> getAccessToken() async {
    if (_currentAccessToken != null) {
      if (_isTokenExpiringSoon(_currentAccessToken!)) {
        await refreshToken();
      }
      return _currentAccessToken;
    }
    return null;
  }

  Future<http.Response> authenticatedRequest({
    required String method,
    required String path,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final token = await getAccessToken();
    if (token == null) {
      throw AuthException('Not authenticated');
    }

    final allHeaders = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      ...?headers,
    };

    final uri = Uri.parse('$baseUrl$path');

    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri, headers: allHeaders);
      case 'POST':
        return http.post(uri, headers: allHeaders, body: body);
      case 'PUT':
        return http.put(uri, headers: allHeaders, body: body);
      case 'DELETE':
        return http.delete(uri, headers: allHeaders, body: body);
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }

  String _extractUserIdFromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw AuthException('Invalid token format');
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final data = jsonDecode(decoded) as Map<String, dynamic>;
    return data['sub'] as String;
  }

  bool _isTokenExpiringSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = data['exp'] as int;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      final now = DateTime.now();
      return expiresAt.difference(now).inSeconds < 60;
    } catch (e) {
      return true;
    }
  }
}

class LoginResponse {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String refreshToken;

  LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshToken,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String,
    );
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}
```

</details>

---

## Testing

### Unit Testing (UseCase Level)

To test UseCases individually, use `useCaseTestHandler`:

```dart
import 'package:test/test.dart';
import 'package:modular_api/modular_api.dart';
import '../lib/modules/auth/usecases/login.dart';

void main() {
  group('LoginUseCase', () {
    test('should successfully login with valid credentials', () async {
      final handler = useCaseTestHandler(LoginUseCase.factory);
      
      final response = await handler({
        'username': 'example',
        'password': 'abc123',
      });

      expect(response.statusCode, equals(200));
      
      final body = jsonDecode(await response.readAsString());
      expect(body, containsPair('access_token', isA<String>()));
      expect(body, containsPair('refresh_token', isA<String>()));
      expect(body, containsPair('token_type', 'Bearer'));
      expect(body, containsPair('expires_in', isA<int>()));
    });

    test('should fail with invalid credentials', () async {
      final handler = useCaseTestHandler(LoginUseCase.factory);
      
      final response = await handler({
        'username': 'example',
        'password': 'wrong_password',
      });

      expect(response.statusCode, equals(500));
    });

    test('should validate empty username', () async {
      final handler = useCaseTestHandler(LoginUseCase.factory);
      
      final response = await handler({
        'username': '',
        'password': 'abc123',
      });

      expect(response.statusCode, equals(400));
    });
  });
}
```

### E2E Testing with httpClient

E2E tests should use `httpClient` to maintain consistency with production code:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:modular_api/modular_api.dart';

void main() {
  late Process serverProcess;
  const serverUrl = 'http://localhost:3456';

  setUpAll(() async {
    // Start server
    print('🚀 Starting server for E2E tests...');
    
    final envVars = _loadEnvVariables();
    serverProcess = await Process.start(
      'dart',
      ['run', 'bin/main.dart'],
      environment: envVars,
      workingDirectory: Directory.current.path,
    );

    // Wait for server to be ready
    var attempts = 0;
    const maxAttempts = 30;
    var serverReady = false;

    while (attempts < maxAttempts && !serverReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final response = await http
            .get(Uri.parse('$serverUrl/health'))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          serverReady = true;
          print('✅ Server ready\n');
        }
      } catch (e) {
        attempts++;
      }
    }

    if (!serverReady) {
      serverProcess.kill();
      throw Exception('❌ Server did not respond');
    }
  });

  tearDownAll(() async {
    print('\n🛑 Stopping server...');
    serverProcess.kill();
    await serverProcess.exitCode;
    print('✅ Server stopped');
  });

  group('E2E - Auth Flow with httpClient', () {
    String? refreshToken;

    test('1. Login - Successful with valid credentials', () async {
      print('🧪 Test 1: Login with valid credentials');

      // Use httpClient with auth=true to capture tokens automatically
      final body = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/auth/login',
        body: {'username': 'example', 'password': 'abc123'},
        auth: true,
        user: 'test_user_1',
      ) as Map<String, dynamic>;

      print('   Response: ${body.keys.join(', ')}');

      expect(body, containsPair('access_token', isA<String>()));
      expect(body, containsPair('refresh_token', isA<String>()));
      expect(body, containsPair('token_type', 'Bearer'));
      expect(body, containsPair('expires_in', isA<int>()));

      final accessToken = body['access_token'] as String;
      refreshToken = body['refresh_token'] as String;

      expect(accessToken, isNotEmpty);
      expect(refreshToken, isNotEmpty);

      print('✅ Login successful - tokens obtained');
    });

    test('2. Login - Invalid credentials should fail', () async {
      print('\n🧪 Test 2: Login with incorrect password');

      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'example', 'password': 'wrong_password'},
          auth: true,
          user: 'test_user_2',
        );
        fail('Expected login to fail with invalid credentials');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Invalid credentials correctly rejected');
      }
    });

    test('3. Refresh - Valid refresh token', () async {
      print('\n🧪 Test 3: Refresh with valid token');

      expect(refreshToken, isNotNull, reason: 'Refresh token from login is required');

      // Refresh doesn't use auth=true because it's not an authentication endpoint
      final body = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/auth/refresh',
        body: {'refresh_token': refreshToken},
      ) as Map<String, dynamic>;

      print('   Response: ${body.keys.join(', ')}');

      expect(body, containsPair('access_token', isA<String>()));
      expect(body, containsPair('token_type', 'Bearer'));
      expect(body, containsPair('expires_in', isA<int>()));

      final newAccessToken = body['access_token'] as String;
      expect(newAccessToken, isNotEmpty);
      expect(newAccessToken.split('.').length, equals(3), 
             reason: 'Access token should be a valid JWT (3 parts)');

      // If token rotation enabled, update refresh token
      if (body.containsKey('refresh_token')) {
        final newRefreshToken = body['refresh_token'] as String;
        expect(newRefreshToken, isNotEmpty);
        expect(
          newRefreshToken,
          isNot(equals(refreshToken)),
          reason: 'Rotated refresh token should be different',
        );
        refreshToken = newRefreshToken;
        print('   Token rotation detected - refresh token updated');
      }

      print('✅ Refresh successful - new access token obtained');
    });

    test('4. Protected Endpoint - Access with valid token', () async {
      print('\n🧪 Test 4: Access protected endpoint with valid token');

      // httpClient with auth=true automatically attaches Bearer token
      final body = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/module1/hello-world',
        body: {'word': 'World'},
        auth: true,
        user: 'test_user_1',  // Same user from login
      ) as Map<String, dynamic>;

      print('   Response: $body');

      expect(body, containsPair('output', isA<String>()));
      expect(body['output'], contains('Hello'));
      expect(body['output'], contains('World'));

      print('✅ Protected endpoint accessible with valid token');
    });

    test('5. Protected Endpoint - Fails without token', () async {
      print('\n🧪 Test 5: Access protected endpoint without token');

      try {
        // Without auth=true, no token is attached
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/module1/hello-world',
          body: {'word': 'World'},
        );
        fail('Expected request to fail without token');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Protected endpoint correctly rejects requests without token');
      }
    });

    test('6. Logout - Successfully revoke token', () async {
      print('\n🧪 Test 6: Logout with valid refresh token');

      // First, do fresh login
      final loginBody = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/auth/login',
        body: {'username': 'example', 'password': 'abc123'},
        auth: true,
        user: 'test_user_6',
      ) as Map<String, dynamic>;

      final logoutRefreshToken = loginBody['refresh_token'] as String;

      // Logout no usa auth=true
      final body = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/auth/logout',
        body: {'refresh_token': logoutRefreshToken},
      ) as Map<String, dynamic>;

      print('   Response: $body');

      expect(body, containsPair('success', true));
      expect(body, containsPair('message', isA<String>()));

      print('✅ Logout successful - token revoked');

      // Verify revoked token doesn't work
      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/refresh',
          body: {'refresh_token': logoutRefreshToken},
        );
        fail('Expected refresh to fail with revoked token');
      } catch (e) {
        expect(e.toString(), contains('Error in HTTP request'));
        print('✅ Revoked token correctly rejected');
      }
    });

    test('7. httpClient Auto-Refresh - Transparent retry on 401', () async {
      print('\n🧪 Test 7: httpClient auto-refresh on expired token');

      // Clear state
      await TokenVault.deleteRefresh('test_user_7');
      Token.clear();

      // Login to get tokens
      final loginBody = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/auth/login',
        body: {'username': 'example', 'password': 'abc123'},
        auth: true,
        user: 'test_user_7',
      ) as Map<String, dynamic>;

      // Simulate expired/invalid token
      Token.accessToken = 'invalid-or-expired-token';
      Token.accessExp = DateTime.now().subtract(const Duration(minutes: 10));

      // httpClient should detect 401, refresh, and retry
      final protected = await httpClient(
        method: 'POST',
        baseUrl: serverUrl,
        endpoint: 'api/module1/hello-world',
        body: {'word': 'AutoRefresh'},
        auth: true,
        user: 'test_user_7',
      ) as Map<String, dynamic>;

      expect(protected, isA<Map>());
      expect(protected['output'], isA<String>());
      expect((protected['output'] as String), contains('AutoRefresh'));

      print('✅ httpClient auto-refresh flow succeeded');
    });

    test('8. httpClient - AuthReLoginException when refresh fails', () async {
      print('\n🧪 Test 8: AuthReLoginException on refresh failure');

      // Configure invalid refresh token
      await TokenVault.saveRefresh('test_user_8', 'invalid-refresh-token');
      Token.accessToken = null;
      Token.accessExp = null;

      try {
        await httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/module1/hello-world',
          body: {'word': 'Fail'},
          auth: true,
          user: 'test_user_8',
        );
        fail('Expected AuthReLoginException to be thrown');
      } on AuthReLoginException catch (e) {
        print('✅ Caught expected AuthReLoginException: $e');
      }
    });
  });

  group('E2E - Concurrency with httpClient', () {
    test('Multiple concurrent logins', () async {
      print('\n🧪 Test: Concurrent logins');

      final futures = List.generate(5, (index) {
        return httpClient(
          method: 'POST',
          baseUrl: serverUrl,
          endpoint: 'api/auth/login',
          body: {'username': 'example', 'password': 'abc123'},
          auth: true,
          user: 'test_user_concurrent_$index',
        );
      });

      final responses = await Future.wait(futures);

      var successCount = 0;
      final tokens = <String>{};

      for (var i = 0; i < responses.length; i++) {
        try {
          final body = responses[i] as Map<String, dynamic>;
          successCount++;
          tokens.add(body['refresh_token'] as String);
        } catch (e) {
          // Ignorar errores en test de concurrencia
        }
      }

      print('   Successful requests: $successCount/5');
      print('   Unique tokens generated: ${tokens.length}');

      expect(successCount, equals(5), reason: 'All concurrent logins should succeed');
      expect(tokens.length, equals(5), reason: 'Each login should generate unique token');

      print('✅ Concurrency handled correctly');
    });
  });
}

Map<String, String> _loadEnvVariables() {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    throw Exception('.env file not found');
  }

  final envVars = <String, String>{};
  final lines = envFile.readAsLinesSync();

  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final separatorIndex = line.indexOf('=');
    if (separatorIndex == -1) continue;

    final key = line.substring(0, separatorIndex).trim();
    var value = line.substring(separatorIndex + 1).trim();

    // Remove quotes
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    }

    envVars[key] = value;
  }

  return envVars;
}
```

### Testing Patterns with httpClient

#### ✅ Successful Login
```dart
final body = await httpClient(
  method: 'POST',
  baseUrl: serverUrl,
  endpoint: 'api/auth/login',
  body: {'username': 'user', 'password': 'pass'},
  auth: true,
  user: 'unique_test_user_id',
) as Map<String, dynamic>;

expect(body['access_token'], isNotEmpty);
expect(body['refresh_token'], isNotEmpty);
```

#### ❌ Login with Invalid Credentials
```dart
try {
  await httpClient(
    method: 'POST',
    baseUrl: serverUrl,
    endpoint: 'api/auth/login',
    body: {'username': 'user', 'password': 'wrong'},
    auth: true,
    user: 'test_user',
  );
  fail('Expected login to fail');
} catch (e) {
  expect(e.toString(), contains('Error in HTTP request'));
}
```

#### 🔄 Refresh Token
```dart
final body = await httpClient(
  method: 'POST',
  baseUrl: serverUrl,
  endpoint: 'api/auth/refresh',
  body: {'refresh_token': refreshToken},
  // Don't use auth=true for refresh/logout endpoints
) as Map<String, dynamic>;

expect(body['access_token'], isNotEmpty);
```

#### 🔒 Protected Endpoint
```dart
final body = await httpClient(
  method: 'POST',
  baseUrl: serverUrl,
  endpoint: 'api/protected/resource',
  body: {'data': 'value'},
  auth: true,
  user: 'test_user',  // Same user from login
) as Map<String, dynamic>;

expect(body, containsPair('result', isA<String>()));
```

#### 🚫 Protected Endpoint without Token
```dart
try {
  await httpClient(
    method: 'POST',
    baseUrl: serverUrl,
    endpoint: 'api/protected/resource',
    body: {'data': 'value'},
    // Without auth=true, no token is attached
  );
  fail('Expected request to fail without token');
} catch (e) {
  expect(e.toString(), contains('Error in HTTP request'));
}
```

---

## Security and Best Practices

### 🔒 Security Configuration

1. **JWT Secret**: 
   - Use strong key (minimum 32 random bytes)
   - Never commit to repository
   - Rotate periodically in production

2. **Password Hashing**:
   - Bcrypt cost factor: 12 (adjust based on hardware)
   - Never store passwords in plain text
   - Implement strong password policies

3. **Token Storage**:
   - Store only SHA-256 hashes in DB
   - Never log complete tokens
   - Implement token rotation for refresh tokens

4. **HTTPS**:
   - ALWAYS use HTTPS in production
   - Enable HSTS
   - Configure CORS appropriately

### ⚡ Recommended Configurations

```env
# Production
JWT_SECRET=<generated-with-openssl-rand-base64-32>
JWT_EXPIRES_IN=900           # 15 minutes
REFRESH_TOKEN_DAYS=7         # 7 days
BCRYPT_COST=12               # Adjust based on hardware

# Development
JWT_SECRET=dev-secret-key
JWT_EXPIRES_IN=3600          # 1 hour (more comfortable for dev)
REFRESH_TOKEN_DAYS=30        # 30 days
```

### 📊 Monitoring

Implement logging of:
- Failed login attempts
- Token refreshes
- Logouts
- Expired/revoked tokens

### 🛡️ Rate Limiting

Consider implementing rate limiting for:
- `/api/auth/login`: Max 5 attempts/minute
- `/api/auth/refresh`: Max 10 attempts/minute

### 🔄 Token Rotation

**Advantages**:
- Higher security (single-use tokens)
- Better token theft detection
- Complete audit trail

**Disadvantages**:
- Additional complexity
- Requires careful client-side handling

**Recommendation**: Enable in production, disable in development.

```dart
// In RefreshUseCase
RefreshUseCase({
  required super.input,
  this.enableRotation = true,  // Change to true in production
});
```

---

## Troubleshooting

### Error: "Token has expired"
- **Cause**: Access token expired
- **Solution**: Call `/api/auth/refresh` with refresh token

### Error: "Refresh token not found or has been revoked"
- **Cause**: Invalid or revoked refresh token
- **Solution**: User must login again

### Error: "Invalid username or password"
- **Cause**: Incorrect credentials
- **Solution**: Verify username/password, check DB

### Error: "Connection to PostgreSQL failed"
- **Cause**: DB unavailable
- **Solution**: Verify PostgreSQL is running and credentials are correct

---

## Additional Resources

- [JWT.io](https://jwt.io) - JWT Debugger
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [modular_api Documentation](../README.md)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

**Questions or problems?** Open an issue in the repository.
