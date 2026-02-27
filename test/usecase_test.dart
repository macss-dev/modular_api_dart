import 'dart:convert';

import 'package:test/test.dart';
import 'package:modular_api/src/core/logger/logger.dart';
import 'package:modular_api/src/core/usecase/usecase.dart';
import 'package:modular_api/src/core/usecase/usecase_test_handler.dart';

/// Simple UseCase that sums two integers
class SumUseCase implements UseCase<SumInput, SumOutput> {
  @override
  final SumInput input;

  @override
  ModularLogger? logger;

  SumUseCase({required this.input});

  factory SumUseCase.fromJson(Map<String, dynamic> json) {
    return SumUseCase(input: SumInput.fromJson(json));
  }

  @override
  String? validate() {
    if (input.a == null) return 'a is required';
    if (input.b == null) return 'b is required';
    return null;
  }

  @override
  Future<SumOutput> execute() async {
    final a = input.a ?? 0;
    final b = input.b ?? 0;
    return SumOutput(resultado: a + b);
  }
}

class SumInput implements Input {
  final int? a;
  final int? b;

  SumInput({required this.a, required this.b});

  factory SumInput.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return SumInput(a: parseInt(json['a']), b: parseInt(json['b']));
  }

  @override
  Map<String, dynamic> toJson() => {'a': a, 'b': b};

  @override
  Map<String, dynamic> toSchema() => {
        'type': 'object',
        'properties': {
          'a': {'type': 'integer'},
          'b': {'type': 'integer'},
        },
        'required': ['a', 'b'],
      };
}

class SumOutput implements Output {
  final int resultado;

  SumOutput({required this.resultado});

  factory SumOutput.fromJson(Map<String, dynamic> json) => SumOutput(
        resultado: (json['resultado'] is int)
            ? json['resultado']
            : int.tryParse((json['resultado'] ?? '').toString()) ?? 0,
      );

  @override
  int get statusCode => 200;

  @override
  Map<String, dynamic> toJson() => {'resultado': resultado};

  @override
  Map<String, dynamic> toSchema() => {
        'type': 'object',
        'properties': {
          'resultado': {'type': 'integer'},
        },
        'required': ['resultado'],
      };
}

void main() {
  final handler = useCaseTestHandler((json) => SumUseCase.fromJson(json));

  test(
    'SumUseCase returns success and correct result when inputs provided',
    () async {
      final response = await handler({'a': 3, 'b': 4});
      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resultado'], equals(7));
    },
  );

  test('SumUseCase validation fails when a parameter is missing', () async {
    final response = await handler({'a': 5}); // missing 'b'
    expect(response.statusCode, equals(400));
  });
}
