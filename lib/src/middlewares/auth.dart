import 'package:modular_api/modular_api.dart';

/// Authentication middleware that verifies the JWT access token
///
/// This middleware:
/// - Extracts the token from the Authorization header (format: `Bearer <token>`)
/// - Verifies that the token is valid using JwtHelper
/// - Allows access only if the token is of type "access"
/// - Excludes public routes such as /auth/* and /health
///
/// Usage:
/// ```dart
/// final api = ModularApi(basePath: '/api');
/// api.use(authMiddleware()); // Apply before registering protected modules
/// ```
Middleware authMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      // Get full path
      final fullPath = request.requestedUri.path;

      // Public routes that do not require authentication
      // Check if the path starts with any of these
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

      // Verify "Bearer <token>" format
      if (!authHeader.startsWith('Bearer ')) {
        return Response.unauthorized(
          'Invalid authorization format. Expected: Bearer <token>',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final token = authHeader.substring(7); // Remove "Bearer "

      if (token.isEmpty) {
        return Response.unauthorized(
          'Empty token',
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify JWT token
      try {
        final payload = JwtHelper.verifyToken(token);
        
        // Check that it is an access token
        final tokenType = payload['type'] as String?;
        if (tokenType != 'access') {
          return Response.forbidden(
            'Invalid token type. Expected: access token',
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Token is valid, continue with the request
        // Add user information to the context (optional)
        final userId = payload['sub'] as String?;
        final username = payload['username'] as String?;
        
        // We can add this information to the request if needed
        final requestWithUser = request.change(context: {
          'userId': userId,
          'username': username,
        });

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
