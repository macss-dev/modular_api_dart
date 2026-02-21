import 'package:modular_api/modular_api.dart';

// ─── Server ───────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final api = ModularApi(basePath: '/api');

  api.module('greetings', buildGreetingsModule);

  await api.serve(port: 8080);
}

// ─── Module Builder ───────────────────────────────────────────────────────────
// In a real project, this would live in its own file:
//   lib/modules/greetings/greetings_builder.dart

void buildGreetingsModule(ModuleBuilder m) {
  m.usecase('hello', HelloWorld.fromJson);
}

// ─── Input DTO ────────────────────────────────────────────────────────────────

class HelloInput implements Input {
  final String name;

  HelloInput({required this.name});

  factory HelloInput.fromJson(Map<String, dynamic> json) =>
      HelloInput(name: (json['name'] ?? '').toString());

  @override
  Map<String, dynamic> toJson() => {'name': name};

  @override
  Map<String, dynamic> toSchema() => {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Name to greet'},
        },
        'required': ['name'],
      };
}

// ─── Output DTO ───────────────────────────────────────────────────────────────

class HelloOutput extends Output {
  final String message;

  HelloOutput({this.message = ''});

  factory HelloOutput.fromJson(Map<String, dynamic> json) =>
      HelloOutput(message: (json['message'] ?? '').toString());

  @override
  Map<String, dynamic> toJson() => {'message': message};

  @override
  Map<String, dynamic> toSchema() => {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': 'Greeting message'},
        },
        'required': ['message'],
      };
}

// ─── UseCase ──────────────────────────────────────────────────────────────────

class HelloWorld implements UseCase<HelloInput, HelloOutput> {
  @override
  final HelloInput input;

  @override
  late HelloOutput output;

  HelloWorld({required this.input}) {
    output = HelloOutput();
  }

  static HelloWorld fromJson(Map<String, dynamic> json) {
    return HelloWorld(input: HelloInput.fromJson(json));
  }

  @override
  String? validate() {
    if (input.name.isEmpty) {
      return 'name is required';
    }
    return null;
  }

  @override
  Future<void> execute() async {
    output = HelloOutput(message: 'Hello, ${input.name}!');
  }

  @override
  Map<String, dynamic> toJson() => output.toJson();
}
