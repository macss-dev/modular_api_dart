import 'package:modular_api/modular_api.dart';

/// Authentication middleware that validates JWT access tokens.
///
/// This middleware:
/// - Extracts the token from the Authorization header (format: `Bearer <token>`)
/// - Validates the token using `JwtHelper`
/// - Allows access only if the token type is `access`
/// - Skips authentication for public routes such as `/auth/*` and `/health`
///
/// Usage:
/// ```dart
/// final api = ModularApi(basePath: '/api');
/// api.use(authMiddleware()); // Apply before registering protected modules
/// ```
Middleware authMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      // Get full request path
      final fullPath = request.requestedUri.path;

      // Public routes that do not require authentication
      if (fullPath.startsWith('/health') ||
          fullPath.startsWith('/docs') ||
          fullPath.contains('/api/auth/')) {
        return handler(request);
      }

      // Extract token from Authorization header
      final authHeader = request.headers['authorization'];

      if (authHeader == null) {
        return Response.unauthorized(
          'Missing authorization header',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Expect format "Bearer <token>"
      if (!authHeader.startsWith('Bearer ')) {
        return Response.unauthorized(
          'Invalid authorization format. Expected: Bearer <token>',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final token = authHeader.substring(7); // Remove "Bearer " prefix

      if (token.isEmpty) {
        return Response.unauthorized(
          'Empty token',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Validate JWT token
      try {
        final payload = JwtHelper.verifyToken(token);

        // Ensure token is an access token
        final tokenType = payload['type'] as String?;
        if (tokenType != 'access') {
          return Response.forbidden(
            'Invalid token type. Expected: access token',
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Token valid — continue with the request
        // Optionally add user information to the request context
        final userId = payload['sub'] as String?;
        final username = payload['username'] as String?;

        final requestWithUser = request.change(
          context: {'userId': userId, 'username': username},
        );

        return handler(requestWithUser);
      } on JwtException catch (e) {
        return Response.unauthorized(
          'Invalid token: ${e.message}',
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: 'Authentication error: $e',
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
