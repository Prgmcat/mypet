import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A locally remembered login. Passwords live only in the platform secure
/// storage (Android Keystore-backed), never in shared preferences or logs.
class SavedAccount {
  final String username;
  final String password;
  final String displayName;
  final String lastUsedAt;

  const SavedAccount({
    required this.username,
    required this.password,
    required this.displayName,
    required this.lastUsedAt,
  });

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        lastUsedAt: (json['lastUsedAt'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'displayName': displayName,
        'lastUsedAt': lastUsedAt,
      };
}

/// Inserts [next] at the front, replacing any entry with the same username
/// (case-insensitive), and keeps at most [max] entries.
List<SavedAccount> upsertAccount(
  List<SavedAccount> current,
  SavedAccount next, {
  int max = 8,
}) {
  final key = next.username.toLowerCase();
  final result = current
      .where((a) => a.username.toLowerCase() != key)
      .toList(growable: true);
  result.insert(0, next);
  if (result.length > max) result.removeRange(max, result.length);
  return result;
}

class AccountStore {
  AccountStore._();

  static const _key = 'mypet_saved_accounts';
  static const _max = 8;
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<List<SavedAccount>> load() async {
    try {
      final raw = await _secure.read(key: _key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SavedAccount.fromJson)
          .where((a) => a.username.isNotEmpty && a.password.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // An unreadable store must not block sign-in.
      return const [];
    }
  }

  /// Remembers a successfully used login so it can be tapped later.
  static Future<void> remember({
    required String username,
    required String password,
    required String displayName,
  }) async {
    try {
      final current = await load();
      final next = SavedAccount(
        username: username,
        password: password,
        displayName: displayName,
        lastUsedAt: DateTime.now().toIso8601String(),
      );
      final merged = upsertAccount(current, next, max: _max);
      await _secure.write(
        key: _key,
        value: jsonEncode(merged.map((a) => a.toJson()).toList()),
      );
    } catch (_) {
      // Saving is a convenience; never fail the login because of it.
    }
  }

  static Future<void> remove(String username) async {
    try {
      final key = username.toLowerCase();
      final current = await load();
      final left =
          current.where((a) => a.username.toLowerCase() != key).toList();
      if (left.isEmpty) {
        await _secure.delete(key: _key);
        return;
      }
      await _secure.write(
        key: _key,
        value: jsonEncode(left.map((a) => a.toJson()).toList()),
      );
    } catch (_) {
      // Ignore: the list is cosmetic.
    }
  }
}
