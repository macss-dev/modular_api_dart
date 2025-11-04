/// Public library for modular_api package.
/// This library provides a use case centric API toolkit for Dart applications,
/// including Shelf UseCase base class, HTTP adapters, CORS/API-Key middlewares,
/// and OpenAPI specifications.

library;

// Shelf types
export 'package:shelf/shelf.dart' show Middleware, Handler, Request, Response;

// Core
export 'src/core/modular_api.dart' show ModularApi, ModuleBuilder;
export 'src/core/usecase/usecase.dart' show UseCase, Input, Output;
export 'src/core/usecase/usecase_test_handler.dart' show useCaseTestHandler;

// Middlewares
export 'src/middlewares/cors.dart' show exampleCorsMiddleware;
export 'src/middlewares/apikey.dart' show exampleApiKeyMiddleware;

// Clients
export 'src/clients/http/http_client.dart' show httpClient;
export 'src/clients/http/token.dart' show Token;
export 'src/clients/http/token_vault.dart' show TokenVault;
export 'src/clients/http/auth_exceptions.dart' show AuthReLoginException;
export 'src/clients/http/storage/token_storage_adapter.dart'
    show TokenStorageAdapter, TokenStorageException;
export 'src/clients/http/storage/memory_storage_adapter.dart'
    show MemoryStorageAdapter;
export 'src/clients/http/storage/file_storage_adapter.dart'
    show
        FileStorageAdapter,
        AesGcmEncryptor,
        TokenEncryptor,
        PassphraseProvider;
export 'src/clients/db/db_client.dart' show DbClient;

// OpenAPI
export 'src/openapi/openapi.dart' show OpenApi;

// utils
export 'src/utils/env.dart' show Env;
export 'src/utils/get_local_ip.dart' show getLocalIp;

// Auth utilities
export 'src/auth/jwt_helper.dart' show JwtHelper, JwtException;
export 'src/auth/password_hasher.dart' show PasswordHasher;
export 'src/auth/token_hasher.dart' show TokenHasher;
