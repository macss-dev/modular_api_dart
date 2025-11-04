import 'package:modular_api/modular_api.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryStorageAdapter', () {
    late MemoryStorageAdapter adapter;

    setUp(() {
      adapter = MemoryStorageAdapter.shared();
      // Clean state before each test
      adapter.deleteAll();
    });

    test('should be a singleton', () {
      final instance1 = MemoryStorageAdapter.shared();
      final instance2 = MemoryStorageAdapter.shared();
      expect(identical(instance1, instance2), isTrue);
    });

    test('should save and read refresh token', () async {
      await adapter.saveRefresh('user1', 'token-123');
      final token = await adapter.readRefresh('user1');
      expect(token, equals('token-123'));
    });

    test('should return null for non-existent user', () async {
      final token = await adapter.readRefresh('non-existent');
      expect(token, isNull);
    });

    test('should update existing token', () async {
      await adapter.saveRefresh('user1', 'old-token');
      await adapter.saveRefresh('user1', 'new-token');
      final token = await adapter.readRefresh('user1');
      expect(token, equals('new-token'));
    });

    test('should delete refresh token', () async {
      await adapter.saveRefresh('user1', 'token-123');
      await adapter.deleteRefresh('user1');
      final token = await adapter.readRefresh('user1');
      expect(token, isNull);
    });

    test('should handle multiple users', () async {
      await adapter.saveRefresh('user1', 'token-1');
      await adapter.saveRefresh('user2', 'token-2');
      await adapter.saveRefresh('user3', 'token-3');

      expect(await adapter.readRefresh('user1'), equals('token-1'));
      expect(await adapter.readRefresh('user2'), equals('token-2'));
      expect(await adapter.readRefresh('user3'), equals('token-3'));
      expect(adapter.tokenCount, equals(3));
    });

    test('should delete all tokens', () async {
      await adapter.saveRefresh('user1', 'token-1');
      await adapter.saveRefresh('user2', 'token-2');
      await adapter.saveRefresh('user3', 'token-3');

      await adapter.deleteAll();

      expect(await adapter.readRefresh('user1'), isNull);
      expect(await adapter.readRefresh('user2'), isNull);
      expect(await adapter.readRefresh('user3'), isNull);
      expect(adapter.hasTokens, isFalse);
      expect(adapter.tokenCount, equals(0));
    });

    test('should track token count', () async {
      expect(adapter.tokenCount, equals(0));
      expect(adapter.hasTokens, isFalse);

      await adapter.saveRefresh('user1', 'token-1');
      expect(adapter.tokenCount, equals(1));
      expect(adapter.hasTokens, isTrue);

      await adapter.saveRefresh('user2', 'token-2');
      expect(adapter.tokenCount, equals(2));

      await adapter.deleteRefresh('user1');
      expect(adapter.tokenCount, equals(1));

      await adapter.deleteAll();
      expect(adapter.tokenCount, equals(0));
      expect(adapter.hasTokens, isFalse);
    });

    test('should list user IDs', () async {
      await adapter.saveRefresh('user1', 'token-1');
      await adapter.saveRefresh('user2', 'token-2');
      await adapter.saveRefresh('user3', 'token-3');

      final userIds = adapter.userIds;
      expect(userIds.length, equals(3));
      expect(userIds, containsAll(['user1', 'user2', 'user3']));
    });
  });

  group('TokenVault with MemoryStorageAdapter', () {
    setUp(() async {
      TokenVault.configure(MemoryStorageAdapter.shared());
      await TokenVault.deleteAll();
    });

    test('should save and read through TokenVault', () async {
      await TokenVault.saveRefresh('user123', 'rt-xyz');
      final token = await TokenVault.readRefresh('user123');
      expect(token, equals('rt-xyz'));
    });

    test('should add rt: prefix to keys', () async {
      await TokenVault.saveRefresh('user1', 'token-1');

      final adapter = MemoryStorageAdapter.shared();
      final userIds = adapter.userIds;

  // TokenVault should add the 'rt:' prefix
  expect(userIds, contains('rt:user1'));
      expect(userIds, isNot(contains('user1')));
    });

    test('should delete through TokenVault', () async {
      await TokenVault.saveRefresh('user1', 'token-1');
      await TokenVault.deleteRefresh('user1');
      final token = await TokenVault.readRefresh('user1');
      expect(token, isNull);
    });

    test('should delete all through TokenVault', () async {
      await TokenVault.saveRefresh('user1', 'token-1');
      await TokenVault.saveRefresh('user2', 'token-2');
      await TokenVault.deleteAll();

      expect(await TokenVault.readRefresh('user1'), isNull);
      expect(await TokenVault.readRefresh('user2'), isNull);
    });
  });
}
