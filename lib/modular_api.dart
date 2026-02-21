/// Public library for modular_api package.
/// Use-case centric API toolkit for Dart — Shelf + OpenAPI, nothing more.

library;

// Shelf types
export 'package:shelf/shelf.dart' show Middleware, Handler, Request, Response;

// Core
export 'src/core/modular_api.dart' show ModularApi, ModuleBuilder;
export 'src/core/usecase/usecase.dart' show UseCase, Input, Output;
export 'src/core/usecase/use_case_exception.dart' show UseCaseException;
export 'src/core/usecase/usecase_test_handler.dart' show useCaseTestHandler;

// Middlewares
export 'src/middlewares/cors.dart' show exampleCorsMiddleware;

// OpenAPI
export 'src/openapi/openapi.dart' show OpenApi;
