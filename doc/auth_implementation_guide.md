# Guía de Implementación de Autenticación con modular_api

Esta guía explica cómo implementar un sistema completo de autenticación JWT con refresh tokens usando `modular_api`.

---

## 📋 Tabla de Contenidos

1. [Requisitos Previos](#requisitos-previos)
2. [Estructura del Sistema](#estructura-del-sistema)
3. [Configuración de la Base de Datos](#configuración-de-la-base-de-datos)
4. [Dependencias Requeridas](#dependencias-requeridas)
5. [Estructura de Archivos](#estructura-de-archivos)
6. [Implementación Paso a Paso](#implementación-paso-a-paso)
7. [Uso desde Cliente (Flutter)](#uso-desde-cliente-flutter)
8. [Testing](#testing)
9. [Seguridad y Mejores Prácticas](#seguridad-y-mejores-prácticas)

---

## Requisitos Previos

- Dart SDK 3.8.1 o superior
- PostgreSQL 12 o superior
- Conocimientos básicos de JWT
- Conocimientos de SQL

---

## Estructura del Sistema

El sistema de autenticación implementa:

- ✅ **Login**: Autenticación con username/password → retorna access token + refresh token
- ✅ **Refresh**: Intercambiar refresh token por nuevo access token
- ✅ **Logout**: Revocar un refresh token específico (cerrar sesión en un dispositivo)
- ✅ **Logout All**: Revocar todos los refresh tokens del usuario (cerrar todas las sesiones)
- ✅ **Token Rotation**: Opcional, genera nuevo refresh token en cada refresh (más seguro)
- ✅ **Password Hashing**: Bcrypt con cost factor 12
- ✅ **Token Storage**: Hashes SHA-256 en base de datos

### Flujo de Tokens

```
┌─────────────┐
│   Cliente   │
└──────┬──────┘
       │
       │ 1. POST /api/auth/login
       │    {username, password}
       ▼
┌─────────────────────────────┐
│         Servidor            │
│  ┌─────────────────────┐   │
│  │ LoginUseCase        │   │
│  │ - Verificar credenc.│   │
│  │ - Generar tokens    │   │
│  │ - Guardar hash      │   │
│  └─────────────────────┘   │
└──────┬──────────────────────┘
       │
       │ 2. Response: {access_token, refresh_token, expires_in}
       ▼
┌─────────────┐
│   Cliente   │
│ Guarda ambos│
│   tokens    │
└──────┬──────┘
       │
       │ (15 minutos después, access token expira)
       │
       │ 3. POST /api/auth/refresh
       │    {refresh_token}
       ▼
┌─────────────────────────────┐
│         Servidor            │
│  ┌─────────────────────┐   │
│  │ RefreshUseCase      │   │
│  │ - Verificar token   │   │
│  │ - Check DB hash     │   │
│  │ - Generar nuevo AT  │   │
│  │ - (Rotar RT)        │   │
│  └─────────────────────┘   │
└──────┬──────────────────────┘
       │
       │ 4. Response: {access_token, [refresh_token], expires_in}
       ▼
┌─────────────┐
│   Cliente   │
│  Actualiza  │
│   tokens    │
└─────────────┘
```

---

## Configuración de la Base de Datos

### 1. Crear el Schema

```sql
-- Crear schema auth
CREATE SCHEMA IF NOT EXISTS auth;
```

### 2. Tabla: auth.user

Almacena información básica de usuarios.

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

**Campos:**
- `id`: Identificador único (auto-incremento)
- `username`: Nombre de usuario único (3-16 caracteres recomendado)
- `full_name`: Nombre completo del usuario
- `created_at`: Fecha de creación del usuario

### 3. Tabla: auth.password

Almacena hashes de contraseñas (bcrypt).

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

**Campos:**
- `id`: Identificador único
- `id_user`: Referencia al usuario (FK)
- `password_hash`: Hash bcrypt de la contraseña (60 caracteres)
- `created_at`: Fecha de creación
- `updated_at`: Fecha de última actualización

**IMPORTANTE**: Relación 1:1 con `auth.user` (un usuario, una contraseña).

### 4. Tabla: auth.refresh_token

Almacena hashes de refresh tokens y audit trail.

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

**Campos:**
- `id`: Identificador único (se incluye en el JWT como `jti`)
- `id_user`: Referencia al usuario (FK)
- `token_hash`: Hash SHA-256 del refresh token (64 caracteres hex)
- `previous_id`: ID del token anterior (para token rotation chain)
- `revoked`: Indica si el token fue revocado (soft delete)
- `created_at`: Fecha de creación del token
- `expires_at`: Fecha de expiración del token (7 días por defecto)

**Relación 1:N con `auth.user`**: Un usuario puede tener múltiples refresh tokens activos (múltiples dispositivos/sesiones).

### 5. Datos de Prueba (Seed)

```sql
-- Usuarios de ejemplo
INSERT INTO auth.user (username, full_name) VALUES
  ('example', 'Example User'),
  ('admin', 'Administrator User'),
  ('testuser', 'Test User Demo');

-- Contraseñas (bcrypt hash de las contraseñas)
-- example: abc123
-- admin: password123
-- testuser: password123
INSERT INTO auth.password (id_user, password_hash) VALUES
  (1, '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYHNqJzS0yG'),
  (2, '$2b$12$fR8Qg3JZ0Ih7LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5'),
  (3, '$2b$12$fR8Qg3JZ0Ih7LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5');
```

---

## Dependencias Requeridas

### Servidor (Dart Backend)

Agrega al `pubspec.yaml`:

```yaml
dependencies:
  modular_api: ^0.0.7       # Incluye bcrypt, dart_jsonwebtoken y crypto
  postgres: ^3.0.0          # Cliente PostgreSQL
  
dev_dependencies:
  test: ^1.24.0             # Testing
  http: ^1.5.0              # Cliente HTTP para tests E2E
```

### Cliente Flutter

Agrega al `pubspec.yaml` de tu app Flutter:

```yaml
dependencies:
  http: ^1.5.0                        # Cliente HTTP
  flutter_secure_storage: ^9.2.2     # Almacenamiento seguro de tokens
  dart_jsonwebtoken: ^2.14.0          # Decodificar JWT (opcional)
```

---

## Estructura de Archivos

```
lib/
├── db/
│   └── postgres_client.dart          # Cliente PostgreSQL
└── modules/
    └── auth/
        ├── auth_builder.dart         # Registro de endpoints
        ├── auth_repository.dart      # Operaciones de DB
        └── usecases/
            ├── login.dart            # POST /auth/login
            ├── refresh.dart          # POST /auth/refresh
            ├── logout.dart           # POST /auth/logout
            └── logout_all.dart       # POST /auth/logout_all

db/
└── auth/
    ├── auth.sql                      # Schema completo
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

## Implementación Paso a Paso

### Paso 1: Utilidades Base

**IMPORTANTE**: Las utilidades `JwtHelper` y `PasswordHasher` están incluidas en el paquete `modular_api` desde la versión 0.0.7. Solo necesitas importarlas:

```dart
import 'package:modular_api/modular_api.dart';

// Ya tienes acceso a:
// - JwtHelper: Generación y validación de JWT
// - JwtException: Excepción para errores JWT
// - PasswordHasher: Hash y verificación de contraseñas con bcrypt
```

#### 1.1 JwtHelper (incluido en modular_api)

El `JwtHelper` incluido en el framework proporciona:

**Métodos:**
- `generateAccessToken({required int userId, required String username})` - Genera token de acceso (15 min)
- `generateRefreshToken({required int userId, required int tokenId})` - Genera token de refresco (7 días)
- `verifyToken(String token)` - Verifica y decodifica un token JWT
- `calculateRefreshTokenExpiration()` - Calcula fecha de expiración del refresh token
- `accessTokenExpiresIn` - Getter para tiempo de expiración del access token (en segundos)

**Configuración:**
- El `JwtHelper` lee el secreto JWT de la variable de entorno `JWT_SECRET`
- Access tokens: 15 minutos de duración
- Refresh tokens: 7 días de duración

**Ejemplo de uso:**
```dart
// Generar access token
final accessToken = JwtHelper.generateAccessToken(
  userId: 1,
  username: 'example',
);

// Generar refresh token
final refreshToken = JwtHelper.generateRefreshToken(
  userId: 1,
  tokenId: 123,
);

// Verificar token
try {
  final payload = JwtHelper.verifyToken(accessToken);
  print('User ID: ${payload['sub']}');
  print('Type: ${payload['type']}'); // 'access' o 'refresh'
} on JwtException catch (e) {
  print('Token inválido: $e');
}
```

#### 1.2 PasswordHasher (incluido en modular_api)

El `PasswordHasher` incluido en el framework proporciona:

**Métodos:**
- `hash(String password, {int cost = 12})` - Genera hash bcrypt de la contraseña
- `verify(String password, String hash)` - Verifica contraseña contra hash
- `needsRehash(String hash, {int cost = 12})` - Determina si el hash necesita actualizarse

#### 1.3 TokenHasher (incluido en modular_api)

El `TokenHasher` incluido en el framework proporciona hashing SHA-256 seguro para almacenar tokens:

**Métodos:**
- `hash(String token)` - Genera hash SHA-256 del token (64 caracteres hexadecimales)
- `verify(String token, String expectedHash)` - Verifica token contra hash almacenado

**Propósito:**
Los refresh tokens deben almacenarse hasheados en la base de datos por seguridad. Si la base de datos es comprometida, los tokens originales no pueden ser recuperados del hash.

**Ejemplo de uso:**
```dart
// Hashear refresh token antes de guardar en DB
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

// Verificar token recibido contra hash almacenado
final incomingTokenHash = TokenHasher.hash(receivedToken);
final storedToken = await repo.getRefreshToken(incomingTokenHash);

// O usar el método de conveniencia
if (TokenHasher.verify(receivedToken, storedToken.hash)) {
  // Token válido
}
```

**Configuración:**
- Cost factor por defecto: 12 (ajustable según hardware)
- Usa bcrypt internamente

**Ejemplo de uso:**
```dart
// Hash de contraseña
final hash = PasswordHasher.hash('abc123');
// $2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYHNqJzS0yG

// Verificar contraseña
final isValid = PasswordHasher.verify('abc123', hash);
print(isValid); // true

// Verificar si necesita rehash (ej: si cambió el cost factor)
final needsUpdate = PasswordHasher.needsRehash(hash, cost: 13);
```

**Ventajas de usar las utilidades incluidas:**
- ✅ Sin dependencias adicionales (ya están en modular_api)
- ✅ Configuración por defecto segura
- ✅ Documentadas y testeadas
- ✅ Compatibles con el resto del framework
- ✅ Mantenidas y actualizadas con el paquete

### Paso 2: Repository

#### 2.1 Auth Repository (`lib/modules/auth/auth_repository.dart`)

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:modular_api/modular_api.dart';  // Importa JwtHelper y PasswordHasher
import '../../db/postgres_client.dart';

class AuthRepository {
  final PostgresClient _db;

  AuthRepository(this._db);

  /// Obtener usuario por username
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

  /// Verificar contraseña
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

  /// Autenticar usuario
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

  /// Guardar refresh token
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

  /// Obtener refresh token por hash
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

  /// Revocar refresh token
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

  /// Revocar todos los tokens de un usuario
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

  /// Contar tokens activos de un usuario
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

### Paso 3: Use Cases

#### 3.1 Login (`lib/modules/auth/usecases/login.dart`)

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:modular_api/modular_api.dart';  // Importa UseCase, Input, Output, JwtHelper
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
    // Autenticar usuario
    final user = await _repository.authenticate(
      input.username,
      input.password,
    );

    if (user == null) {
      throw ArgumentError('Invalid username or password');
    }

    final userId = user['id'] as int;
    final username = user['username'] as String;

    // Generar access token
    final accessToken = JwtHelper.generateAccessToken(
      userId: userId,
      username: username,
    );

    // Generar refresh token (primero guardar en DB para obtener ID)
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

    // Actualizar hash del token en DB
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
// Similar estructura a Login, ver template/lib/modules/auth/usecases/refresh.dart
// Implementa token rotation opcional y validación del refresh token
```

#### 3.3 Logout y Logout All

Ver implementaciones completas en el template.

### Paso 4: Registrar Módulo

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

#### 4.2 Registrar en ModularApi (`bin/main.dart`)

```dart
import 'package:modular_api/modular_api.dart';
import '../lib/modules/auth/auth_builder.dart';

Future<void> main() async {
  final api = ModularApi(basePath: '/api');

  // Registrar módulo auth
  api.module('auth', buildAuthModule);

  // Middlewares
  api.use(cors());
  api.use(apiKey()); // Opcional

  await api.serve(port: 3456);
  print('🚀 Server running at http://localhost:3456');
  print('📚 API Docs at http://localhost:3456/docs');
}
```

### Paso 5: Variables de Entorno

Crear archivo `.env`:

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

**IMPORTANTE**: Generar una clave segura para JWT:
```bash
openssl rand -base64 32
```

---

## Uso desde Cliente (Flutter)

### Paso 1: Crear Adapter para Flutter Secure Storage

Crea `lib/auth/flutter_secure_storage_adapter.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// IMPORTANTE: Este adapter es necesario para apps Flutter.
/// Para apps de servidor Dart, usar FileStorageAdapter (incluido en modular_api).
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

  /// Guardar refresh token
  Future<void> saveRefresh(String userId, String token) =>
      _storage.write(key: 'refresh_token_$userId', value: token);

  /// Leer refresh token
  Future<String?> readRefresh(String userId) =>
      _storage.read(key: 'refresh_token_$userId');

  /// Eliminar refresh token
  Future<void> deleteRefresh(String userId) =>
      _storage.delete(key: 'refresh_token_$userId');

  /// Eliminar todos los tokens
  Future<void> deleteAll() => _storage.deleteAll();

  /// Guardar access token (opcional, si necesitas guardarlo)
  Future<void> saveAccess(String userId, String token) =>
      _storage.write(key: 'access_token_$userId', value: token);

  /// Leer access token
  Future<String?> readAccess(String userId) =>
      _storage.read(key: 'access_token_$userId');
}
```

### Paso 2: Servicio de Autenticación

Crea `lib/auth/auth_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'flutter_secure_storage_adapter.dart';

class AuthService {
  final String baseUrl;
  final FlutterSecureStorageAdapter _storage;

  AuthService({
    required this.baseUrl,
    FlutterSecureStorageAdapter? storage,
  }) : _storage = storage ?? FlutterSecureStorageAdapter();

  String? _currentUserId;
  String? _currentAccessToken;

  /// Login
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

    // Extraer userId del access token (decodificar JWT)
    final userId = _extractUserIdFromToken(loginResponse.accessToken);

    // Guardar tokens
    await _storage.saveAccess(userId, loginResponse.accessToken);
    await _storage.saveRefresh(userId, loginResponse.refreshToken);

    _currentUserId = userId;
    _currentAccessToken = loginResponse.accessToken;

    return loginResponse;
  }

  /// Refresh token
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
      body: jsonEncode({
        'refresh_token': refreshToken,
      }),
    );

    if (response.statusCode != 200) {
      throw AuthException('Token refresh failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    
    // Actualizar access token
    final newAccessToken = data['access_token'] as String;
    await _storage.saveAccess(_currentUserId!, newAccessToken);
    _currentAccessToken = newAccessToken;

    // Si hay token rotation, actualizar refresh token
    if (data.containsKey('refresh_token')) {
      final newRefreshToken = data['refresh_token'] as String;
      await _storage.saveRefresh(_currentUserId!, newRefreshToken);
    }
  }

  /// Logout (revocar token actual)
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
        // Continuar incluso si falla la revocación en el servidor
      }
    }

    await _storage.deleteRefresh(_currentUserId!);
    await _storage.deleteAccess(_currentUserId!);
    _currentUserId = null;
    _currentAccessToken = null;
  }

  /// Logout de todas las sesiones
  Future<void> logoutAll() async {
    if (_currentUserId == null) return;

    final refreshToken = await _storage.readRefresh(_currentUserId!);
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout_all'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        );
      } catch (e) {
        // Continuar
      }
    }

    await _storage.deleteAll();
    _currentUserId = null;
    _currentAccessToken = null;
  }

  /// Obtener access token actual
  Future<String?> getAccessToken() async {
    if (_currentAccessToken != null) {
      // Verificar si está por expirar (menos de 1 minuto)
      if (_isTokenExpiringSoon(_currentAccessToken!)) {
        await refreshToken();
      }
      return _currentAccessToken;
    }
    return null;
  }

  /// Hacer request autenticado
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
    // Decodificar JWT (payload está en base64)
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

      // Refrescar si expira en menos de 1 minuto
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

### Paso 3: Uso en Flutter

```dart
// Inicializar
final authService = AuthService(baseUrl: 'http://localhost:3456');

// Login
try {
  final response = await authService.login(
    username: 'example',
    password: 'abc123',
  );
  print('Login exitoso! Access token expira en ${response.expiresIn}s');
} catch (e) {
  print('Login falló: $e');
}

// Hacer request autenticado
try {
  final response = await authService.authenticatedRequest(
    method: 'GET',
    path: '/api/users/profile',
  );
  print('Profile: ${response.body}');
} catch (e) {
  print('Request falló: $e');
}

// Logout
await authService.logout();

// Logout de todas las sesiones
await authService.logoutAll();
```

---

## Testing

### Test Unitario (Login)

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
  });
}
```

### Test E2E

Ver `template/test/e2e/auth_flow_test.dart` para ejemplo completo.

---

## Seguridad y Mejores Prácticas

### 🔒 Configuración de Seguridad

1. **JWT Secret**: 
   - Usar clave fuerte (mínimo 32 bytes aleatorios)
   - Nunca commitear en repositorio
   - Rotar periódicamente en producción

2. **Password Hashing**:
   - Bcrypt cost factor: 12 (ajustar según hardware)
   - Nunca almacenar contraseñas en texto plano
   - Implementar políticas de contraseñas fuertes

3. **Token Storage**:
   - Guardar solo hashes SHA-256 en DB
   - Nunca loggear tokens completos
   - Implementar token rotation para refresh tokens

4. **HTTPS**:
   - SIEMPRE usar HTTPS en producción
   - Habilitar HSTS
   - Configurar CORS apropiadamente

### ⚡ Configuraciones Recomendadas

```env
# Producción
JWT_SECRET=<generated-with-openssl-rand-base64-32>
JWT_EXPIRES_IN=900           # 15 minutos
REFRESH_TOKEN_DAYS=7         # 7 días
BCRYPT_COST=12               # Ajustar según hardware

# Desarrollo
JWT_SECRET=dev-secret-key
JWT_EXPIRES_IN=3600          # 1 hora (más cómodo para dev)
REFRESH_TOKEN_DAYS=30        # 30 días
```

### 📊 Monitoreo

Implementar logging de:
- Intentos de login fallidos
- Token refreshes
- Logouts
- Tokens expirados/revocados

### 🛡️ Rate Limiting

Considerar implementar rate limiting para:
- `/api/auth/login`: Max 5 intentos/minuto
- `/api/auth/refresh`: Max 10 intentos/minuto

### 🔄 Token Rotation

**Ventajas**:
- Mayor seguridad (tokens de un solo uso)
- Mejor detección de robo de tokens
- Audit trail completo

**Desventajas**:
- Complejidad adicional
- Requiere manejo cuidadoso en cliente

**Recomendación**: Habilitar en producción, deshabilitar en desarrollo.

```dart
// En RefreshUseCase
RefreshUseCase({
  required super.input,
  this.enableRotation = true,  // Cambiar a true en producción
});
```

---

## Troubleshooting

### Error: "Token has expired"
- **Causa**: Access token expiró
- **Solución**: Llamar a `/api/auth/refresh` con el refresh token

### Error: "Refresh token not found or has been revoked"
- **Causa**: Refresh token inválido o revocado
- **Solución**: Usuario debe hacer login nuevamente

### Error: "Invalid username or password"
- **Causa**: Credenciales incorrectas
- **Solución**: Verificar username/password, revisar DB

### Error: "Connection to PostgreSQL failed"
- **Causa**: DB no disponible
- **Solución**: Verificar que PostgreSQL esté corriendo y credenciales correctas

---

## Recursos Adicionales

- [JWT.io](https://jwt.io) - Debugger de JWT
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [modular_api Documentation](../README.md)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

## Changelog

- **v1.0.0** (2025-11-03): Guía inicial completa
  - Login, Refresh, Logout, Logout All
  - Token rotation opcional
  - Flutter integration
  - Tests E2E

---

**¿Preguntas o problemas?** Abre un issue en el repositorio.
