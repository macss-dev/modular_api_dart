# modular_api - AI Agent Guide

Quick reference guide for AI assistants working with `modular_api` framework.

---

## Framework Overview

`modular_api` is a Dart/Flutter framework for building **use-case-centric REST APIs** on top of Shelf following clean architecture.

### Core Architecture

```
HTTP Request → ModularApi → Module → UseCase → Business Logic → Output → HTTP Response
                                ↓
                             Input DTO (validated)
```

**Key Components:**
- **UseCase** — Single business operation (pure logic, no HTTP concerns)
- **Input** — Request DTO with validation
- **Output** — Response DTO
- **Module** — Logical grouping of related use cases
- **ModularApi** — Main orchestrator for routing and middleware

**Default Behavior:**
- All endpoints are POST by default
- Automatic OpenAPI/Swagger documentation at `/docs`
- Automatic health check at `GET /health`
- Built-in middlewares: CORS, API Key authentication

---

## When to Use

✅ **Use `modular_api` for:**
- REST APIs in Dart/Flutter
- Clean architecture with use cases
- Automatic API documentation
- Testable, modular server code
- Separation of business logic from HTTP

❌ **Don't use for:**
- GraphQL APIs
- WebSocket-only servers
- Simple static file servers
- Frontend applications

---

## Quick Implementation Guide

### 1. Create DTOs

Every endpoint needs Input and Output DTOs.

**Requirements:**
- Extend `Input` or `Output` base class
- All properties must be `final`
- Implement `fromJson` factory constructor
- Override `toJson()` method
- Override `toSchema()` method for OpenAPI docs

**📖 Detailed Guide:** [doc/usecase_dto_guide.md](doc/usecase_dto_guide.md)

**Example:**
```dart
class MyInput extends Input {
  final String name;
  
  MyInput({required this.name});
  
  factory MyInput.fromJson(Map<String, dynamic> json) {
    return MyInput(name: json['name'] as String);
  }
  
  @override
  Map<String, dynamic> toJson() => {'name': name};
  
  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'description': 'User name'},
      },
      'required': ['name'],
    };
  }
}
```

### 2. Implement UseCase

**Requirements:**
- Extend `UseCase<InputType, OutputType>`
- Call `super(input)` in constructor
- Implement static `fromJson(Map<String, dynamic> json)` factory
- Override `execute()` method returning `Future<OutputType>`
- Keep business logic pure (no HTTP concerns)

**📖 Detailed Guide:** [doc/usecase_implementation.md](doc/usecase_implementation.md)

**Example:**
```dart
class MyUseCase extends UseCase<MyInput, MyOutput> {
  MyUseCase(super.input);
  
  static MyUseCase fromJson(Map<String, dynamic> json) {
    return MyUseCase(MyInput.fromJson(json));
  }
  
  @override
  Future<MyOutput> execute() async {
    // Business logic here
    return MyOutput(message: 'Hello, ${input.name}!');
  }
}
```

### 3. Create Module Builder

Encapsulate related use cases in a builder function:

```dart
void buildMyModule(ModuleBuilder m) {
  m.usecase('usecase-name', MyUseCase.fromJson);
  m.usecase('another-usecase', AnotherUseCase.fromJson);
}
```

### 4. Register Modules

```dart
final api = ModularApi(basePath: '/api');

api.module('module1', buildModule1);
api.module('users', buildUsersModule);

await api.serve(port: 8080);
```

**This creates endpoints like:**
- `POST /api/module1/usecase-name`
- `POST /api/users/create`

---

## Type Mapping for OpenAPI Schemas

When implementing `toSchema()`, use these mappings:

| Dart Type | OpenAPI Schema |
|-----------|----------------|
| `int` | `{'type': 'integer'}` |
| `double` | `{'type': 'number', 'format': 'double'}` |
| `String` | `{'type': 'string'}` |
| `bool` | `{'type': 'boolean'}` |
| `DateTime` | `{'type': 'string', 'format': 'date-time'}` |
| `List<T>` | `{'type': 'array', 'items': {...}}` |
| Custom class | `{'type': 'object', 'properties': {...}}` |

---

## Authentication & HTTP Client (v0.0.7+)

### Single-User Design

The framework is optimized for **single-user applications** (one user at a time).

**Key Features:**
- `httpClient()` — Intelligent HTTP client with auto-authentication
- `Token` — In-memory session management
- `TokenVault` — Persistent storage for refresh tokens
- `JwtHelper` — JWT generation and validation
- `PasswordHasher` — bcrypt password hashing
- `TokenHasher` — SHA-256 token hashing

**📖 Complete Guide:** [doc/http_client_guide.md](doc/http_client_guide.md)

**📖 Auth Implementation:** [doc/auth_implementation_guide.md](doc/auth_implementation_guide.md)

### Quick httpClient Usage

```dart
// Login - auto-captures tokens
await httpClient(
  method: 'POST',
  baseUrl: 'https://api.example.com',
  endpoint: 'api/auth/login',
  body: {'username': 'user', 'password': 'pass'},
  auth: true,
);

// Protected request - auto-attaches Bearer token, auto-refreshes on 401
try {
  final data = await httpClient(
    method: 'GET',
    baseUrl: 'https://api.example.com',
    endpoint: 'api/users/profile',
    auth: true,
  );
} on AuthReLoginException {
  // Session expired - redirect to login
}

// Logout
Token.clear();
await TokenVault.deleteRefresh();
```

**Important:** No `user` parameter needed in v0.0.7+ (single-user optimized).

---

## Testing

Use `useCaseTestHandler` for unit testing without HTTP server:

**📖 Complete Guide:** [doc/testing_guide.md](doc/testing_guide.md)

**Example:**
```dart
import 'package:modular_api/modular_api.dart';
import 'package:test/test.dart';
import 'dart:convert';

void main() {
  test('MyUseCase should return expected output', () async {
    final input = {'name': 'World'};
    final handler = useCaseTestHandler(MyUseCase.fromJson);
    
    final response = await handler(input);
    
    expect(response.statusCode, equals(200));
    final body = jsonDecode(await response.readAsString());
    expect(body['message'], equals('Hello, World!'));
  });
}
```

---

## Common User Requests and How to Handle Them

### Request: "Create an API endpoint to [do something]"

**Actions:**
1. Identify the operation name (e.g., "calculate sum", "create user")
2. Define Input DTO with required fields
3. Define Output DTO with result fields
4. Implement UseCase with business logic
5. Create or update module builder function to register the UseCase
6. Show registration code in main() using module builder
7. Provide example curl request

**Example Response Structure:**
- Show Input DTO implementation
- Show Output DTO implementation
- Show UseCase implementation
- Show module builder function (or update existing one)
- Show registration in ModularApi using the builder
- Provide test example using `useCaseTestHandler`

### Request: "Add validation to my use case"

**Actions:**
1. Add validation logic in `execute()` method
2. Throw `ArgumentError` or custom exceptions for validation failures
3. Framework automatically converts exceptions to HTTP 500 responses
4. Show updated `execute()` method with validation

### Request: "Connect to a database"

**Actions:**
1. Show how to inject `DbClient` in UseCase constructor
2. Implement `fromJson` to create/inject DB client
3. Show SQL query execution in `execute()` method
4. Handle empty results with exceptions
5. Parse result rows into Output DTO

**Built-in DB Support:**
- `DbClient` interface available
- ODBC support for SQL Server and Oracle
- DSN-based connections

### Request: "Add authentication"

**Actions:**
1. Show `apiKey()` middleware usage
2. Explain API key is read from `API_KEY` environment variable
3. Show how to use `Env.getString('API_KEY')`
4. Add middleware before serve: `api.use(apiKey())`

### Request: "Enable CORS"

**Actions:**
1. Show `cors()` middleware usage
2. Add before serve: `api.use(cors())`

### Request: "How do I test this?"

**Actions:**
1. Show `useCaseTestHandler` helper
2. Provide complete test example with `package:test`
3. Show how to test validation errors
4. Explain testing without HTTP server (unit test level)

---

## Code Generation Guidelines for AI Agents

### When generating DTOs:

1. **Always include all three methods:** `fromJson`, `toJson`, `toSchema`
2. **toSchema must match class properties exactly**
3. **Use proper type mapping** (see Type Mapping section)
4. **Mark optional fields with `?` in Dart and exclude from `required` array in schema**
5. **Add descriptions** to all properties in `toSchema` for better documentation

### When generating UseCases:

1. **Keep execute() method focused** — single responsibility
2. **Inject dependencies** via constructor, not create inside execute()
3. **Use meaningful variable names** for clarity
4. **Add validation** before business logic
5. **Throw descriptive exceptions** for errors
6. **Return properly constructed Output DTO**

### When showing registration:

1. **Show module builder function** — Encapsulate use cases in a builder
2. **Show complete main() function** with ModularApi setup registering builders
3. **Include port and base path** configuration
4. **Show how to access Swagger docs** at `/docs`
5. **Mention health endpoint** at `/health`
6. **Use meaningful module and usecase names** (kebab-case preferred)
7. **Keep builders in separate files** for better organization

---

## Middlewares

```dart
final api = ModularApi(basePath: '/api')
  .use(cors())        // Enable CORS
  .use(apiKey());     // API Key authentication (reads from API_KEY env var)
```

---

## Environment Variables

Use `Env` utility for environment variables:

```dart
final apiKey = Env.getString('API_KEY');
final port = Env.getInt('PORT');
```

**Behavior (v0.0.4+):**
1. If `.env` file exists → read from it
2. If `.env` not found → fallback to `Platform.environment`
3. If key not found → throws `EnvKeyNotFoundException`

---

## Database Support

Built-in ODBC client for SQL Server and Oracle:

```dart
import 'package:modular_api/modular_api.dart';

final db = createSqlServerClient();
try {
  final rows = await db.execute('SELECT * FROM users');
  print(rows);
} finally {
  await db.disconnect();
}
```

---

## Project Structure Recommendation

```
lib/
  modules/
    module1/
      usecases/
        usecase_1.dart
        usecase_2.dart
      repositories/
        repository.dart
      module1_builder.dart      # Builder function
    module2/
      usecases/
        usecase_3.dart
      module2_builder.dart
  db/
    db_client.dart
bin/
  main.dart                     # Imports all builders
test/
  module1/
    usecase_1_test.dart
```

---

## Common Mistakes to Avoid

When generating code, ensure you avoid these common mistakes:

1. ❌ **Forgetting `toSchema()`** — Required for OpenAPI docs
2. ❌ **Mismatched types in `toSchema()`** — Must match Dart types
3. ❌ **Not calling `super(input)`** in UseCase constructor
4. ❌ **Missing `static fromJson`** in UseCase
5. ❌ **Creating dependencies inside execute()** — Inject via constructor
6. ❌ **Accessing HTTP request/response** in UseCase — Keep it pure
7. ❌ **Not marking all DTO properties as `final`**
8. ❌ **Forgetting to override `toJson()` and `toSchema()`**
9. ❌ **Using mutable properties** in DTOs
10. ❌ **Not handling null/empty results** from database queries

---

## Error Messages and Troubleshooting

### Common Error: "Missing fromJson factory"
**Solution:** Add `static MyUseCase fromJson(Map<String, dynamic> json)` to UseCase class

### Common Error: "toSchema not implemented"
**Solution:** Override `toSchema()` method in Input/Output DTOs

### Common Error: "EnvKeyNotFoundException"
**Solution:** 
- Add key to `.env` file, OR
- Set as system environment variable, OR
- Check key name spelling

### Common Error: "Type mismatch in fromJson"
**Solution:** Ensure proper type casting: `json['field'] as Type` or `(json['field'] as num).toDouble()`

---

## Key Differences from Other Frameworks

Help users understand these differences:

| Feature | modular_api | Express.js | Spring Boot |
|---------|-------------|------------|-------------|
| Language | Dart | JavaScript | Java |
| Pattern | Use-case centric | Route-based | Controller-based |
| HTTP Method | POST (default) | Any | Any |
| Validation | Manual in execute() | Middleware | Annotations |
| DI | Manual injection | Built-in | Built-in |
| Testing | useCaseTestHandler | Supertest | MockMvc |

---

## Dependencies to Import

When generating code, include these imports:

```dart
import 'package:modular_api/modular_api.dart'; // Always needed
import 'dart:convert'; // For jsonDecode/jsonEncode
import 'package:test/test.dart'; // For testing
import 'package:http/http.dart' as http; // For HTTP clients (if needed)
```

---

## Complete Minimal Example

When users ask for a complete example, provide this:

```dart
// Input DTO
class HelloInput extends Input {
  final String name;
  
  HelloInput({required this.name});
  
  factory HelloInput.fromJson(Map<String, dynamic> json) {
    return HelloInput(name: json['name'] as String);
  }
  
  @override
  Map<String, dynamic> toJson() => {'name': name};
  
  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'description': 'User name'},
      },
      'required': ['name'],
    };
  }
}

// Output DTO
class HelloOutput extends Output {
  final String message;
  
  HelloOutput({required this.message});
  
  factory HelloOutput.fromJson(Map<String, dynamic> json) {
    return HelloOutput(message: json['message'] as String);
  }
  
  @override
  Map<String, dynamic> toJson() => {'message': message};
  
  @override
  Map<String, dynamic> toSchema() {
    return {
      'type': 'object',
      'properties': {
        'message': {'type': 'string', 'description': 'Greeting message'},
      },
      'required': ['message'],
    };
  }
}

// UseCase
class SayHello extends UseCase<HelloInput, HelloOutput> {
  SayHello(super.input);
  
  static SayHello fromJson(Map<String, dynamic> json) {
    return SayHello(HelloInput.fromJson(json));
  }
  
  @override
  Future<HelloOutput> execute() async {
    return HelloOutput(message: 'Hello, ${input.name}!');
  }
}

// Main
Future<void> main() async {
  final api = ModularApi(basePath: '/api');
  
  api.module('greetings', (m) {
    m.usecase('hello', SayHello.fromJson);
  });
  
  await api.serve(port: 8080);
  print('API running at http://localhost:8080');
  print('Try: curl -X POST http://localhost:8080/api/greetings/hello -H "Content-Type: application/json" -d "{\\"name\\":\\"World\\"}"');
}
```

**Note:** For projects with multiple use cases, prefer creating separate module builder functions:

```dart
// greetings_builder.dart
void buildGreetingsModule(ModuleBuilder m) {
  m.usecase('hello', SayHello.fromJson);
  m.usecase('goodbye', SayGoodbye.fromJson);
}

// main.dart
Future<void> main() async {
  final api = ModularApi(basePath: '/api');
  
  api.module('greetings', buildGreetingsModule);
  api.module('users', buildUsersModule);
  
  await api.serve(port: 8080);
}
```

---

## Quick Reference Commands

**Install package:**
```bash
dart pub add modular_api
```

**Run server:**
```bash
dart run bin/main.dart
```

**Run tests:**
```bash
dart test
```

**Compile to executable:**
```bash
dart compile exe bin/main.dart -o build/server
```

---

## Documentation Index

**📚 Complete Documentation:** [doc/INDEX.md](doc/INDEX.md)

**Essential Guides:**
- **[doc/usecase_dto_guide.md](doc/usecase_dto_guide.md)** — Creating Input/Output DTOs
- **[doc/usecase_implementation.md](doc/usecase_implementation.md)** — Implementing UseCases
- **[doc/testing_guide.md](doc/testing_guide.md)** — Testing with useCaseTestHandler
- **[doc/http_client_guide.md](doc/http_client_guide.md)** — Using httpClient (Flutter & Dart)
- **[doc/authentication_guide.md](doc/authentication_guide.md)** — Token management basics
- **[doc/auth_implementation_guide.md](doc/auth_implementation_guide.md)** — Complete JWT auth system

**Additional Resources:**
- `template/` folder — Full example project with multiple modules
- `example/` folder — Minimal runnable example

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  modular_api: ^0.0.7
```

Or:
```bash
dart pub add modular_api
```

---

## Quick Commands

```bash
# Run server
dart run bin/main.dart

# Run tests
dart test

# Compile to executable
dart compile exe bin/main.dart -o build/server
```

---

## AI Agent Best Practices

When assisting users:

1. ✅ **Always generate complete code** — Include all three DTO methods, full UseCase, and registration
2. ✅ **Reference the detailed guides** — Point to specific documentation files
3. ✅ **Follow the pattern** — Input → UseCase → Output (no HTTP in business logic)
4. ✅ **Include tests** — Show useCaseTestHandler examples
5. ✅ **Suggest file organization** — Especially for multi-module projects
6. ✅ **Explain automatic features** — Health endpoint, docs, error handling
7. ✅ **Validate schemas** — Ensure toSchema() matches class properties
8. ✅ **Use dependency injection** — Never create deps inside execute()
9. ✅ **Provide curl examples** — Help users test immediately
10. ✅ **Keep it simple** — Start minimal, add complexity only when needed

---

**This framework prioritizes clean architecture, testability, and separation of concerns.**
