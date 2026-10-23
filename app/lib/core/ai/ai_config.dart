import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.isDefault = false,
    this.supportsVision = false,
    this.supportsTools = false,
  });

  final String id;
  final String name;

  /// `openai` for OpenAI-compatible endpoints, `anthropic` for Messages API.
  final String kind;
  final String baseUrl;
  final String model;
  final bool isDefault;
  final bool supportsVision;
  final bool supportsTools;

  AiProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? model,
    bool? isDefault,
    bool? supportsVision,
    bool? supportsTools,
  }) {
    return AiProviderConfig(
      id: id,
      name: name ?? this.name,
      kind: kind,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      isDefault: isDefault ?? this.isDefault,
      supportsVision: supportsVision ?? this.supportsVision,
      supportsTools: supportsTools ?? this.supportsTools,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'baseUrl': baseUrl,
        'model': model,
        'isDefault': isDefault,
        'supportsVision': supportsVision,
        'supportsTools': supportsTools,
      };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) =>
      AiProviderConfig(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'openai',
        baseUrl: (json['baseUrl'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        isDefault: json['isDefault'] == true,
        supportsVision: json['supportsVision'] == true,
        supportsTools: json['supportsTools'] == true,
      );
}

const aiProviderPresets = <AiProviderConfig>[
  AiProviderConfig(
    id: 'openai',
    name: 'OpenAI',
    kind: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    supportsVision: true,
    supportsTools: true,
  ),
  AiProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    kind: 'openai',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
  ),
  AiProviderConfig(
    id: 'qwen',
    name: '通义千问（兼容模式）',
    kind: 'openai',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  ),
  AiProviderConfig(
    id: 'moonshot',
    name: 'Moonshot',
    kind: 'openai',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
  ),
  AiProviderConfig(
    id: 'zhipu',
    name: '智谱 GLM',
    kind: 'openai',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
  ),
  AiProviderConfig(
    id: 'anthropic',
    name: 'Anthropic',
    kind: 'anthropic',
    baseUrl: 'https://api.anthropic.com',
    model: 'claude-sonnet-5-5',
    supportsVision: true,
    supportsTools: true,
  ),
  AiProviderConfig(
    id: 'gemini',
    name: 'Google Gemini（兼容模式）',
    kind: 'openai',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    model: 'gemini-2.0-flash',
    supportsVision: true,
  ),
];

class AiConfigStore {
  AiConfigStore._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _providersKey(String userId) =>
      'mypet_ai_providers_$userId';
  static String _keyName(String userId, String providerId) =>
      'mypet_ai_key_${userId}_$providerId';

  /// Stored configs merged with presets, so new presets appear automatically.
  static Future<List<AiProviderConfig>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_providersKey(userId));
    final stored = <String, AiProviderConfig>{};
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final config =
              AiProviderConfig.fromJson(item as Map<String, dynamic>);
          if (config.id.isNotEmpty) stored[config.id] = config;
        }
      } catch (_) {
        // Corrupted local settings should not block the AI page.
      }
    }
    final merged = <AiProviderConfig>[
      for (final preset in aiProviderPresets)
        stored[preset.id] ?? preset,
      for (final entry in stored.entries)
        if (!aiProviderPresets.any((p) => p.id == entry.key)) entry.value,
    ];
    if (merged.isNotEmpty && !merged.any((c) => c.isDefault)) {
      merged[0] = merged[0].copyWith(isDefault: true);
    }
    return merged;
  }

  static Future<void> save(
    String userId,
    List<AiProviderConfig> configs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _providersKey(userId),
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  static Future<String?> apiKey(String userId, String providerId) async {
    return _secure.read(key: _keyName(userId, providerId));
  }

  static Future<void> setApiKey(
    String userId,
    String providerId,
    String key,
  ) async {
    await _secure.write(key: _keyName(userId, providerId), value: key);
  }

  static Future<void> deleteApiKey(String userId, String providerId) async {
    await _secure.delete(key: _keyName(userId, providerId));
  }

  static Future<AiProviderConfig?> defaultConfig(String userId) async {
    final configs = await load(userId);
    for (final config in configs) {
      if (!config.isDefault) continue;
      final key = await apiKey(userId, config.id);
      if (key != null && key.isNotEmpty) return config;
    }
    for (final config in configs) {
      final key = await apiKey(userId, config.id);
      if (key != null && key.isNotEmpty) return config;
    }
    return null;
  }
}
