import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/api_client.dart';

void main() {
  test('blocked DELETE falls back to POST with method override', () async {
    var overrideSeen = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'DELETE') {
        // Simulate an HTTP tunnel that closes the connection for unsupported
        // methods before sending any response.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      if (request.method == 'POST' &&
          request.uri.path == '/api/weights/w1') {
        overrideSeen =
            request.headers.value('x-http-method-override') == 'DELETE';
        request.response.headers.contentType = ContentType.json;
        request.response.write(
            jsonEncode({'code': 0, 'message': 'ok', 'data': {'ok': true}}));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
    try {
      final api = ApiClient()
        ..configure(baseUrl: 'http://127.0.0.1:${server.port}');
      await api.deleteWeight('w1');
      expect(overrideSeen, true);
    } finally {
      await server.close(force: true);
    }
  });
}
