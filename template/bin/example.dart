import 'dart:io';
import 'package:example/middlewares/auth_middleware.dart';
import 'package:example/modules/auth/auth_builder.dart';
import 'package:modular_api/modular_api.dart';
import 'package:example/modules/module1/hello_world.dart';
import 'package:example/modules/module2/module2_builder.dart';
import 'package:example/modules/module3/module3_builder.dart';

Future<void> main(List<String> args) async {
  // Load environment variables
  // require the .env file in the project root or set system environment variables
  final port = Env.getInt('PORT');

  final api = ModularApi(basePath: '/api');

  // Global middlewares
  api.use(exampleCorsMiddleware());
  
  // Auth middleware (will be applied to all routes except public ones)
  api.use(authMiddleware());

  // Authentication module (public routes handled by authMiddleware)
  api.module('auth', authBuilder);

  // Protected modules (require access token)
  // POST api/module1/hello-world (protected)
  api.module('module1', (m) {
    m.usecase('hello-world', HelloWorld.fromJson);
  });

  // Modular builder from external file (protected)
  api.module('module2', module2Builder);
  api.module('module3', module3Builder);

  await api.serve(port: port);

  /// OpenAPI docs URL
  /// You can access the docs at http://localhost:<port>/docs
  stdout.writeln('Docs on http://localhost:$port/docs');
  stdout.writeln('Health check on http://localhost:$port/health');
}
