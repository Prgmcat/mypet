import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/ai/ai_client.dart';
import 'package:miaolegemi/core/ai/ai_config.dart';

Future<HttpServer> startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

void writeSse(HttpResponse response, List<String> frames) {
  response.statusCode = 200;
  response.headers.contentType =
      ContentType('text', 'event-stream', charset: 'utf-8');
  for (final frame in frames) {
    response.add(utf8.encode(frame));
  }
  response.close();
}

void main() {
  test('OpenAI-compatible stream yields deltas', () async {
    final server = await startServer((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value('authorization'), 'Bearer sk-test');
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['stream'], true);
      expect(body['messages'][0]['role'], 'system');
      expect(body['messages'][1]['content'], '你好');
      writeSse(request.response, [
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n',
        'data: [DONE]\n\n',
      ]);
    });
    try {
      final config = AiProviderConfig(
        id: 'test',
        name: 'test',
        kind: 'openai',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'test-model',
      );
      final buffer = StringBuffer();
      await for (final chunk in AiClient().stream(
        config: config,
        apiKey: 'sk-test',
        systemPrompt: 'system',
        messages: const [AiMessage(role: 'user', content: '你好')],
      )) {
        buffer.write(chunk);
      }
      expect(buffer.toString(), '你好');
    } finally {
      await server.close(force: true);
    }
  });

  test('Anthropic stream yields text deltas', () async {
    final server = await startServer((request) async {
      expect(request.uri.path, '/v1/messages');
      expect(request.headers.value('x-api-key'), 'sk-ant');
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['system'], 'system');
      expect(body['stream'], true);
      writeSse(request.response, [
        'event: content_block_delta\n',
        'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"喵"}}\n\n',
        'data: {"type":"message_stop"}\n\n',
      ]);
    });
    try {
      final config = AiProviderConfig(
        id: 'anthropic',
        name: 'anthropic',
        kind: 'anthropic',
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'claude-test',
      );
      final text = await AiClient().complete(
        config: config,
        apiKey: 'sk-ant',
        systemPrompt: 'system',
        messages: const [AiMessage(role: 'user', content: 'hi')],
      );
      expect(text, '喵');
    } finally {
      await server.close(force: true);
    }
  });

  test('HTTP errors surface provider message', () async {
    final server = await startServer((request) async {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"error":{"message":"invalid api key"}}',
      );
      await request.response.close();
    });
    try {
      final config = AiProviderConfig(
        id: 'test',
        name: 'test',
        kind: 'openai',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'm',
      );
      await expectLater(
        AiClient().complete(
          config: config,
          apiKey: 'bad',
          systemPrompt: 'system',
          messages: const [AiMessage(role: 'user', content: 'hi')],
        ),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('invalid api key'),
        )),
      );
    } finally {
      await server.close(force: true);
    }
  });
}
