import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'ai_config.dart';

class AiConfigImport {
  const AiConfigImport({
    required this.configs,
    required this.keys,
    this.serverUrl,
    this.exportedAt,
  });

  final List<AiProviderConfig> configs;

  /// Provider id → API key.
  final Map<String, String> keys;
  final String? serverUrl;
  final DateTime? exportedAt;
}

/// Encrypted, password-protected transfer of AI provider settings and keys.
///
/// The envelope contains no provider names, URLs, models or keys in clear
/// text. The payload is encrypted with AES-256-GCM, using a PBKDF2-HMAC-SHA256
/// key derived from the user's password and a random salt.
class AiConfigTransfer {
  AiConfigTransfer._();

  static const format = 'mypet-ai-config';
  static const version = 1;
  static const _iterations = 210000;
  static const _minIterations = 10000;
  static const _maxIterations = 1000000;

  static Future<Uint8List> export({
    required List<AiProviderConfig> configs,
    required Map<String, String> keys,
    required String password,
    String? serverUrl,
    int iterations = _iterations,
  }) async {
    final safeIterations =
        iterations.clamp(_minIterations, _maxIterations).toInt();
    final payload = <String, dynamic>{
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
      'providers': [
        for (final config in configs)
          if ((keys[config.id] ?? '').isNotEmpty)
            {
              ...config.toJson(),
              'apiKey': keys[config.id],
            },
      ],
    };
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt, safeIterations);
    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
    );
    final envelope = <String, dynamic>{
      'format': format,
      'version': version,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': safeIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Returns a single copy-pasteable encrypted string.
  static Future<String> exportString({
    required List<AiProviderConfig> configs,
    required Map<String, String> keys,
    required String password,
    String? serverUrl,
    int iterations = _iterations,
  }) async {
    final bytes = await export(
      configs: configs,
      keys: keys,
      password: password,
      serverUrl: serverUrl,
      iterations: iterations,
    );
    return 'MYPETAI:${base64UrlEncode(bytes)}';
  }

  static Future<AiConfigImport> importString({
    required String value,
    required String password,
  }) {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw const FormatException('请粘贴加密配置');
    }
    var payload = raw;
    if (payload.startsWith('MYPETAI:')) {
      payload = payload.substring('MYPETAI:'.length).trim();
    }
    Uint8List bytes;
    if (payload.startsWith('{')) {
      bytes = Uint8List.fromList(utf8.encode(payload));
    } else {
      final compact = payload.replaceAll(RegExp(r'\s'), '');
      try {
        bytes = base64Url.decode(compact);
      } catch (_) {
        throw const FormatException('加密配置格式不正确');
      }
    }
    return import(bytes: bytes, password: password);
  }

  static Future<AiConfigImport> import({
    required Uint8List bytes,
    required String password,
  }) async {
    Map<String, dynamic> envelope;
    try {
      envelope =
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('文件格式不正确');
    }
    if (envelope['format'] != format) {
      throw const FormatException('不是喵了个咪的 AI 配置文件');
    }
    final fileVersion = (envelope['version'] as num?)?.toInt() ?? 0;
    if (fileVersion > version) {
      throw const FormatException('文件版本过新，请升级 App');
    }
    final iterations =
        (envelope['iterations'] as num?)?.toInt() ?? _iterations;
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const FormatException('文件参数异常');
    }
    Uint8List salt;
    Uint8List nonce;
    Uint8List mac;
    Uint8List cipherText;
    try {
      salt = base64Decode(envelope['salt'] as String);
      nonce = base64Decode(envelope['nonce'] as String);
      mac = base64Decode(envelope['mac'] as String);
      cipherText = base64Decode(envelope['ciphertext'] as String);
    } catch (_) {
      throw const FormatException('文件内容损坏');
    }
    final key = await _deriveKey(password, salt, iterations);
    final algorithm = AesGcm.with256bits();
    List<int> clear;
    try {
      clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('密码错误或文件已损坏');
    }
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('文件内容损坏');
    }
    final providers = payload['providers'];
    if (providers is! List) {
      throw const FormatException('文件缺少服务商配置');
    }
    final configs = <AiProviderConfig>[];
    final keys = <String, String>{};
    for (final item in providers) {
      if (item is! Map) continue;
      final config = AiProviderConfig.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (config.id.isEmpty || config.name.isEmpty) continue;
      if (config.kind != 'openai' && config.kind != 'anthropic') continue;
      if (config.baseUrl.isEmpty || config.model.isEmpty) continue;
      final apiKey = (item['apiKey'] as String?)?.trim() ?? '';
      if (apiKey.isEmpty) continue;
      configs.removeWhere((existing) => existing.id == config.id);
      configs.add(config);
      keys[config.id] = apiKey;
    }
    if (configs.isEmpty) {
      throw const FormatException('文件中没有可导入的 API Key 配置');
    }
    final serverUrl = (payload['serverUrl'] as String?)?.trim();
    return AiConfigImport(
      configs: configs,
      keys: keys,
      serverUrl: serverUrl == null || serverUrl.isEmpty ? null : serverUrl,
      exportedAt: DateTime.tryParse(payload['exportedAt'] as String? ?? ''),
    );
  }

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
