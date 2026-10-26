import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:miaolegemi/core/ai/ai_config.dart';
import 'package:miaolegemi/core/ai/ai_config_transfer.dart';

const _config = AiProviderConfig(
  id: 'custom1',
  name: 'Mock Provider',
  kind: 'openai',
  baseUrl: 'https://ai.example/v1',
  model: 'mock-model',
  isDefault: true,
  supportsVision: true,
);

const _secretKey = 'sk-super-secret-123456789';

void main() {
  test('encrypted export round-trips and hides plaintext', () async {
    final bytes = await AiConfigTransfer.export(
      configs: const [_config],
      keys: const {'custom1': _secretKey},
      password: 'Passw0rd!',
      serverUrl: 'http://server.test',
      iterations: 10000,
    );
    final text = utf8.decode(bytes);
    expect(text.contains(_secretKey), isFalse);
    expect(text.contains('Mock Provider'), isFalse);
    expect(text.contains('ai.example'), isFalse);
    expect(text.contains('mock-model'), isFalse);

    final imported = await AiConfigTransfer.import(
      bytes: bytes,
      password: 'Passw0rd!',
    );
    expect(imported.configs, hasLength(1));
    expect(imported.configs.single.id, 'custom1');
    expect(imported.configs.single.name, 'Mock Provider');
    expect(imported.configs.single.baseUrl, 'https://ai.example/v1');
    expect(imported.configs.single.supportsVision, isTrue);
    expect(imported.keys['custom1'], _secretKey);
    expect(imported.serverUrl, 'http://server.test');
    expect(imported.exportedAt, isNotNull);
  });

  test('only providers with keys are exported', () async {
    const withoutKey = AiProviderConfig(
      id: 'no-key',
      name: 'No Key',
      kind: 'openai',
      baseUrl: 'https://ai.example/v1',
      model: 'm',
    );
    final bytes = await AiConfigTransfer.export(
      configs: const [_config, withoutKey],
      keys: const {'custom1': _secretKey},
      password: 'Passw0rd!',
      iterations: 10000,
    );
    final imported = await AiConfigTransfer.import(
      bytes: bytes,
      password: 'Passw0rd!',
    );
    expect(imported.configs.map((c) => c.id), ['custom1']);
  });

  test('encrypted string round-trips and tolerates line breaks', () async {
    final text = await AiConfigTransfer.exportString(
      configs: const [_config],
      keys: const {'custom1': _secretKey},
      password: 'Passw0rd!',
      iterations: 10000,
    );
    expect(text.startsWith('MYPETAI:'), isTrue);
    expect(text.contains(_secretKey), isFalse);
    final wrapped = text.replaceRange(60, 60, '\n');
    final imported = await AiConfigTransfer.importString(
      value: wrapped,
      password: 'Passw0rd!',
    );
    expect(imported.keys['custom1'], _secretKey);
  });

  test('wrong password is rejected', () async {
    final bytes = await AiConfigTransfer.export(
      configs: const [_config],
      keys: const {'custom1': _secretKey},
      password: 'Passw0rd!',
      iterations: 10000,
    );
    await expectLater(
      AiConfigTransfer.import(bytes: bytes, password: 'wrong-password'),
      throwsA(isA<FormatException>()),
    );
  });

  test('tampered ciphertext is rejected', () async {
    final bytes = await AiConfigTransfer.export(
      configs: const [_config],
      keys: const {'custom1': _secretKey},
      password: 'Passw0rd!',
      iterations: 10000,
    );
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final cipher = base64Decode(envelope['ciphertext'] as String);
    cipher[0] ^= 0xff;
    envelope['ciphertext'] = base64Encode(cipher);
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    await expectLater(
      AiConfigTransfer.import(bytes: tampered, password: 'Passw0rd!'),
      throwsA(isA<FormatException>()),
    );
  });

  test('invalid or foreign files are rejected', () async {
    await expectLater(
      AiConfigTransfer.import(
        bytes: Uint8List.fromList(utf8.encode('{"format":"other"}')),
        password: 'Passw0rd!',
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      AiConfigTransfer.import(
        bytes: Uint8List.fromList(utf8.encode('not-json')),
        password: 'Passw0rd!',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
