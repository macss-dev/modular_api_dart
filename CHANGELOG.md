# Changelog
All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/)
and the project adheres to [Semantic Versioning](https://semver.org/).

### Documentation

## [0.0.9] - 2025-12-15
### Added
- **OAuth2 Client Credentials Support** — full OAuth2 implementation:
  - `OAuthService` — manages client authentication and JWT token generation
  - `OAuthClient` — represents registered clients with credentials and scopes
  - `TokenRequest`, `TokenResponse`, `TokenErrorResponse` — OAuth2 data structures
  - `AccessToken` — decoded JWT with scope validation methods
  - `createOAuthTokenHandler` — POST /oauth/token endpoint handler
  - `bearer()` middleware — validates Bearer tokens and enforces scopes
  - `requireAuth()` middleware — marks routes as requiring authentication
  - HS256 (HMAC-SHA256) JWT signing algorithm
  - Scope-based authorization for protected endpoints
  - Follows RFC 6749 OAuth2 specification

### Changed
- Exported auth utilities: `JwtHelper`, `hashPassword`, `verifyPassword`, `hashToken`
- Updated exports to include OAuth2 types and services

### Removed
- **Removed `template/` folder** — Simplified project structure by removing the full example template
  - Template project has been removed to reduce repository complexity
  - Only the minimal `example/` folder remains for quick reference
  - Previous template code included extensive examples, tests, and infrastructure that were redundant

### Documentation
- Added comprehensive OAuth2 guides and examples
- Updated AGENTS.md with OAuth2 usage patterns
- Updated all documentation to remove references to `template/` folder
- Simplified examples to focus on the minimal `example/` implementation
- Cleaned up README.md, AGENTS.md, and guides to reflect simplified structure

## [0.0.8] - 2025-12-04
### Added
- **Output.statusCode** — customizable HTTP status code for UseCase responses:
  - `Output` abstract class now includes `int get statusCode => 200;` getter
  - Override in your Output DTO to return custom HTTP status codes (e.g., 201 for created, 400 for bad request)
  - `useCaseHttpHandler` uses `output.statusCode` instead of hardcoded 200
  - Enables proper RESTful responses without modifying the HTTP handler

### Changed
- **Output DTOs** now use `extends Output` instead of `implements Output` to inherit the default `statusCode` getter
- Example and template Output classes updated to extend Output

### Migration Guide
If you have existing Output DTOs using `implements Output`, change them to `extends Output`:
```dart
// Before
class MyOutput implements Output { ... }

// After
class MyOutput extends Output { ... }
```
Alternatively, add the statusCode getter manually: `@override int get statusCode => 200;`

## [0.0.7] - 2025-11-04
### Added
- **httpClient** — intelligent HTTP client with automatic authentication:
  - Automatic token attachment for authenticated requests (`auth: true`)
  - Auto-capture of access and refresh tokens from login responses
  - Transparent retry with refresh token on 401 responses
  - Throws `AuthReLoginException` when refresh fails (signals re-login required)
  - Per-user token management via `user` parameter
- **Token** (in-memory session) — static class for managing access tokens:
  - `Token.accessToken` — current access token
  - `Token.accessExp` — access token expiration timestamp
  - `Token.isAuthenticated` — check if user has valid token
  - `Token.isExpired` — check if current token is expired
  - `Token.clear()` — clear session
- **TokenVault** (persistent storage) — configurable adapter for refresh tokens:
  - `TokenVault.saveRefresh(userId, token)` — persist refresh token
  - `TokenVault.readRefresh(userId)` — retrieve refresh token
  - `TokenVault.deleteRefresh(userId)` — delete specific refresh token
  - `TokenVault.deleteAll()` — clear all tokens
  - `TokenVault.configure(adapter)` — set storage adapter
  - Includes `MemoryStorageAdapter` (default) and `FileStorageAdapter` with optional encryption
- **JwtHelper** — JWT generation and validation utilities:
  - `generateAccessToken({userId, username})` — create access tokens (15 min)
  - `generateRefreshToken({userId, tokenId})` — create refresh tokens (7 days)
  - `verifyToken(token)` — validate and decode JWT
  - `calculateRefreshTokenExpiration()` — get refresh token expiry date
  - Reads secret from `JWT_SECRET` environment variable
- **PasswordHasher** — bcrypt password hashing:
  - `hash(password, {cost = 12})` — generate bcrypt hash
  - `verify(password, hash)` — verify password against hash
  - `needsRehash(hash, {cost})` — check if hash needs update
- **TokenHasher** — SHA-256 token hashing for secure storage:
  - `hash(token)` — generate SHA-256 hash (64 hex chars)
  - `verify(token, expectedHash)` — verify token against hash
- **AuthReLoginException** — specialized exception for auth flow control
- Comprehensive authentication documentation:
  - **docs/auth_implementation_guide.md** — Complete JWT authentication implementation guide with refresh tokens, including database setup, repository patterns, use cases, and client integration (Flutter & Dart)
  - **docs/http_client_guide.md** — Focused guide for using httpClient in Flutter and pure Dart applications with configuration examples and best practices
- Complete E2E authentication test suite:
  - `template/test/e2e/auth_flow_test.dart` — 25+ comprehensive tests covering login, refresh, logout, protected endpoints, concurrent requests, auto-refresh behavior, and re-login exception handling

### Changed
- All documentation translated to English for consistency

## [0.0.6] - 2025-10-30
### Added
- Exported `useCaseTestHandler` in main library export (`lib/modular_api.dart`) for convenient unit testing of UseCases without starting an HTTP server.
- Comprehensive documentation guides:
  - **AGENTS.md** — Framework overview and implementation guide optimized for AI assistants
  - **docs/USECASE_DTO_GUIDE.md** — Complete guide for creating Input/Output DTOs with type mapping reference and advanced examples
  - **docs/usecase_implementation.md** — Step-by-step guide for implementing UseCases with validation, database access, and repository patterns
  - **docs/TESTING_GUIDE.md** — Quick reference for testing UseCases using `useCaseTestHandler`
- Complete test suite for template project:
  - `template/test/module1/hello_world_test.dart` — 5 tests for HelloWorld use case
  - `template/test/module2/sum_case_test.dart` — 7 tests for SumCase use case
  - `template/test/module2/upper_case_test.dart` — 7 tests for UpperCase use case
  - `template/test/module3/lower_case_test.dart` — 7 tests for LowerCase use case
  - `template/test/module3/multiply_case_test.dart` — 9 tests for MultiplyCase use case
  - All 35 tests demonstrate proper usage of `useCaseTestHandler` with success and failure scenarios

## [0.0.5] - 2025-10-25
### Changed
- `Env` now initializes automatically on first access (lazy singleton pattern). No need to call `Env.init()` explicitly, though it remains available for manual initialization if needed.
- .usecase() now trims leading slashes from usecase names to prevent double slashes in registered paths.

## [0.0.4] - 2025-10-23
### Changed
- `Env` behavior: when a `.env` file is not found the library reads values from `Platform.environment`. If a requested key is missing from both sources an `EnvKeyNotFoundException` is thrown.

## [0.0.3] - 2025-10-23
### Added
- Automatic health endpoint: the server registers `GET /health` which responds with `ok` on startup. Implemented in `modular_api.dart` (exposes `_root.get('/health', (Request request) => Response.ok('ok'));`).

## [0.0.2] - 2025-10-21
### Changed
- refactor: improve OpenAPI initialization (now initialized automatically internally)
- Rename middlewares as examples
- rename example project to template
- Add a simple example

## [0.0.1] - 2025-10-21
### Added
- Initial release of **modular_api**. Main features:
  - Use-case centric framework with `UseCase<I extends Input, O extends Output>` base classes and DTO helpers (`Input`/`Output`).
  - HTTP adapter `useCaseHttpHandler()` to expose UseCases as Shelf `Handler`s.
  - Built-in middlewares: `cors()` and `apiKey()` for CORS handling and header-based API key authentication.
  - OpenAPI/Swagger generation helpers (`OpenApi.init`, `OpenApi.docs`) that infer schemas from DTO `toSchema()`.
  - Utilities: `Env.getString`, `Env.getInt`, `Env.setString` (.env support via dotenv) and `getLocalIp`.
  - Minimal ODBC `DbClient` (DSN-based) exported for database access; example factories and usage provided in `example/` (tested with Oracle and SQL Server; see `NOTICE` for provenance).
  - Example project demonstrating modules and usecases under `example/` and unit-test helpers (`useCaseTestHandler`) under `test/`.
  - Public API exports in `lib/modular_api.dart` for easy consumption.

