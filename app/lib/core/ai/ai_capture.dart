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
    this.occurredAt = '',
    this.scheduledAt = '',
    this.appointmentType = '',
    this.payload = const {},
    this.note = '',
  });

  /// weight | medical | diet | growth | pet | appointment
  final String kind;
  String petId;
  String petName;
  final String label;
  final double? weightKg;
  final String title;

  /// Record date in YYYY-MM-DD. Empty means today.
  String occurredAt;

  /// Appointment date in YYYY-MM-DD. Only used when kind is appointment.
  final String scheduledAt;

  /// vaccine | deworming | checkup | medical | medication | grooming | other
  final String appointmentType;
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

const _growthWords = [
  '第一次',
  '学会',
  '会自己',
  '玩耍',
  '玩球',
  '逗猫棒',
  '抓蝴蝶',
  '抓虫',
  '扑',
  '追',
  '晒太阳',
  '散步',
  '遛',
  '打滚',
  '撒娇',
  '粘人',
  '开心',
  '高兴',
  '睡姿',
  '打呼',
  '生日',
  '游泳',
  '爬山',
  '出门',
  '可爱',
];

/// A question or plan is not a completed moment, so it must not become a
/// growth entry.
bool _looksLikeQuestion(String text) {
  if (text.contains('?') || text.contains('？')) return true;
  return RegExp(r'(吗|呢|怎么|为什么|是不是|要不要|需不需要|能不能|可不可以|如何|什么|哪|多久|多少|什么时候)')
      .hasMatch(text);
}

const _recordWorthyWords = [
  ..._symptomWords,
  ..._dietWords,
  ..._growthWords,
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

/// Whether a message is worth the model-based capture fallback. Growth stories
/// often contain no health keyword, so a mentioned pet name is enough.
bool shouldTryAiCapture(String text, List<Pet> pets) {
  final value = text.trim();
  if (value.length < 4 || _looksLikeQuestion(value)) return false;
  if (_looksLikeAppointment(value)) return true;
  if (looksRecordWorthy(value)) return true;
  return pets.any((pet) => value.contains(pet.name));
}

/// Matches exactly one pet name in the text, or the only pet when unambiguous.
Pet? matchPet(String text, List<Pet> pets) {
  final matches = pets.where((p) => text.contains(p.name)).toList();
  if (matches.length == 1) return matches.first;
  if (matches.isEmpty && pets.length == 1) return pets.first;
  return null;
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _today() => _formatDate(DateTime.now());

/// Normalizes an already formatted YYYY-MM-DD date; returns empty if invalid.
String _normalizeDate(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw.trim());
  if (match == null) return '';
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return '';
  return _formatDate(date);
}

/// Extracts a record date from Chinese text. Falls back to today.
String parseRecordDate(String text, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);

  var match = RegExp(r'(\d{4})\s*[-/年]\s*(\d{1,2})\s*[-/月]\s*(\d{1,2})\s*[日号]?')
      .firstMatch(text);
  if (match != null) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year == year && date.month == month && date.day == day) {
      return _formatDate(date);
    }
  }

  match = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]').firstMatch(text);
  if (match != null) {
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    var date = DateTime(today.year, month, day);
    if (date.month == month && date.day == day) {
      // A date later than today most likely refers to last year.
      if (date.isAfter(today)) date = DateTime(today.year - 1, month, day);
      return _formatDate(date);
    }
  }

  if (text.contains('大前天')) {
    return _formatDate(today.subtract(const Duration(days: 3)));
  }
  if (text.contains('前天')) {
    return _formatDate(today.subtract(const Duration(days: 2)));
  }
  if (text.contains('昨天')) {
    return _formatDate(today.subtract(const Duration(days: 1)));
  }
  if (text.contains('今天') || text.contains('今日')) {
    return _formatDate(today);
  }
  match = RegExp(r'(\d{1,2})\s*天前').firstMatch(text);
  if (match != null) {
    final days = int.parse(match.group(1)!);
    if (days >= 0 && days <= 3650) {
      return _formatDate(today.subtract(Duration(days: days)));
    }
  }
  return _formatDate(today);
}

const appointmentTypeLabels = <String, String>{
  'vaccine': '疫苗',
  'deworming': '驱虫',
  'checkup': '体检',
  'medical': '就诊',
  'medication': '用药',
  'grooming': '洗护',
  'other': '预约',
};

String appointmentTypeLabel(String type) =>
    appointmentTypeLabels[type] ?? appointmentTypeLabels['other']!;

const _appointmentTypeCues = <(String, String)>[
  ('驱虫', 'deworming'),
  ('疫苗', 'vaccine'),
  ('接种', 'vaccine'),
  ('打针', 'vaccine'),
  ('猫三联', 'vaccine'),
  ('狂犬', 'vaccine'),
  ('体检', 'checkup'),
  ('复查', 'checkup'),
  ('绝育', 'medical'),
  ('手术', 'medical'),
  ('看病', 'medical'),
  ('就诊', 'medical'),
  ('复诊', 'medical'),
  ('喂药', 'medication'),
  ('用药', 'medication'),
  ('吃药', 'medication'),
  ('洗澡', 'grooming'),
  ('洗护', 'grooming'),
  ('美容', 'grooming'),
  ('剪指甲', 'grooming'),
];

String? appointmentTypeForText(String text) {
  for (final (cue, type) in _appointmentTypeCues) {
    if (text.contains(cue)) return type;
  }
  return null;
}

/// True when the message describes a future care plan rather than something
/// that already happened.
bool hasFutureAppointmentCue(String text) {
  // Strong past markers always win, even if the sentence also mentions a
  // weekday.
  if (RegExp(r'(已经|昨天|前天|昨儿|上周|上个月|去年|刚刚|刚才)').hasMatch(text)) {
    return false;
  }
  // An explicit future date is enough on its own.
  if (RegExp(
    r'(明天|明日|后天|大后天|下周|下个?星期|下个?月|下个月|\d{1,2}\s*月\s*\d{1,2}\s*[日号]|\d{1,2}\s*[天周]\s*后)',
  ).hasMatch(text)) {
    return true;
  }
  // Without an explicit future date, completed-action wording means the care
  // already happened; "明天去洗澡了" was caught above as a plan.
  if (RegExp(
    r'(洗了|洗过|洗澡了|剪了|剪过|驱虫了|驱过虫|体检了|复诊了|检查了|做了|做过|'
    r'去了|去过|打了|打过|吃了|吃过|看了|看过|用过了)',
  ).hasMatch(text)) {
    return false;
  }
  if (RegExp(r'(周|星期)[一二三四五六日天]').hasMatch(text)) return true;
  return (text.contains('今天') || text.contains('今晚') || text.contains('周末')) &&
      RegExp(r'(要|得|需要|打算|准备|计划|安排|预约|约|提醒)').hasMatch(text);
}

bool _looksLikeAppointment(String text) =>
    appointmentTypeForText(text) != null &&
    !_looksLikeQuestion(text) &&
    hasFutureAppointmentCue(text);

/// Resolves the date of a future plan. Returns null when no date cue is found.
String? parseAppointmentDate(String text, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  String fmt(DateTime d) => _formatDate(d);

  var match = RegExp(
    r'(\d{4})\s*[-/年]\s*(\d{1,2})\s*[-/月]\s*(\d{1,2})\s*[日号]?',
  ).firstMatch(text);
  if (match != null) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year == year && date.month == month && date.day == day) {
      return fmt(date);
    }
  }

  match = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]').firstMatch(text);
  if (match != null) {
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    var date = DateTime(today.year, month, day);
    if (date.month == month && date.day == day) {
      if (date.isBefore(today)) date = DateTime(today.year + 1, month, day);
      return fmt(date);
    }
  }

  match = RegExp(r'下个?月\s*(\d{1,2})\s*[日号]').firstMatch(text);
  if (match != null) {
    final day = int.parse(match.group(1)!);
    final month = today.month == 12 ? 1 : today.month + 1;
    final year = today.month == 12 ? today.year + 1 : today.year;
    final date = DateTime(year, month, day);
    if (date.month == month && date.day == day) return fmt(date);
  }

  match = RegExp(r'(\d{1,2})\s*天\s*后').firstMatch(text);
  if (match != null) {
    final days = int.parse(match.group(1)!);
    if (days > 0 && days <= 3650) return fmt(today.add(Duration(days: days)));
  }

  match = RegExp(r'(\d{1,2})\s*(?:个)?\s*(?:周|星期)\s*后').firstMatch(text);
  if (match != null) {
    final weeks = int.parse(match.group(1)!);
    if (weeks > 0 && weeks <= 520) {
      return fmt(today.add(Duration(days: weeks * 7)));
    }
  }

  if (text.contains('大后天')) return fmt(today.add(const Duration(days: 3)));
  if (text.contains('后天')) return fmt(today.add(const Duration(days: 2)));
  if (text.contains('明天') || text.contains('明日')) {
    return fmt(today.add(const Duration(days: 1)));
  }
  if (text.contains('今晚') || text.contains('今天') || text.contains('今日')) {
    return fmt(today);
  }

  if (text.contains('周末')) {
    final saturday = today.add(Duration(days: 6 - today.weekday));
    final isNext = text.contains('下个周末') || text.contains('下周末');
    if (isNext) return fmt(saturday.add(const Duration(days: 7)));
    if (saturday.isBefore(today)) {
      return fmt(saturday.add(const Duration(days: 7)));
    }
    return fmt(saturday);
  }

  const weekdays = <String, int>{
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
  };
  match = RegExp(r'下\s*(?:个)?\s*(?:周|星期)\s*([一二三四五六日天])').firstMatch(text);
  if (match != null) {
    final monday = today
        .subtract(Duration(days: today.weekday - 1))
        .add(const Duration(days: 7));
    return fmt(monday.add(Duration(days: weekdays[match.group(1)]! - 1)));
  }
  if (RegExp(r'下\s*(?:个)?\s*(?:周|星期)').hasMatch(text)) {
    final monday = today
        .subtract(Duration(days: today.weekday - 1))
        .add(const Duration(days: 7));
    return fmt(monday);
  }

  match = RegExp(r'(?:这|本)?\s*(?:周|星期)\s*([一二三四五六日天])').firstMatch(text);
  if (match != null) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    var date = monday.add(Duration(days: weekdays[match.group(1)]! - 1));
    if (date.isBefore(today)) date = date.add(const Duration(days: 7));
    return fmt(date);
  }
  return null;
}

/// Turns "下周一要给手抓饼做个驱虫" into an appointment capture.
CaptureEvent? parseLocalAppointment(String text, List<Pet> pets) {
  if (_looksLikeQuestion(text)) return null;
  final type = appointmentTypeForText(text);
  if (type == null || !hasFutureAppointmentCue(text)) return null;
  final scheduledAt = parseAppointmentDate(text);
  if (scheduledAt == null) return null;
  final pet = matchPet(text, pets);
  final label = appointmentTypeLabel(type);
  return CaptureEvent(
    kind: 'appointment',
    petId: pet?.id ?? '',
    petName: pet?.name ?? '',
    label: '预约 $scheduledAt · $label',
    title: label,
    occurredAt: scheduledAt,
    scheduledAt: scheduledAt,
    appointmentType: type,
    note: text,
  );
}

final _recordCommandPattern = RegExp(
  r'(记下|记一下|记录一下|记录下|帮我记|帮忙记|存一下|存档|归档|写成.{0,6}记录|作为.{0,6}记录|当做.{0,6}记录|当作.{0,6}记录)',
);

/// True when the user explicitly asks to save something into the profile.
bool isRecordCommand(String text) => _recordCommandPattern.hasMatch(text);

/// Viewer pets are shared read-only and cannot receive automatic writes.
bool canAutoWrite(Pet pet) => pet.role != 'viewer';

/// Automatic captures can be undone for two minutes after the card is created.
const captureUndoWindow = Duration(minutes: 2);

bool canUndoCaptureAt(String createdAt, {DateTime? now}) {
  final created = DateTime.tryParse(createdAt);
  if (created == null) return false;
  return (now ?? DateTime.now()).isBefore(created.add(captureUndoWindow));
}

/// Finds the user message a bare "记下吧" command refers to. Returns null when
/// there is no earlier message or it already produced a capture card.
String? previousUserTextForCapture(List<AiStoredMessage> messages) {
  var previous = -1;
  for (var i = messages.length - 2; i >= 0; i--) {
    if (messages[i].role == 'user' && messages[i].content.trim().isNotEmpty) {
      previous = i;
      break;
    }
  }
  if (previous < 0) return null;
  for (var i = previous + 1; i < messages.length - 1; i++) {
    if (messages[i].isCapture && messages[i].captures.isNotEmpty) return null;
    if (messages[i].role == 'user') break;
  }
  final content = messages[previous].content.trim();
  return content.isEmpty ? null : content;
}

String _formatKg(double kg) {
  final text = kg.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Deterministic, offline extraction for the common phrasings.
List<CaptureEvent> parseLocalCaptures(String text, List<Pet> pets) {
  final newPet = _parseNewPet(text);
  if (newPet != null) return [newPet];

  final appointment = parseLocalAppointment(text, pets);
  if (appointment != null) return [appointment];

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
        occurredAt: parseRecordDate(text),
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
      occurredAt: parseRecordDate(text),
      payload: {'symptoms': symptom, 'note': text},
      note: text,
    ));
  }

  final diet = _dietWords.firstWhere(text.contains, orElse: () => '');
  // Only record food when the user describes an action (changed/ate/tried),
  // not when they merely ask for a recommendation.
  final dietAction = RegExp(r'(换|吃|喂|买|试|用)(了|过|上|成|着)').hasMatch(text) ||
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
      occurredAt: parseRecordDate(text),
      payload: {'product': product, 'note': text},
      note: text,
    ));
  }

  final growth = _growthWords.firstWhere(text.contains, orElse: () => '');
  if (growth.isNotEmpty && events.isEmpty && !_looksLikeQuestion(text)) {
    final title = text.length > 30 ? text.substring(0, 30) : text;
    events.add(CaptureEvent(
      kind: 'growth',
      petId: pet?.id ?? '',
      petName: pet?.name ?? '',
      label: '成长：$title',
      title: title,
      occurredAt: parseRecordDate(text),
      payload: {'note': text},
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
  final hasCue =
      _newPetCues.any(text.contains) || RegExp(r'养了(一)?[只条]').hasMatch(text);
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
  final ageMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(岁|个月|月)').firstMatch(text);
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

  final speciesLabel = species == 'cat'
      ? '猫'
      : species == 'dog'
          ? '狗'
          : '其他';
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
你是宠物档案信息抽取器。今天是 ${_today()}。已知账号下的宠物：$list。
从用户这句话里提取需要写入档案的已发生事实，只输出一个 JSON 对象，不要 markdown 或解释。
格式：
{"events":[
 {"kind":"weight|medical|diet","pet":"宠物名字或空字符串","occurredAt":"YYYY-MM-DD","weightKg":2.5,
  "title":"不超过 20 字","note":"原始描述","product":"换粮/食品名称"},
 {"kind":"growth","pet":"宠物名字或空字符串","occurredAt":"YYYY-MM-DD","title":"不超过 20 字","note":"原始描述"},
 {"kind":"pet","name":"新宠物名字","species":"cat|dog|other","breed":"","sex":"male|female|unknown",
  "birthday":"YYYY-MM-DD 或空","ageMonths":24,"weightKg":2.5,"neutered":"yes|no|unknown","note":"原始描述"},
 {"kind":"appointment","pet":"宠物名字或空字符串","scheduledAt":"YYYY-MM-DD",
  "appointmentType":"vaccine|deworming|checkup|medical|medication|grooming|other",
  "title":"不超过 20 字","note":"原始描述"}
]}
规则：
1. 只提取用户明确陈述、已经发生的事实；提问、假设不要记录。
   未来要做的照护计划用 appointment，不要记为已发生的健康记录。
2. weight 必须给出公斤数；用户用“斤”时要换算成公斤（1 斤 = 0.5 kg）。
3. medical 用于症状/就诊，title 用简短症状；diet 用于换粮、食品、配方。
   growth 用于宠物日常的成长瞬间：玩耍、第一次、学会新本领、开心可爱的小事、出门游玩等，title 概括这件事。
4. pet 只用于用户明确说“新养/领养/家里来了/捡到”等新加入的宠物，且必须能确定名字；
   已经在列表里的宠物绝不能输出 pet 事件。
5. 无法确定是哪只宠物时 pet 留空，不要猜。
6. 没有可记录内容时输出 {"events":[]}；不要编造数值或名字。
7. 同一句话如果已经输出 weight、medical 或 diet，就不要再输出 growth。
8. growth 的 title 用用户的原话概括，不要写成医疗建议；note 保留原始描述。
9. occurredAt 解析用户陈述的日期：支持“今天/昨天/前天/10月5号/2026-10-05”等；没有日期时用今天。
10. appointment 只用于未来计划，例如“下周一要给手抓饼做个驱虫”“明天带猫去洗澡”。
11. scheduledAt 必须解析成具体日期：“明天/后天/下周X/周X/下个月X号/10月5号/N天后”等；
    无法确定日期时不要输出 appointment。
12. appointmentType 按内容选择：驱虫=deworming，疫苗/接种=vaccine，体检/复查=checkup，
    看病/就诊/复诊/手术/绝育=medical，喂药/用药=medication，洗澡/洗护/美容=grooming，其余=other。
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
    final rawOccurredAt = ((item['occurredAt'] as String?) ?? '').trim();
    final occurredAt = _normalizeDate(rawOccurredAt).isEmpty
        ? _today()
        : _normalizeDate(rawOccurredAt);
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
      final speciesLabel = species == 'cat'
          ? '猫'
          : species == 'dog'
              ? '狗'
              : '其他';
      out.add(CaptureEvent(
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
          'currentWeightKg': (kg > 0 && kg <= 120) ? kg : 0,
          'allergies': '',
          'chronicConditions': '',
          'medications': '',
        },
        note: note,
      ));
      continue;
    }
    if (kind == 'appointment') {
      var scheduledAt =
          _normalizeDate(((item['scheduledAt'] as String?) ?? '').trim());
      if (scheduledAt.isEmpty) {
        // Some models put the plan date in occurredAt instead.
        scheduledAt =
            _normalizeDate(((item['occurredAt'] as String?) ?? '').trim());
      }
      if (scheduledAt.isEmpty) continue;
      var type = ((item['appointmentType'] as String?) ?? 'other').trim();
      if (!appointmentTypeLabels.containsKey(type)) {
        type = appointmentTypeForText(note) ?? 'other';
      }
      final label = appointmentTypeLabel(type);
      final rawTitle = ((item['title'] as String?) ?? '').trim();
      final title = rawTitle.isEmpty
          ? label
          : (rawTitle.length > 30 ? rawTitle.substring(0, 30) : rawTitle);
      out.add(CaptureEvent(
        kind: 'appointment',
        petId: pet?.id ?? '',
        petName: pet?.name ?? petName,
        label: '预约 $scheduledAt · $label',
        title: title,
        occurredAt: scheduledAt,
        scheduledAt: scheduledAt,
        appointmentType: type,
        note: note,
      ));
    } else if (kind == 'weight') {
      final kg = (item['weightKg'] as num?)?.toDouble() ?? 0;
      if (kg <= 0 || kg > 120) continue;
      out.add(CaptureEvent(
        kind: 'weight',
        petId: pet?.id ?? '',
        petName: pet?.name ?? petName,
        label: '体重 ${_formatKg(kg)} kg',
        weightKg: kg,
        occurredAt: occurredAt,
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
        occurredAt: occurredAt,
        payload: kind == 'medical'
            ? {'symptoms': title, 'note': note}
            : {'product': product, 'note': note},
        note: note,
      ));
    } else if (kind == 'growth') {
      final title = ((item['title'] as String?) ?? '').trim();
      final resolved = title.isEmpty ? '成长记录' : title;
      out.add(CaptureEvent(
        kind: 'growth',
        petId: pet?.id ?? '',
        petName: pet?.name ?? petName,
        label: '成长：$resolved',
        title: resolved.length > 30 ? resolved.substring(0, 30) : resolved,
        occurredAt: occurredAt,
        payload: {'note': note.isEmpty ? resolved : note},
        note: note.isEmpty ? resolved : note,
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
  if (event.kind == 'appointment') {
    if (event.scheduledAt.isEmpty) {
      throw StateError('缺少预约日期');
    }
    final appointment = await api.createAppointment(event.petId, {
      'type': event.appointmentType.isEmpty ? 'other' : event.appointmentType,
      'title': event.title.isEmpty ? event.label : event.title,
      'scheduledAt': event.scheduledAt,
      'note': event.note,
    });
    return AiCapture(
      kind: 'appointment',
      id: appointment.id,
      petId: event.petId,
      petName: event.petName,
      label: '${event.petName} · ${event.label}',
    );
  }
  final occurredAt = event.occurredAt.isEmpty ? _today() : event.occurredAt;
  if (event.kind == 'weight') {
    final weight = await api.createWeight(event.petId, {
      'measuredAt': occurredAt,
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
    'occurredAt': occurredAt,
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
  } else if (capture.kind == 'appointment') {
    await api.deleteAppointment(capture.id);
  } else {
    await api.deleteRecord(capture.id);
  }
}
