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

  test('OpenAI-compatible image message uses data URLs', () async {
    final dir = await Directory.systemTemp.createTemp('mypet-ai-test');
    final image = File('${dir.path}/photo.png');
    await image.writeAsBytes([137, 80, 78, 71, 1, 2, 3]);
    HttpServer? server;
    try {
      server = await startServer((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        final content = body['messages'][1]['content'];
        expect(content, isA<List>());
        expect(content[0]['type'], 'text');
        expect(content[1]['type'], 'image_url');
        expect(content[1]['image_url']['url'],
            startsWith('data:image/png;base64,'));
        writeSse(request.response, [
          'data: {"choices":[{"delta":{"content":"看到了"}}]}\n\n',
          'data: [DONE]\n\n',
        ]);
      });
      final config = AiProviderConfig(
        id: 'test',
        name: 'test',
        kind: 'openai',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'm',
      );
      final text = await AiClient().complete(
        config: config,
        apiKey: 'sk-test',
        systemPrompt: 'system',
        messages: [
          AiMessage(
            role: 'user',
            content: '看看这张照片',
            imagePaths: [image.path],
          ),
        ],
      );
      expect(text, '看到了');
    } finally {
      await server?.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test('Anthropic image message uses base64 source blocks', () async {
    final dir = await Directory.systemTemp.createTemp('mypet-ai-test');
    final image = File('${dir.path}/photo.jpg');
    await image.writeAsBytes([255, 216, 255, 1]);
    HttpServer? server;
    try {
      server = await startServer((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        final content = body['messages'][0]['content'];
        expect(content, isA<List>());
        expect(content[0]['type'], 'image');
        expect(content[0]['source']['type'], 'base64');
        expect(content[0]['source']['media_type'], 'image/jpeg');
        expect(content[1]['type'], 'text');
        writeSse(request.response, [
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"收到"}}\n\n',
          'data: {"type":"message_stop"}\n\n',
        ]);
      });
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
        messages: [
          AiMessage(
            role: 'user',
            content: '看看这张照片',
            imagePaths: [image.path],
          ),
        ],
      );
      expect(text, '收到');
    } finally {
      await server?.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test('fetchModels returns the provider catalogue', () async {
    final server = await startServer((request) async {
      expect(request.uri.path, '/v1/models');
      expect(request.headers.value('authorization'), 'Bearer sk-test');
      final body = jsonEncode({
        'data': [
          {'id': 'deepseek-reasoner'},
          {'id': 'deepseek-chat'},
        ],
      });
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(body);
      await request.response.close();
    });
    try {
      final models = await AiClient().fetchModels(
        config: AiProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          kind: 'openai',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'deepseek-chat',
        ),
        apiKey: 'sk-test',
      );
      expect(models, ['deepseek-chat', 'deepseek-reasoner']);
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
