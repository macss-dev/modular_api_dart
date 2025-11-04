// This file re-exports the correct implementation depending on the platform.
//
// - If dart:io is available (CLI, server, desktop): use file_storage_io.dart
// - If dart:io is not available (web): use file_storage_stub.dart
export 'file_storage_stub.dart' if (dart.library.io) 'file_storage_io.dart';
