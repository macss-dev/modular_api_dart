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
export 'src/core/oauth_handler.dart' show createOAuthTokenHandler;

// Auth
export 'src/auth/jwt_helper.dart' show JwtHelper;
export 'src/auth/password_hasher.dart';
export 'src/auth/token_hasher.dart';
export 'src/auth/oauth_types.dart'
    show
        OAuthClient,
        TokenRequest,
        TokenResponse,
        TokenErrorResponse,
        AccessToken;
export 'src/auth/oauth_service.dart' show OAuthService;

// Middlewares
export 'src/middlewares/cors.dart' show exampleCorsMiddleware;
export 'src/middlewares/apikey.dart' show exampleApiKeyMiddleware;
export 'src/middlewares/bearer.dart' show bearer, requireAuth;

// OpenAPI
export 'src/openapi/openapi.dart' show OpenApi;

// utils
export 'src/utils/env.dart' show Env;
export 'src/utils/get_local_ip.dart' show getLocalIp;
