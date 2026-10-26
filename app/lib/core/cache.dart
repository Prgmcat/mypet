import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'server_scope.dart';

/// Small read-only cache so the app can show the last known data offline.
/// Server remains the only source of truth; cache is per user and clearable.
class LocalCache {
  LocalCache._();

  static String _prefix(String userId) =>
      '${ServerScope.prefix}mypet_cache_${userId}_';

  static String _key(String userId, String name) => '${_prefix(userId)}$name';

  static Future<void> savePets(String userId, List<Pet> pets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(userId, 'pets'), jsonEncode(pets.map((p) => p.toJson()).toList()));
    await prefs.setString(_key(userId, 'saved_at'),
        DateTime.now().toIso8601String());
  }

  static Future<List<Pet>> loadPets(String userId) async {
    final raw = await _read(userId, 'pets');
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Pet.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveRecords(
      String userId, String petId, List<HealthRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(userId, 'records_$petId'),
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  static Future<List<HealthRecord>> loadRecords(
      String userId, String petId) async {
    final raw = await _read(userId, 'records_$petId');
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => HealthRecord.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveWeights(
      String userId, String petId, List<WeightRecord> weights) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(userId, 'weights_$petId'),
      jsonEncode(weights.map((w) => w.toJson()).toList()),
    );
  }

  static Future<List<WeightRecord>> loadWeights(
      String userId, String petId) async {
    final raw = await _read(userId, 'weights_$petId');
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => WeightRecord.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveReminders(
      String userId, String status, List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(userId, 'reminders_$status'),
      jsonEncode(reminders.map((r) => r.toJson()).toList()),
    );
    await prefs.setString(_key(userId, 'saved_at'),
        DateTime.now().toIso8601String());
  }

  static Future<List<Reminder>> loadReminders(
      String userId, String status) async {
    final raw = await _read(userId, 'reminders_$status');
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<DateTime?> lastSaved(String userId) async {
    final raw = await _read(userId, 'saved_at');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _prefix(userId);
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }

  static Future<String?> _read(String userId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(userId, name));
  }
}
