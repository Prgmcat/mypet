import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/ai/ai_capture.dart';
import 'package:miaolegemi/core/api_client.dart';
import 'package:miaolegemi/core/models.dart';

Pet buildPet(String id, String name, String species) => Pet(
      id: id,
      ownerUserId: 'u1',
      name: name,
      species: species,
      breed: '',
      sex: 'unknown',
      birthday: '',
      birthdayEstimated: false,
      neutered: 'unknown',
      currentWeightKg: 0,
      allergies: '',
      chronicConditions: '',
      medications: '',
      identityNo: 'PET-$id',
      status: 'active',
      version: 1,
      role: 'owner',
    );

void main() {
  final mimi = buildPet('p1', '咪咪', 'cat');
  final doudou = buildPet('p2', '豆豆', 'dog');
  final pets = [mimi, doudou];

  test('weight sentence converts 斤 to kg and resolves the pet', () {
    final events = parseLocalCaptures('啊，咪咪又胖了，都5斤了', pets);
    expect(events.length, 1);
    expect(events.first.kind, 'weight');
    expect(events.first.petId, mimi.id);
    expect(events.first.weightKg, 2.5);
  });

  test('symptom sentence creates a medical event', () {
    final events = parseLocalCaptures('今天咪咪拉稀了', pets);
    expect(events.any((e) => e.kind == 'medical' && e.title == '拉稀'), true);
    expect(events.first.petId, mimi.id);
  });

  test('food change creates a diet event with product', () {
    final events = parseLocalCaptures('今天给咪咪换了新猫粮，看看这个配方', pets);
    final diet = events.where((e) => e.kind == 'diet').toList();
    expect(diet.length, 1);
    expect(diet.first.petId, mimi.id);
    expect(diet.first.label, contains('新猫粮'));
  });

  test('unresolved pet stays empty when multiple pets and no name', () {
    final events = parseLocalCaptures('今天拉稀了', pets);
    expect(events, isNotEmpty);
    expect(events.first.petId, '');
  });

  test('single pet resolves without a name', () {
    final events = parseLocalCaptures('今天 5.2 公斤了', [mimi]);
    expect(events.first.petId, mimi.id);
    expect(events.first.weightKg, 5.2);
  });

  test('questions without facts do not create captures', () {
    expect(parseLocalCaptures('咪咪下次驱虫是什么时候', pets), isEmpty);
    expect(looksRecordWorthy('咪咪下次驱虫是什么时候'), true);
    expect(parseLocalCaptures('咪咪吃什么猫粮好', pets), isEmpty);
  });

  test('new pet sentence creates a pet event', () {
    final events = parseLocalCaptures(
      '我新养了一只猫叫豆豆，2岁，美短，公的，5斤',
      pets,
    );
    expect(events.length, 1);
    final event = events.single;
    expect(event.kind, 'pet');
    expect(event.payload['name'], '豆豆');
    expect(event.payload['species'], 'cat');
    expect(event.payload['breed'], '美短');
    expect(event.payload['sex'], 'male');
    expect(event.payload['currentWeightKg'], 2.5);
    expect(event.payload['birthday'], isNotEmpty);
    expect(event.label, contains('豆豆'));
  });

  test('talking about an existing pet is not a new pet', () {
    expect(parseLocalCaptures('咪咪养了三年了', pets), isEmpty);
  });

  test('AI pet JSON is mapped to a new pet capture', () {
    final events = parseCaptureJson('''
{"events":[{"kind":"pet","name":"旺财","species":"dog","breed":"柯基",
"sex":"male","ageMonths":3,"weightKg":4.2,"neutered":"no"}]}
''', pets);
    expect(events.length, 1);
    final event = events.single;
    expect(event.kind, 'pet');
    expect(event.payload['name'], '旺财');
    expect(event.payload['species'], 'dog');
    expect(event.payload['breed'], '柯基');
    expect(event.payload['neutered'], 'no');
    expect(event.payload['birthday'], isNotEmpty);
  });

  test('applyCapture creates the new pet and undo deletes it', () async {
    var deleted = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/api/pets') {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body['name'], '豆豆');
        expect(body['species'], 'cat');
        expect(body['breed'], '美短');
        expect(body['currentWeightKg'], 2.5);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {
            'id': 'p-new',
            'ownerUserId': 'u1',
            'name': body['name'],
            'species': body['species'],
            'breed': body['breed'],
            'sex': body['sex'],
            'birthday': body['birthday'],
            'birthdayEstimated': body['birthdayEstimated'],
            'neutered': body['neutered'],
            'currentWeightKg': body['currentWeightKg'],
            'allergies': '',
            'chronicConditions': '',
            'medications': '',
            'identityNo': 'PET2026123456',
            'status': 'active',
            'version': 1,
            'role': 'owner',
          },
        }));
        await request.response.close();
        return;
      }
      if (request.method == 'DELETE' &&
          request.uri.path == '/api/pets/p-new') {
        deleted = true;
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
      final events = parseLocalCaptures(
        '我新养了一只猫叫豆豆，2岁，美短，公的，5斤',
        pets,
      );
      final capture = await applyCapture(api, events.single);
      expect(capture.kind, 'pet');
      expect(capture.id, 'p-new');
      expect(capture.petName, '豆豆');
      await undoCapture(api, capture);
      expect(deleted, true);
    } finally {
      await server.close(force: true);
    }
  });

  test('AI JSON extraction is validated and mapped', () {
    final events = parseCaptureJson('''
```json
{"events":[
 {"kind":"weight","pet":"咪咪","weightKg":2.6,"note":"称重"},
 {"kind":"medical","pet":"豆豆","title":"呕吐","note":"吐了一次"},
 {"kind":"diet","pet":"咪咪","title":"换粮","product":"新猫粮"},
 {"kind":"unknown","pet":"咪咪"}
]}
```
''', pets);
    expect(events.length, 3);
    expect(events[0].petId, mimi.id);
    expect(events[1].petId, doudou.id);
    expect(events[2].kind, 'diet');
    expect(events[2].label, contains('新猫粮'));
  });
}
