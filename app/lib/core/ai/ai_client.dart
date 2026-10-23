import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'ai_config.dart';

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    this.imagePaths = const [],
  });

  final String role; // user | assistant
  final String content;

  /// Local files attached to this message (user messages only).
  final List<String> imagePaths;
}

class AiClient {
  AiClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 120),
        ));

  final Dio _dio;

  /// Streams assistant text deltas. The caller owns [cancelToken].
  Stream<String> stream({
    required AiProviderConfig config,
    required String apiKey,
    required String systemPrompt,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw AiException('尚未配置 API Key');
    }
    final base = _trimSlash(config.baseUrl);
    if (base.isEmpty) throw AiException('请先填写 Base URL');
    if (config.kind == 'anthropic') {
      yield* _streamAnthropic(
        base: base,
        config: config,
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        messages: messages,
        cancelToken: cancelToken,
      );
    } else {
      yield* _streamOpenAi(
        base: base,
        config: config,
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        messages: messages,
        cancelToken: cancelToken,
      );
    }
  }

  Future<String> complete({
    required AiProviderConfig config,
    required String apiKey,
    required String systemPrompt,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in stream(
      config: config,
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      messages: messages,
      cancelToken: cancelToken,
    )) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  Stream<String> _streamOpenAi({
    required String base,
    required AiProviderConfig config,
    required String apiKey,
    required String systemPrompt,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    final payloadMessages = <Map<String, dynamic>>[];
    for (final message in messages) {
      payloadMessages.add(await _openAiMessage(message));
    }
    final response = await _dio.post<ResponseBody>(
      '$base/chat/completions',
      data: jsonEncode({
        'model': config.model,
        'stream': true,
        'temperature': 0.4,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...payloadMessages,
        ],
      }),
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
      ),
      cancelToken: cancelToken,
    );
    final body = await _checkedBody(response);
    await for (final line in _sseLines(body)) {
      if (line.isEmpty) continue;
      if (line == '[DONE]') return;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices.first['delta'] as Map<String, dynamic>?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) yield content;
      } catch (_) {
        // Ignore keep-alives and malformed frames from compatible providers.
      }
    }
  }

  Stream<String> _streamAnthropic({
    required String base,
    required AiProviderConfig config,
    required String apiKey,
    required String systemPrompt,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    final payloadMessages = <Map<String, dynamic>>[];
    for (final message in messages) {
      payloadMessages.add(await _anthropicMessage(message));
    }
    final response = await _dio.post<ResponseBody>(
      '$base/v1/messages',
      data: jsonEncode({
        'model': config.model,
        'max_tokens': 1024,
        'system': systemPrompt,
        'stream': true,
        'messages': payloadMessages,
      }),
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
      ),
      cancelToken: cancelToken,
    );
    final body = await _checkedBody(response);
    await for (final line in _sseLines(body)) {
      if (line.isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        if (json['type'] == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          final text = delta?['text'];
          if (text is String && text.isNotEmpty) yield text;
        }
        if (json['type'] == 'message_stop') return;
      } catch (_) {
        // Ignore ping/comment frames.
      }
    }
  }

  /// Tests credentials without spending meaningful tokens.
  Future<String> testConnection({
    required AiProviderConfig config,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) throw AiException('请先填写 API Key');
    final base = _trimSlash(config.baseUrl);
    try {
      if (config.kind == 'anthropic') {
        final response = await _dio.post(
          '$base/v1/messages',
          data: jsonEncode({
            'model': config.model,
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'ping'}
            ],
          }),
          options: Options(headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          }),
        );
        if (response.statusCode == 200) return '连接成功';
        throw AiException(_errorText(response.data));
      }
      final response = await _dio.get(
        '$base/models',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      if (response.statusCode == 200) return '连接成功';
      throw AiException(_errorText(response.data));
    } on DioException catch (e) {
      if (e.response != null) {
        throw AiException(_errorText(e.response!.data,
            fallback: 'HTTP ${e.response!.statusCode}'));
      }
      throw AiException(_networkMessage(e));
    }
  }

  Future<Map<String, dynamic>> _openAiMessage(AiMessage message) async {
    if (message.imagePaths.isEmpty) {
      return {'role': message.role, 'content': message.content};
    }
    final parts = <Map<String, dynamic>>[];
    if (message.content.trim().isNotEmpty) {
      parts.add({'type': 'text', 'text': message.content});
    }
    for (final path in message.imagePaths) {
      final data = base64Encode(await _readImage(path));
      final mime = _mimeFor(path);
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,$data'},
      });
    }
    return {'role': message.role, 'content': parts};
  }

  Future<Map<String, dynamic>> _anthropicMessage(AiMessage message) async {
    if (message.imagePaths.isEmpty) {
      return {'role': message.role, 'content': message.content};
    }
    final parts = <Map<String, dynamic>>[];
    for (final path in message.imagePaths) {
      final data = base64Encode(await _readImage(path));
      parts.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': _mimeFor(path),
          'data': data,
        },
      });
    }
    if (message.content.trim().isNotEmpty) {
      parts.add({'type': 'text', 'text': message.content});
    }
    return {'role': message.role, 'content': parts};
  }

  Future<Uint8List> _readImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) throw const FormatException('empty');
      return bytes;
    } catch (_) {
      throw AiException('无法读取图片文件，请重新选择：$path');
    }
  }

  static String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<ResponseBody> _checkedBody(Response<ResponseBody> response) async {
    final body = response.data;
    if (body == null) throw AiException('模型服务返回为空');
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return body;
    final text = await _readAll(body.stream);
    throw AiException(_errorText(text, fallback: 'HTTP $status'));
  }

  Future<String> _readAll(Stream<Uint8List> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Stream<String> _sseLines(ResponseBody body) async* {
    final lines =
        utf8.decoder.bind(body.stream).transform(const LineSplitter());
    await for (final raw in lines) {
      final line = raw.trim();
      if (!line.startsWith('data:')) continue;
      yield line.substring(5).trim();
    }
  }

  String _errorText(dynamic data, {String fallback = '请求失败'}) {
    if (data is String && data.trim().isNotEmpty) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          return '模型服务错误：${error['message']}';
        }
        if (json['message'] is String) return '模型服务错误：${json['message']}';
      } catch (_) {
        return data.length > 200 ? '${data.substring(0, 200)}…' : data;
      }
    }
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return '模型服务错误：${error['message']}';
      }
    }
    return fallback;
  }

  String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '模型服务连接超时';
      case DioExceptionType.connectionError:
        return '无法连接模型服务，请检查 Base URL 和网络';
      default:
        return e.message ?? '模型服务请求失败';
    }
  }

  static String _trimSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
