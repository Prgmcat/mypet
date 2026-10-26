import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miaolegemi/core/ai/ai_config.dart';
import 'package:miaolegemi/core/ai/ai_sessions.dart';
import 'package:miaolegemi/core/cache.dart';
import 'package:miaolegemi/core/models.dart';
import 'package:miaolegemi/core/server_scope.dart';

Pet buildPet() => Pet(
      id: 'p1',
      ownerUserId: 'u1',
      name: '咪咪',
      species: 'cat',
      breed: '',
      sex: 'unknown',
      birthday: '',
      birthdayEstimated: false,
      neutered: 'unknown',
      currentWeightKg: 0,
      allergies: '',
      chronicConditions: '',
      medications: '',
      identityNo: 'PET-1',
      status: 'active',
      version: 1,
      role: 'owner',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerScope.setFor('http://default.test', isCustom: false);
  });

  test('normalizes server URLs for stable identity', () {
    expect(ServerScope.normalize('HTTP://Example.COM:80/'), 'http://example.com');
    expect(ServerScope.normalize('https://example.com:443/app/'),
        'https://example.com/app');
    expect(ServerScope.normalize('http://example.com:8080/'),
        'http://example.com:8080');
  });

  test('default server keeps legacy keys; custom servers get distinct scopes', () {
    ServerScope.setFor('http://default.test', isCustom: false);
    expect(ServerScope.prefix, '');
    ServerScope.setFor('http://a.test', isCustom: true);
    final a = ServerScope.prefix;
    ServerScope.setFor('http://b.test', isCustom: true);
    final b = ServerScope.prefix;
    expect(a, matches(RegExp(r'^[0-9a-f]{8}_$')));
    expect(b, matches(RegExp(r'^[0-9a-f]{8}_$')));
    expect(a, isNot(b));
  });

  test('cached pets are isolated per custom server', () async {
    const user = 'u1';
    ServerScope.setFor('http://a.test', isCustom: true);
    await LocalCache.savePets(user, [buildPet()]);
    expect(await LocalCache.loadPets(user), hasLength(1));

    ServerScope.setFor('http://b.test', isCustom: true);
    expect(await LocalCache.loadPets(user), isEmpty);

    ServerScope.setFor('http://a.test', isCustom: true);
    expect(await LocalCache.loadPets(user), hasLength(1));
  });

  test('AI provider configs are isolated per custom server', () async {
    const user = 'u1';
    const config = AiProviderConfig(
      id: 'custom1',
      name: 'Mock',
      kind: 'openai',
      baseUrl: 'http://ai.test/v1',
      model: 'mock',
    );

    ServerScope.setFor('http://a.test', isCustom: true);
    await AiConfigStore.save(user, [config]);
    expect(
      (await AiConfigStore.load(user)).any((c) => c.id == 'custom1'),
      isTrue,
    );

    ServerScope.setFor('http://b.test', isCustom: true);
    expect(
      (await AiConfigStore.load(user)).any((c) => c.id == 'custom1'),
      isFalse,
    );

    ServerScope.setFor('http://a.test', isCustom: true);
    expect(
      (await AiConfigStore.load(user)).any((c) => c.id == 'custom1'),
      isTrue,
    );
  });

  test('AI chat sessions are isolated per custom server', () async {
    const user = 'u1';
    final session = AiSession(
      id: 's1',
      petId: 'p1',
      petName: '咪咪',
      title: '测试对话',
      updatedAt: '',
      messages: [],
    );

    ServerScope.setFor('http://a.test', isCustom: true);
    await AiSessionStore.upsert(user, session);
    expect(await AiSessionStore.load(user), hasLength(1));

    ServerScope.setFor('http://b.test', isCustom: true);
    expect(await AiSessionStore.load(user), isEmpty);

    ServerScope.setFor('http://a.test', isCustom: true);
    expect(await AiSessionStore.load(user), hasLength(1));
  });
}
