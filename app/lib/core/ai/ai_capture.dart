import 'dart:convert';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../models.dart';
import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_sessions.dart';

/// A structured fact detected in a chat message that should be written to the
/// pet's health profile.
class CaptureEvent {
  CaptureEvent({
    required this.kind,
    required this.petId,
    required this.petName,
    required this.label,
    this.weightKg,
    this.title = '',
    this.payload = const {},
    this.note = '',
  });

  /// weight | medical | diet
  final String kind;
  String petId;
  String petName;
  final String label;
  final double? weightKg;
  final String title;
  final Map<String, dynamic> payload;
  final String note;
}

const _symptomWords = [
  '拉稀',
  '腹泻',
  '软便',
  '便秘',
  '呕吐',
  '吐血',
  '便血',
  '咳嗽',
  '打喷嚏',
  '发烧',
  '发热',
  '精神差',
  '精神萎靡',
  '不吃',
  '不喝',
  '食欲下降',
  '瘙痒',
  '掉毛',
  '眼屎',
  '耳螨',
  '皮肤',
  '走路不稳',
  '抽搐',
  '呼吸困难',
];

const _dietWords = [
  '换粮',
  '换了一代',
  '换了一款',
  '新粮',
  '猫粮',
  '狗粮',
  '罐头',
  '冻干',
  '配方',
  '零食',
  '生骨肉',
];

const _recordWorthyWords = [
  ..._symptomWords,
  ..._dietWords,
  '体重',
  '公斤',
  '千克',
  '斤',
  'kg',
  '疫苗',
  '驱虫',
  '体检',
  '洗澡',
  '剪指甲',
];

bool looksRecordWorthy(String text) {
  return _recordWorthyWords.any(text.contains);
}

/// Matches exactly one pet name in the text, or the only pet when unambiguous.
Pet? matchPet(String text, List<Pet> pets) {
  final matches = pets.where((p) => text.contains(p.name)).toList();
  if (matches.length == 1) return matches.first;
  if (matches.isEmpty && pets.length == 1) return pets.first;
  return null;
}

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _formatKg(double kg) {
  final text = kg.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Deterministic, offline extraction for the common phrasings.
List<CaptureEvent> parseLocalCaptures(String text, List<Pet> pets) {
  final newPet = _parseNewPet(text);
  if (newPet != null) return [newPet];

  final events = <CaptureEvent>[];
  final pet = matchPet(text, pets);

  final weightMatch =
      RegExp(r'(\d+(?:\.\d+)?)\s*(公斤|千克|kg|KG|Kg|斤)').firstMatch(text);
  if (weightMatch != null) {
    final raw = double.tryParse(weightMatch.group(1)!) ?? 0;
    final unit = weightMatch.group(2)!;
    final kg = unit == '斤' ? raw / 2 : raw;
    if (kg > 0 && kg <= 120) {
      events.add(CaptureEvent(
        kind: 'weight',
        petId: pet?.id ?? '',
        petName: pet?.name ?? '',
        label: '体重 ${_formatKg(kg)} kg',
        weightKg: kg,
        note: '来自 AI 对话',
      ));
    }
  }

  final symptom = _symptomWords.firstWhere(text.contains, orElse: () => '');
  if (symptom.isNotEmpty) {
    events.add(CaptureEvent(
      kind: 'medical',
      petId: pet?.id ?? '',
      petName: pet?.name ?? '',
      label: '病历：$symptom',
      title: symptom,
      payload: {'symptoms': symptom, 'note': text},
      note: text,
    ));
  }

  final diet = _dietWords.firstWhere(text.contains, orElse: () => '');
  // Only record food when the user describes an action (changed/ate/tried),
  // not when they merely ask for a recommendation.
  final dietAction =
      RegExp(r'(换|吃|喂|买|试|用)(了|过|上|成|着)').hasMatch(text) ||
          text.contains('换粮') ||
          text.contains('新粮') ||
          text.contains('一直吃') ||
          text.contains('在吃');
  if (diet.isNotEmpty && dietAction) {
    final product = _extractProduct(text);
    final title = product.isEmpty ? '饮食记录' : '换粮：$product';
    events.add(CaptureEvent(
      kind: 'diet',
      petId: pet?.id ?? '',
      petName: pet?.name ?? '',
      label: '饮食：${product.isEmpty ? diet : product}',
      title: title.length > 30 ? title.substring(0, 30) : title,
      payload: {'product': product, 'note': text},
      note: text,
    ));
  }

  return events;
}

const _newPetCues = [
  '新养',
  '领养',
  '接回来',
  '接回家',
  '家里来',
  '捡到',
  '又多',
  '又养',
  '再养',
  '刚养',
  '新成员',
];

const _breedWords = [
  '美短',
  '英短',
  '布偶',
  '暹罗',
  '狸花',
  '橘猫',
  '金毛',
  '柯基',
  '泰迪',
  '贵宾',
  '柴犬',
  '边牧',
  '拉布拉多',
  '哈士奇',
  '萨摩耶',
  '比熊',
  '博美',
  '田园犬',
  '混血',
];

String _dateOnly(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

CaptureEvent? _parseNewPet(String text) {
  final hasCue = _newPetCues.any(text.contains) ||
      RegExp(r'养了(一)?[只条]').hasMatch(text);
  if (!hasCue) return null;
  final nameMatch = RegExp(
    r'(?:名字)?叫\s*(?:它|做|为)?\s*([一-龥A-Za-z0-9]{1,10})',
  ).firstMatch(text);
  if (nameMatch == null) return null;
  final name = nameMatch.group(1)!;

  var species = 'other';
  if (text.contains('猫')) {
    species = 'cat';
  } else if (text.contains('狗') || text.contains('犬')) {
    species = 'dog';
  }
  var breed = '';
  for (final word in _breedWords) {
    if (text.contains(word)) {
      breed = word;
      break;
    }
  }
  var sex = 'unknown';
  if (RegExp(r'(母|妹妹|女孩)').hasMatch(text)) {
    sex = 'female';
  } else if (RegExp(r'(公|弟弟|男孩)').hasMatch(text)) {
    sex = 'male';
  }
  var neutered = 'unknown';
  if (text.contains('绝育')) {
    neutered = (text.contains('未绝育') ||
            text.contains('没绝育') ||
            text.contains('未做') ||
            text.contains('没做'))
        ? 'no'
        : 'yes';
  }

  String birthday = '';
  final ageMatch =
      RegExp(r'(\d+(?:\.\d+)?)\s*(岁|个月|月)').firstMatch(text);
  if (ageMatch != null) {
    final value = double.tryParse(ageMatch.group(1)!) ?? 0;
    final months =
        ageMatch.group(2) == '岁' ? (value * 12).round() : value.round();
    if (months > 0 && months < 360) {
      final now = DateTime.now();
      birthday = _dateOnly(DateTime(now.year, now.month - months, now.day));
    }
  }

  double weightKg = 0;
  final weightMatch =
      RegExp(r'(\d+(?:\.\d+)?)\s*(公斤|千克|kg|KG|Kg|斤)').firstMatch(text);
  if (weightMatch != null) {
    final raw = double.tryParse(weightMatch.group(1)!) ?? 0;
    weightKg = weightMatch.group(2) == '斤' ? raw / 2 : raw;
    if (weightKg <= 0 || weightKg > 120) weightKg = 0;
  }

  final speciesLabel =
      species == 'cat' ? '猫' : species == 'dog' ? '狗' : '其他';
  return CaptureEvent(
    kind: 'pet',
    petId: '',
    petName: name,
    label: '新宠物：$name（$speciesLabel${breed.isEmpty ? '' : ' · $breed'}）',
    payload: {
      'name': name,
      'species': species,
      'breed': breed,
      'sex': sex,
      'birthday': birthday,
      'birthdayEstimated': birthday.isNotEmpty,
      'neutered': neutered,
      'currentWeightKg': weightKg,
      'allergies': '',
      'chronicConditions': '',
      'medications': '',
    },
    note: text,
  );
}

String _extractProduct(String text) {
  final match = RegExp(
    r'(?:换(?:了|成|上|一款|一代)?|吃(?:了)?|买了?|试了?)\s*([^，。,.!?；;\n]{1,18})',
  ).firstMatch(text);
  if (match == null) return '';
  var value = match.group(1)!.trim();
  value = value.replaceAll(RegExp(r'^(了|成|上|一款|一代|个)'), '').trim();
  value = value.split('看看').first.trim();
  value = value.split('的配方').first.trim();
  return value;
}

String buildCaptureExtractionPrompt(List<Pet> pets) {
  final list = pets.map((p) => '${p.name}（${p.speciesLabel}）').join('、');
  return '''
你是宠物档案信息抽取器。已知账号下的宠物：$list。
从用户这句话里提取需要写入档案的已发生事实，只输出一个 JSON 对象，不要 markdown 或解释。
格式：
{"events":[
 {"kind":"weight|medical|diet","pet":"宠物名字或空字符串","weightKg":2.5,
  "title":"不超过 20 字","note":"原始描述","product":"换粮/食品名称"},
 {"kind":"pet","name":"新宠物名字","species":"cat|dog|other","breed":"","sex":"male|female|unknown",
  "birthday":"YYYY-MM-DD 或空","ageMonths":24,"weightKg":2.5,"neutered":"yes|no|unknown","note":"原始描述"}
]}
规则：
1. 只提取用户明确陈述、已经发生的事实；提问、假设、计划不要记录。
2. weight 必须给出公斤数；用户用“斤”时要换算成公斤（1 斤 = 0.5 kg）。
3. medical 用于症状/就诊，title 用简短症状；diet 用于换粮、食品、配方。
4. pet 只用于用户明确说“新养/领养/家里来了/捡到”等新加入的宠物，且必须能确定名字；
   已经在列表里的宠物绝不能输出 pet 事件。
5. 无法确定是哪只宠物时 pet 留空，不要猜。
6. 没有可记录内容时输出 {"events":[]}；不要编造数值或名字。
''';
}

List<CaptureEvent> parseCaptureJson(String raw, List<Pet> pets) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return const [];
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) return const [];
    json = decoded;
  } catch (_) {
    return const [];
  }
  final list = json['events'];
  if (list is! List) return const [];
  final out = <CaptureEvent>[];
  for (final item in list) {
    if (item is! Map) continue;
    final kind = (item['kind'] as String?) ?? '';
    final petName = ((item['pet'] as String?) ?? '').trim();
    Pet? pet;
    for (final p in pets) {
      if (p.name == petName) pet = p;
    }
    if (pet == null && pets.length == 1 && petName.isEmpty) pet = pets.first;
    final note = ((item['note'] as String?) ?? '').trim();
    if (kind == 'pet') {
      final name = ((item['name'] as String?) ?? '').trim();
      if (name.isEmpty || name.length > 20) continue;
      var species = ((item['species'] as String?) ?? 'other').trim();
      if (species != 'cat' && species != 'dog') species = 'other';
      final breed = ((item['breed'] as String?) ?? '').trim();
      var sex = ((item['sex'] as String?) ?? 'unknown').trim();
      if (sex != 'male' && sex != 'female') sex = 'unknown';
      var neutered = ((item['neutered'] as String?) ?? 'unknown').trim();
      if (neutered != 'yes' && neutered != 'no') neutered = 'unknown';
      var birthday = ((item['birthday'] as String?) ?? '').trim();
      if (birthday.isNotEmpty && DateTime.tryParse(birthday) == null) {
        birthday = '';
      }
      if (birthday.isEmpty) {
        final months = (item['ageMonths'] as num?)?.toInt() ?? 0;
        if (months > 0 && months < 360) {
          final now = DateTime.now();
          birthday = _dateOnly(DateTime(now.year, now.month - months, now.day));
        }
      }
      final kg = (item['weightKg'] as num?)?.toDouble() ?? 0;
      final speciesLabel =
          species == 'cat' ? '猫' : species == 'dog' ? '狗' : '其他';
      out.add(CaptureEvent(
        kind: 'pet',
        petId: '',
        petName: name,
        label:
            '新宠物：$name（$speciesLabel${breed.isEmpty ? '' : ' · $breed'}）',
        payload: {
          'name': name,
          'species': species,
          'breed': breed,
          'sex': sex,
          'birthday': birthday,
          'birthdayEstimated': birthday.isNotEmpty,
          'neutered': neutered,
          'currentWeightKg': (kg > 0 && kg <= 120) ? kg : 0,
          'allergies': '',
          'chronicConditions': '',
          'medications': '',
        },
        note: note,
      ));
      continue;
    }
    if (kind == 'weight') {
      final kg = (item['weightKg'] as num?)?.toDouble() ?? 0;
      if (kg <= 0 || kg > 120) continue;
      out.add(CaptureEvent(
        kind: 'weight',
        petId: pet?.id ?? '',
        petName: pet?.name ?? petName,
        label: '体重 ${_formatKg(kg)} kg',
        weightKg: kg,
        note: note.isEmpty ? '来自 AI 对话' : note,
      ));
    } else if (kind == 'medical' || kind == 'diet') {
      final title = ((item['title'] as String?) ?? '').trim();
      final product = ((item['product'] as String?) ?? '').trim();
      final label = kind == 'medical'
          ? '病历：${title.isEmpty ? '症状' : title}'
          : '饮食：${product.isEmpty ? (title.isEmpty ? '饮食记录' : title) : product}';
      out.add(CaptureEvent(
        kind: kind,
        petId: pet?.id ?? '',
        petName: pet?.name ?? petName,
        label: label,
        title: kind == 'medical'
            ? (title.isEmpty ? '症状记录' : title)
            : (title.isEmpty ? '饮食记录' : title),
        payload: kind == 'medical'
            ? {'symptoms': title, 'note': note}
            : {'product': product, 'note': note},
        note: note,
      ));
    }
  }
  return out;
}

/// Uses the configured model as a fallback when local rules found nothing.
Future<List<CaptureEvent>> extractCapturesWithAi({
  required AiClient client,
  required AiProviderConfig config,
  required String apiKey,
  required List<Pet> pets,
  required String text,
  CancelToken? cancelToken,
}) async {
  final raw = await client.complete(
    config: config,
    apiKey: apiKey,
    systemPrompt: buildCaptureExtractionPrompt(pets),
    messages: [AiMessage(role: 'user', content: text)],
    cancelToken: cancelToken,
  );
  return parseCaptureJson(raw, pets);
}

/// Writes one event and returns the persisted capture descriptor.
Future<AiCapture> applyCapture(ApiClient api, CaptureEvent event) async {
  if (event.kind == 'pet') {
    final pet = await api.createPet(Map<String, dynamic>.from(event.payload));
    return AiCapture(
      kind: 'pet',
      id: pet.id,
      petId: pet.id,
      petName: pet.name,
      label: event.label,
    );
  }
  if (event.petId.isEmpty) {
    throw StateError('缺少宠物');
  }
  final today = _today();
  if (event.kind == 'weight') {
    final weight = await api.createWeight(event.petId, {
      'measuredAt': today,
      'weightKg': event.weightKg,
      'note': event.note,
    });
    return AiCapture(
      kind: 'weight',
      id: weight.id,
      petId: event.petId,
      petName: event.petName,
      label: '${event.petName} · ${event.label}',
    );
  }
  final record = await api.createRecord(event.petId, {
    'type': event.kind,
    'occurredAt': today,
    'title': event.title.isEmpty ? event.label : event.title,
    'payload': event.payload,
    'hospital': '',
    'doctor': '',
    'nextDueAt': '',
    'source': 'ai',
  });
  return AiCapture(
    kind: 'record',
    id: record.id,
    petId: event.petId,
    petName: event.petName,
    label: '${event.petName} · ${event.label}',
  );
}

Future<void> undoCapture(ApiClient api, AiCapture capture) async {
  if (capture.undone) return;
  if (capture.kind == 'pet') {
    await api.deletePet(capture.id);
  } else if (capture.kind == 'weight') {
    await api.deleteWeight(capture.id);
  } else {
    await api.deleteRecord(capture.id);
  }
}
