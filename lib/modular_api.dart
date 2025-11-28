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
