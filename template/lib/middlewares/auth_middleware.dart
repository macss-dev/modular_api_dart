import 'package:shelf/shelf.dart';

Middleware authMiddleware() {

  return (Handler handler) {
    return (Request request) async {
      
      final response = await handler(request);
      return response;
    };
  };
}
