import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiStoredMessage {
  AiStoredMessage({
    required this.role,
    required this.content,
    this.riskLevel = '',
    this.feedback = 0,
    this.createdAt = '',
  });

  final String role;
  final String content;
  final String riskLevel; // '', 'l1', 'l2', 'l3'
  int feedback; // 0 none, 1 useful, -1 not useful
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'riskLevel': riskLevel,
        'feedback': feedback,
        'createdAt': createdAt,
      };

  factory AiStoredMessage.fromJson(Map<String, dynamic> json) =>
      AiStoredMessage(
        role: (json['role'] as String?) ?? 'assistant',
        content: (json['content'] as String?) ?? '',
        riskLevel: (json['riskLevel'] as String?) ?? '',
        feedback: (json['feedback'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as String?) ?? '',
      );
}

class AiSession {
  AiSession({
    required this.id,
    required this.petId,
    required this.petName,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.providerId = '',
  });

  final String id;
  String petId;
  String petName;
  String title;
  String updatedAt;
  final List<AiStoredMessage> messages;

  /// Provider chosen for this conversation; empty means the default.
  String providerId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'petName': petName,
        'title': title,
        'updatedAt': updatedAt,
        'providerId': providerId,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory AiSession.fromJson(Map<String, dynamic> json) => AiSession(
        id: (json['id'] as String?) ?? '',
        petId: (json['petId'] as String?) ?? '',
        petName: (json['petName'] as String?) ?? '',
        title: (json['title'] as String?) ?? '新对话',
        updatedAt: (json['updatedAt'] as String?) ?? '',
        providerId: (json['providerId'] as String?) ?? '',
        messages: ((json['messages'] as List?) ?? const [])
            .map((e) => AiStoredMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AiSessionStore {
  AiSessionStore._();

  static String _key(String userId) => 'mypet_ai_sessions_$userId';

  static Future<List<AiSession>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AiSession.fromJson(e as Map<String, dynamic>))
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(String userId, List<AiSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = sessions.take(30).toList();
    await prefs.setString(
      _key(userId),
      jsonEncode(trimmed.map((s) => s.toJson()).toList()),
    );
  }

  static Future<void> upsert(String userId, AiSession session) async {
    final sessions = await load(userId);
    session.updatedAt = DateTime.now().toIso8601String();
    if (session.messages.length > 100) {
      session.messages.removeRange(0, session.messages.length - 100);
    }
    sessions.removeWhere((s) => s.id == session.id);
    sessions.insert(0, session);
    await saveAll(userId, sessions);
  }

  static Future<void> delete(String userId, String sessionId) async {
    final sessions = await load(userId);
    sessions.removeWhere((s) => s.id == sessionId);
    await saveAll(userId, sessions);
  }
}
