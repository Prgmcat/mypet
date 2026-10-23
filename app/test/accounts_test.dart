import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/accounts.dart';

SavedAccount _account(String username, {String password = 'pw'}) =>
    SavedAccount(
      username: username,
      password: password,
      displayName: username,
      lastUsedAt: '2026-10-23T00:00:00Z',
    );

void main() {
  test('saved account survives JSON round trip', () {
    const account = SavedAccount(
      username: 'demo',
      password: 'Passw0rd1',
      displayName: '小管家',
      lastUsedAt: '2026-10-23T10:00:00Z',
    );
    final restored = SavedAccount.fromJson(account.toJson());
    expect(restored.username, 'demo');
    expect(restored.password, 'Passw0rd1');
    expect(restored.displayName, '小管家');
    expect(restored.lastUsedAt, '2026-10-23T10:00:00Z');
  });

  test('upsert moves the newest account to the front and replaces duplicates',
      () {
    var list = <SavedAccount>[];
    list = upsertAccount(list, _account('alice', password: 'old'));
    list = upsertAccount(list, _account('bob'));
    expect(list.map((a) => a.username), ['bob', 'alice']);

    list = upsertAccount(list, _account('ALICE', password: 'new'));
    expect(list.map((a) => a.username), ['ALICE', 'bob']);
    expect(list.first.password, 'new');
  });

  test('upsert keeps at most the configured number of accounts', () {
    var list = <SavedAccount>[];
    for (var i = 0; i < 12; i++) {
      list = upsertAccount(list, _account('user$i'), max: 8);
    }
    expect(list.length, 8);
    expect(list.first.username, 'user11');
    expect(list.last.username, 'user4');
  });
}
