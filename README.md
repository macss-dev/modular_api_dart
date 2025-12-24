[![pub package](https://img.shields.io/pub/v/modular_api.svg)](https://pub.dev/packages/modular_api)

# modular_api

Use-case–centric toolkit for building Modular APIs with Shelf.
Define `UseCase` classes (input → validate → execute → output), connect them to HTTP routes,
add CORS / API Key middlewares, and expose Swagger / OpenAPI documentation.

> Designed for the MACSS ecosystem — modular, explicit and testable server code.

## 🚀 Quick start

This quick start mirrors the included example implementation (`example/example.dart`).

```dart
import 'package:modular_api/modular_api.dart';

Future<void> main(List<String> args) async {
  final api = ModularApi(basePath: '/api');

  // POST api/module1/hello-world
  api.module('module1', (m) {
    m.usecase('hello-world', HelloWorld.fromJson);
  });

  final port = 8080;
  await api.serve(port: port,);

  print('Docs on http://localhost:$port/docs');
}
```

Example request (example server registers `/api/module1/hello-world` as a POST):

```bash
curl -H "Content-Type: application/json" -d '{"word":"world"}' \
  -H "x-api-key: SECRET" \
  "http://localhost:8080/api/module1/hello-world"
```

Example response (HelloOutput):

```json
{"output":"Hello, world!"}
```

---

## 📖 Documentation

**Start here**: [doc/INDEX.md](doc/INDEX.md) — Complete documentation index and vertical development guide

### Quick Links

Core guides for vertical feature development:

- **[doc/INDEX.md](doc/INDEX.md)** — Entry point: vertical development flow from DB to UI
- **[AGENTS.md](AGENTS.md)** — Framework overview and implementation guide (optimized for AI assistants)
- **[doc/usecase_dto_guide.md](doc/usecase_dto_guide.md)** — Creating Input/Output DTOs
- **[doc/usecase_implementation.md](doc/usecase_implementation.md)** — Implementing UseCases with business logic
- **[doc/testing_guide.md](doc/testing_guide.md)** — Testing UseCases with `useCaseTestHandler`
- **[doc/http_client_guide.md](doc/http_client_guide.md)** — Using httpClient in Flutter and Dart apps
- **[doc/authentication_guide.md](doc/authentication_guide.md)** — Token management and storage adapters
- **[doc/auth_implementation_guide.md](doc/auth_implementation_guide.md)** — Complete JWT authentication system

---

## ✨ Features

- ✅ `UseCase<I extends Input, O extends Output>` base classes and DTOs (`Input`/`Output`).
- 🎯 **Custom HTTP Status Codes**: Output DTOs can override `statusCode` getter to return appropriate HTTP status codes (200, 201, 400, 401, 404, 422, 500, etc.)
- 🚨 **UseCaseException**: Throw structured exceptions during use case execution with custom status codes, error messages, and details
- 🧩 `useCaseHttpHandler()` adapter: accepts a factory `UseCase Function(Map<String, dynamic>)`
  and returns a Shelf `Handler`.
- 🔐 **OAuth2 & Authentication**:
  - **OAuth2 Client Credentials**: Built-in OAuth2 Authorization Server with Client Credentials grant type
  - **JWT Tokens**: HS256 (HMAC-SHA256) signed tokens with configurable TTL
  - **Bearer Token Middleware**: Automatic token validation and scope-based authorization
  - **Auto-mounting**: OAuth token endpoint (`POST /oauth/token`) automatically registered when `oauthService` is provided
  - **Scope Protection**: Per-usecase scope requirements via `requiredScopes` parameter
  - `httpClient()` — intelligent HTTP client with automatic authentication, token management, and auto-refresh on 401
  - `Token` — in-memory session management (access tokens, expiration checking)
  - `TokenVault` — configurable persistent storage for refresh tokens (with adapters for memory, file, and custom storage)
  - `JwtHelper` — JWT generation and validation utilities
  - `PasswordHasher` — bcrypt password hashing and verification
  - `TokenHasher` — SHA-256 token hashing for secure storage
  - `AuthReLoginException` — specialized exception for authentication flow control
- 🧱 Included middlewares:
  - `cors()` — simple CORS support.
  - `apiKey()` — header-based authentication; the key is read from the `API_KEY` environment
    variable (via `Env`).
  - `bearer()` — OAuth2 Bearer token validation with scope checking.
- 📄 OpenAPI / Swagger helpers:
  - `OpenApi.init(title)` and `OpenApi.docs` — generate an OpenAPI spec from registered
    usecases (uses DTO `toSchema()`), and provide a Swagger UI `Handler`.
 - 📡 Automatic health endpoint:
   - The server registers a simple health check endpoint at `GET /health` which responds with
     200 OK and body `ok`. This is implemented in `modular_api.dart` as:
     `_root.get('/health', (Request request) => Response.ok('ok'));`
 - ⚙️ Utilities: `Env.getString`, `Env.getInt`, `Env.setString` (.env support via dotenv).
  - `Env` behavior: if a `.env` file is not present the library will read values from
    `Platform.environment`; if a requested key is missing from both sources an
    `EnvKeyNotFoundException` is thrown.
- 🧪 Example project and tests included in `example/` and `test/`.

- 🗄️ ODBC database client: a minimal ODBC `DbClient` implementation (DSN-based) tested with Oracle and SQL Server — see `NOTICE` for provenance and details.
  
  Usage:

  ```dart
  import 'package:modular_api/modular_api.dart';

  Future<void> runQuery() async {
    // Create a DSN-based client (example factories available in example/lib/db/db.dart)
    final db = createSqlServerClient();

    try {
      final rows = await db.execute('SELECT @@VERSION as version');
      print(rows);
    } finally {
      // ensure disconnect
      await db.disconnect();
    }
  }
  ```

  See `NOTICE` for provenance details.

---

## 📦 Installation

In `pubspec.yaml`:

```yaml
dependencies:
  modular_api: ^0.0.10
```

Or from the command line:

```powershell
dart pub add modular_api
dart pub get
```

---

## � Error Handling with UseCaseException

Throw structured exceptions during use case execution to control HTTP responses:

```dart
import 'package:modular_api/modular_api.dart';

class GetUserUseCase extends UseCase<GetUserInput, GetUserOutput> {
  GetUserUseCase(super.input);
  
  static GetUserUseCase fromJson(Map<String, dynamic> json) {
    return GetUserUseCase(GetUserInput.fromJson(json));
  }
  
  @override
  String? validate() => null;
  
  @override
  Future<void> execute() async {
    // Validation errors
    if (input.userId <= 0) {
      throw UseCaseException(
        statusCode: 400,
        message: 'Invalid user ID',
        errorCode: 'INVALID_USER_ID',
      );
    }
    
    // Resource not found
    final user = await repository.findById(input.userId);
    if (user == null) {
      throw UseCaseException(
        statusCode: 404,
        message: 'User not found',
        errorCode: 'USER_NOT_FOUND',
      );
    }
    
    // Business logic errors
    if (!user.isActive) {
      throw UseCaseException(
        statusCode: 422,
        message: 'User account is inactive',
        errorCode: 'ACCOUNT_INACTIVE',
        details: {'userId': input.userId, 'status': user.status},
      );
    }
    
    // External service errors
    try {
      await externalService.verify(user);
    } catch (e) {
      throw UseCaseException(
        statusCode: 503,
        message: 'Verification service unavailable',
        errorCode: 'SERVICE_UNAVAILABLE',
      );
    }
    
    output = GetUserOutput(user: user);
  }
  
  @override
  Map<String, dynamic> toJson() => output.toJson();
}
```

**Response (404 Not Found):**
```json
{
  "error": "USER_NOT_FOUND",
  "message": "User not found"
}
```

**Response (422 Unprocessable Entity with details):**
```json
{
  "error": "ACCOUNT_INACTIVE",
  "message": "User account is inactive",
  "details": {
    "userId": 123,
    "status": "suspended"
  }
}
```

---

## �🔐 OAuth2 Client Credentials

The framework provides built-in OAuth2 Authorization Server support with Client Credentials grant type, JWT tokens, and automatic Bearer token validation.

### Quick Setup

```dart
import 'package:modular_api/modular_api.dart';

Future<void> main() async {
  // 1. Create OAuth2 service
  final oauthService = OAuthService(
    jwtSecret: Env.getString('JWT_SECRET'),
    issuer: 'your-domain.com',
    audience: 'your-domain.com',
    tokenTtlSeconds: 86400, // 24 hours
  );

  // 2. Register OAuth2 clients
  oauthService.registerClient(
    OAuthClient(
      clientId: 'client-id',
      clientSecret: 'client-secret',
      allowedScopes: ['read', 'write'],
      name: 'Client Name',
      isActive: true,
    ),
  );

  // 3. Create API with OAuth2 (auto-mounts /oauth/token endpoint)
  final api = ModularApi(
    basePath: '/api',
    oauthService: oauthService,
  );

  // 4. Protect specific usecases with scopes
  api.module('resources', (m) {
    m.usecase(
      'create',
      CreateResource.fromJson,
      requiredScopes: ['write'],  // Requires 'write' scope
    );
  });

  await api.serve(port: 8080);
}
```

### OAuth2 Flow

```bash
# 1. Obtain access token
curl -X POST http://localhost:8080/oauth/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "client_credentials",
    "client_id": "client-id",
    "client_secret": "client-secret",
    "scope": "read write"
  }'

# Response:
# {
#   "access_token": "eyJhbGc...",
#   "token_type": "Bearer",
#   "expires_in": 86400,
#   "scope": "read write"
# }

# 2. Use access token to call protected endpoints
curl -X POST http://localhost:8080/api/resources/create \
  -H "Authorization: Bearer eyJhbGc..." \
  -H "Content-Type: application/json" \
  -d '{"name": "Resource 1"}'
```

### Features

- ✅ **Client Credentials Grant**: OAuth2 standard flow for machine-to-machine authentication
- ✅ **JWT Tokens**: HS256 signed tokens with standard claims (iss, aud, sub, iat, exp, scopes)
- ✅ **Auto-mounting**: `/oauth/token` endpoint automatically registered
- ✅ **Scope Validation**: Per-usecase scope requirements
- ✅ **Bearer Middleware**: Automatic token validation with 401/403 responses
- ✅ **405 Support**: Proper HTTP method validation (POST required for token endpoint)

---

## 🔐 Authentication with httpClient

The intelligent `httpClient` simplifies authentication by automatically managing tokens for single-user applications:

```dart
import 'package:modular_api/modular_api.dart';

Future<void> authenticatedFlow() async {
  const baseUrl = 'http://localhost:8080';
  
  // Login - httpClient automatically captures and stores tokens
  final loginResponse = await httpClient(
    method: 'POST',
    baseUrl: baseUrl,
    endpoint: 'api/auth/login',
    body: {'username': 'user', 'password': 'pass'},
    auth: true,  // Auto-captures tokens from response
  ) as Map<String, dynamic>;
  
  print('Access token: ${loginResponse['access_token']}');
  
  // Protected request - httpClient automatically:
  // 1. Attaches Bearer token
  // 2. Retries with refresh token on 401
  // 3. Throws AuthReLoginException if refresh fails
  try {
    final profile = await httpClient(
      method: 'POST',
      baseUrl: baseUrl,
      endpoint: 'api/users/profile',
      body: {'user_id': 123},
      auth: true,  // Auto-attaches Bearer token
    );
    print('Profile: $profile');
  } on AuthReLoginException {
    // Session expired, redirect to login
    print('Please log in again');
  }
}
```

See **[doc/http_client_guide.md](doc/http_client_guide.md)** for complete examples and configuration.

---

## 🧭 Architecture

* **UseCase layer** — pure logic, independent of HTTP.
* **HTTP adapter** — turns a `UseCase` into a `Handler`.
* **Middlewares** — cross-cutting concerns (CORS, auth, logging).
* **Swagger UI** — documentation served automatically from registered use cases.

---

## 🧩 Middlewares

```dart
final api = ModularApi(basePath: '/api');
  .use(cors())
  .use(apiKey());
```

---

## 📄 Swagger/OpenAPI

To auto-generate the spec from registered routes and serve a UI:

Open `http://localhost:<port>/docs` to view the UI.

---

## 🧱 Example

This repository includes a minimal runnable example:

- `example/` — minimal, simplified runnable example. Check `example/example.dart` for a concrete `UseCase` + DTO example.

---

## 🧪 Tests

The repository includes example tests (`test/usecase_test.dart`) that demonstrate the
recommended pattern and the `useCaseTestHandler` helper for unit-testing `UseCase` logic.

Run tests with:

```powershell
dart test
```

---

## 🛠️ Compile to executable

* **Windows**

  ```bash
  dart compile exe example/example.dart -o build/api_example.exe
  ```

* **Linux / macOS**

  ```bash
  dart compile exe example/example.dart -o build/api_example
  ```

---

## 📄 License

MIT © [ccisne.dev](https://ccisne.dev)

```