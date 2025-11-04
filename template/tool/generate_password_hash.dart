import 'package:modular_api/modular_api.dart';

/// Helper script to generate bcrypt password hashes for seed data.
///
/// Run with:
/// ```
/// dart run tool/generate_password_hash.dart
/// ```
void main() {
  final passwords = {'abc123': '', 'password123': ''};

  print('Generating bcrypt password hashes...\n');
  print('=' * 60);

  for (final password in passwords.keys) {
    final hash = PasswordHasher.hash(password);
    passwords[password] = hash;

    print('\nPassword: $password');
    print('Hash:     $hash');
    print('-' * 60);
  }

  print('\n✓ All hashes generated successfully!\n');
  print('Copy these hashes to db/seed.sql\n');
}
