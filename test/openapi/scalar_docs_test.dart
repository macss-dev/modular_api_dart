import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:modular_api/modular_api.dart';
import 'package:modular_api/src/core/modular_api.dart' show apiRegistry;
import 'package:test/test.dart';

/// PRD-002 assertions for GET /docs — Scalar API Reference.
///
///   1. GET /docs returns HTTP 200.
///   2. Content-Type header is text/html; charset=utf-8.
///   3. Response body contains data-url="/openapi.json".
///   4. Response body contains @scalar/api-reference.
void main() {
  group('GET /docs — Scalar API Reference (PRD-002)', () {
    late HttpServer server;
    late int port;

    setUp(() async {
      apiRegistry.routes.clear();

      final api = ModularApi(
        basePath: '/api',
        title: 'Pet Store',
        version: '1.0.0',
      );

      server = await api.serve(port: 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close(force: true);
      apiRegistry.routes.clear();
    });

    test('returns HTTP 200', () async {
      final resp = await http.get(Uri.parse('http://localhost:$port/docs'));
      expect(resp.statusCode, 200);
    });

    test('returns Content-Type text/html', () async {
      final resp = await http.get(Uri.parse('http://localhost:$port/docs'));
      expect(resp.headers['content-type'], contains('text/html'));
    });

    test('body contains data-url="/openapi.json"', () async {
      final resp = await http.get(Uri.parse('http://localhost:$port/docs'));
      expect(resp.body, contains('data-url="/openapi.json"'));
    });

    test('body contains @scalar/api-reference CDN script', () async {
      final resp = await http.get(Uri.parse('http://localhost:$port/docs'));
      expect(resp.body, contains('@scalar/api-reference'));
    });

    test('interpolates the API title in the HTML', () async {
      final resp = await http.get(Uri.parse('http://localhost:$port/docs'));
      expect(resp.body, contains('Pet Store'));
    });

    test('returns a complete HTML document', () async {
      final resp = await http.get(Uri.parse('http://localhost:$port/docs'));
      expect(resp.body, contains('<!DOCTYPE html>'));
      expect(resp.body, contains('</html>'));
    });
  });
}
