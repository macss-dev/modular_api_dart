import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../logger/logger.dart';
import 'usecase.dart';

/// Handler for unit testing UseCases
/// Returns a function that runs the unit test flow for a UseCase
/// and returns a [Response] so callers can assert on status code and body.
Future<Response> Function(Map<String, dynamic>) useCaseTestHandler(
  UseCase Function(Map<String, dynamic>) fromJson, {
  ModularLogger? logger,
}) {
  const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  return (Map<String, dynamic> inputJson) async {
    try {
      stdout.writeln('\n=== STARTING TEST ===');
      stdout.writeln('Input JSON: $inputJson');

      /// 1. Build the UseCase from JSON
      stdout.writeln('\n[1/4] Building UseCase from JSON...');
      final useCase = fromJson(inputJson);
      stdout.writeln('✓ UseCase built successfully');

      /// 2. Validate input data
      stdout.writeln('\n[2/4] Validating input data...');
      final validationError = useCase.validate();
      if (validationError != null) {
        stderr.writeln('✗ VALIDATION ERROR: $validationError');
        stderr.writeln('\n=== TEST FAILED (validation) ===\n');
        return Response(
          400,
          headers: jsonHeaders,
          body: jsonEncode({'error': validationError}),
        );
      }
      stdout.writeln('✓ Validation successful');

      /// 3. Inject logger and execute the use case
      useCase.logger = logger;
      stdout.writeln('\n[3/4] Executing UseCase...');
      final output = await useCase.execute();
      stdout.writeln('✓ Execution completed');

      // 4. Convert the response to JSON (optional, for inspection)
      stdout.writeln('\n[4/4] Generating JSON response...');
      final outputJson = output.toJson();
      stdout.writeln('✓ Response generated: $outputJson');

      // 5. Everything went well
      stdout.writeln('\n=== TEST SUCCEEDED ===\n');
      return Response(
        output.statusCode,
        headers: jsonHeaders,
        body: jsonEncode(outputJson),
      );
    } catch (e, stackTrace) {
      // Capture and display detailed error information
      stderr.writeln('\n${'=' * 80}');
      stderr.writeln('CRITICAL ERROR DURING TEST EXECUTION');
      stderr.writeln('=' * 80);
      stderr.writeln('\nERROR TYPE: ${e.runtimeType}');
      stderr.writeln('\nERROR MESSAGE:');
      stderr.writeln(e.toString());
      stderr.writeln('\nFULL STACK TRACE:');
      stderr.writeln(stackTrace.toString());
      stderr.writeln('\n${'=' * 80}');
      stderr.writeln('=== TEST FAILED ===');
      stderr.writeln('=' * 80);
      return Response(
        500,
        headers: jsonHeaders,
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  };
}
