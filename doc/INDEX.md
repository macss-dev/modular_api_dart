# modular_api Documentation Index

Entry point for implementing vertical features.

---

## Development Flow

Implement features following this **bottom-up** vertical flow with TDD at each stage:

```
Database (DDL) → Repository (stage 1) → UseCase (stage 2) → API Routes (stage 3)→ Service (App) → Controller (stage 4) → UI (stage 5)
```

Each stage must be tested before moving to the next.

Stage 1: Unit tests for Repositories
Stage 2: Unit tests for UseCases using `useCaseTestHandler()`
Stage 3: E2E tests for API routes with running server and `httpClient()`
Stage 4: Unit tests for Controllers
Stage 5: Integration tests for complete user flows
---

## Stage 1: Repository and Data Access

**Objective**: Implement SQL queries and database interaction layer.

**Guide**: None (standard repository pattern)

**Steps**:
1. Write repository unit tests
2. Implement repository methods with SQL queries
3. Test against database instance
4. Validate queries execute correctly and map to entities

**Location**: `api/lib/modules/<module>/`

**Validation**:
- ✅ Queries execute without errors
- ✅ Results map correctly to domain entities
- ✅ Error handling for connection and constraints

---

## Stage 2: UseCase Implementation

**Objective**: Implement business logic in `execute()` method.

**Primary Guide**: [usecase_implementation.md](./usecase_implementation.md)  
**Required First**: [usecase_dto_guide.md](./usecase_dto_guide.md)

**Steps**:
1. Create Input/Output DTOs following the DTO guide
2. Implement UseCase class extending `UseCase<Input, Output>`
3. Write unit tests using `useCaseTestHandler`
4. Implement `execute()` method with business logic
5. Test and refactor until all tests pass

**Location**: `api/lib/modules/<module>/usecases/`

**Key Points**:
- UseCases receive Input DTOs and return Output DTOs
- Business logic stays pure (no HTTP concerns)
- Dependencies injected via constructor
- Validation in `validate()` method (optional) or at start of `execute()`

**Testing Guide**: [testing_guide.md](./testing_guide.md)

**Validation**:
- ✅ Business logic executes correctly
- ✅ Edge cases handled properly
- ✅ Transactions and complex operations work as expected

---

## Stage 3: API Integration

**Objective**: Expose UseCases via HTTP endpoints and validate end-to-end backend flows.

**Guides**: 
- Core framework: [AGENTS.md](../AGENTS.md)
- Authentication: [auth_implementation_guide.md](./auth_implementation_guide.md) (if implementing auth)

**Steps**:
1. Register modules and usecases in `ModularApi`
2. Configure middlewares (CORS, API key, auth)
3. Write E2E tests that start the server
4. Test HTTP flows with `httpClient()` or `package:http`
5. Validate routes, serialization, and middlewares

**Location**: `api/routes/` and `api/middlewares/`

**Example Registration**:
```dart
final api = ModularApi(basePath: '/api');

api.module('users', (m) {
  m.usecase('create', CreateUser.fromJson);
  m.usecase('get', GetUser.fromJson);
});

api.use(cors());
await api.serve(port: 8080);
```

**Validation**:
- ✅ HTTP routes respond with correct status codes
- ✅ DTOs serialize/deserialize properly
- ✅ Middlewares function as expected
- ✅ End-to-end backend flows work correctly

---

## Stage 4: Service and Controller (Client App)

**Objective**: Implement communication layer and presentation logic in client application.

**Primary Guide**: [http_client_guide.md](./http_client_guide.md)  
**Authentication**: [authentication_guide.md](./authentication_guide.md)

**Steps**:
1. Configure `TokenVault` adapter for platform (Flutter/CLI/Server)
2. Create Service class using `httpClient()` to communicate with API
3. Implement Controller to orchestrate Service calls
4. Write unit tests for Controller logic
5. Test and refactor until all tests pass

**Location**: `app/services/` and `app/controllers/`

**Key Points**:
- **No direct external API calls from app** — all requests go through backend API
- Use `httpClient()` for automatic authentication management
- Service encapsulates HTTP calls per module
- Controller manages state and orchestrates Service calls
- Each view/widget has its own Controller

**httpClient Features**:
- Auto-attach Bearer tokens (`auth: true`)
- Auto-capture tokens from login
- Auto-refresh on 401 responses
- Throws `AuthReLoginException` when refresh fails

**Validation**:
- ✅ Controller orchestrates Service calls correctly
- ✅ Service constructs HTTP requests properly
- ✅ Network errors handled appropriately
- ✅ State updates correctly based on responses

---

## Stage 5: UI and Integration Tests

**Objective**: Implement views and validate complete user flows.

**Guide**: None (platform-specific UI implementation)

**Steps**:
1. Write integration tests for critical user flows
2. Implement views/widgets that react to Controller state
3. Connect UI events (tap, submit) to Controller methods
4. Run E2E tests and refactor until all pass

**Location**: `app/ui/` or `app/views/`

**Validation**:
- ✅ Complete flows work end-to-end (UI → API → DB → UI)
- ✅ User interactions produce expected results
- ✅ UI reflects states correctly (loading, success, error)

---

## Quick Reference: Guides by Topic

### Core Framework
- **[AGENTS.md](../AGENTS.md)** — Framework overview, ModularApi usage, module registration
- **[usecase_dto_guide.md](./usecase_dto_guide.md)** — Creating Input/Output DTOs
- **[usecase_implementation.md](./usecase_implementation.md)** — Implementing UseCases
- **[testing_guide.md](./testing_guide.md)** — Testing UseCases with `useCaseTestHandler`

### HTTP Client & Authentication
- **[http_client_guide.md](./http_client_guide.md)** — Using `httpClient` in Flutter and Dart apps
- **[authentication_guide.md](./authentication_guide.md)** — Token management, storage adapters
- **[auth_implementation_guide.md](./auth_implementation_guide.md)** — Complete JWT auth system implementation

---

## Implementation Checklist

Use this checklist when implementing a new feature:

### Phase 1: Backend
- [ ] Design database schema (DDL scripts)
- [ ] Define DTO contracts (Input/Output)
- [ ] Implement Repository with tests
- [ ] Implement UseCase with tests
- [ ] Register UseCase in ModularApi
- [ ] Write E2E API tests
- [ ] Validate all backend tests pass

### Phase 2: Client App
- [ ] Configure TokenVault adapter
- [ ] Implement Service class with `httpClient()`
- [ ] Implement Controller with tests
- [ ] Implement UI views/widgets
- [ ] Write integration tests
- [ ] Validate all app tests pass

### Phase 3: Validation
- [ ] Run complete E2E tests (UI → DB → UI)
- [ ] Verify error handling at all layers
- [ ] Check security (auth, validation, sanitization)
- [ ] Review code for consistency and best practices

---

## Key Principles

1. **Test-Driven Development (TDD)** — Write tests before implementation at every stage
2. **Insert-Only Database** — Immutability, auditability, traceability
3. **Vertical Slicing** — Implement complete features from DB to UI
4. **Clean Separation** — Clear boundaries between layers
5. **No Direct External APIs from App** — All external calls through backend API
6. **UseCase Purity** — Business logic independent of HTTP concerns
7. **Dependency Injection** — Inject dependencies, don't create them internally

---

## Common Patterns

### UseCase Factory Pattern
```dart
class MyUseCase extends UseCase<MyInput, MyOutput> {
  MyUseCase(super.input);
  
  static MyUseCase fromJson(Map<String, dynamic> json) {
    return MyUseCase(MyInput.fromJson(json));
  }
  
  @override
  Future<MyOutput> execute() async {
    // Business logic
    return MyOutput(result: data);
  }
}
```

### Module Builder Pattern
```dart
void buildMyModule(ModuleBuilder m) {
  m.usecase('action1', UseCase1.fromJson);
  m.usecase('action2', UseCase2.fromJson);
}

// In main.dart
api.module('mymodule', buildMyModule);
```

### httpClient Pattern
```dart
// Login
final response = await httpClient(
  method: 'POST',
  baseUrl: baseUrl,
  endpoint: 'api/auth/login',
  body: {'username': user, 'password': pass},
  auth: true,
  user: userId,
);

// Protected request
try {
  final data = await httpClient(
    method: 'POST',
    baseUrl: baseUrl,
    endpoint: 'api/users/profile',
    body: {'user_id': 123},
    auth: true,
    user: userId,
  );
} on AuthReLoginException {
  // Navigate to login
}
```

---

## Getting Help

- Framework issues: Check [AGENTS.md](../AGENTS.md)
- DTO problems: Review [usecase_dto_guide.md](./usecase_dto_guide.md)
- UseCase implementation: See [usecase_implementation.md](./usecase_implementation.md)
- Testing issues: Consult [testing_guide.md](./testing_guide.md)
- HTTP client problems: Read [http_client_guide.md](./http_client_guide.md)
- Auth issues: Review [auth_implementation_guide.md](./auth_implementation_guide.md)

---

**Start here, follow the vertical flow, test at every stage, and build complete features from database to UI.**
