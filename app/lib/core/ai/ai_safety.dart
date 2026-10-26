import '../models.dart';

enum RiskLevel { l0, l1, l2, l3 }

class RiskAssessment {
  const RiskAssessment({
    required this.level,
    required this.label,
    required this.advice,
  });

  final RiskLevel level;
  final String label;
  final String advice;

  bool get isRed => level == RiskLevel.l3;
  bool get isWarning => level == RiskLevel.l2;
}

const _redFlags = [
  '呼吸困难',
  '抽搐',
  '大量出血',
  '误食',
  '中毒',
  '无法排尿',
  '尿闭',
  '意识丧失',
  '昏迷',
  '难产',
  '高热',
  '高烧',
  '严重外伤',
  '车祸',
  '坠楼',
  '休克',
  '瞳孔散大',
  '舌头变紫',
  '牙龈苍白',
];

const _urgent = [
  '便血',
  '吐血',
  '持续呕吐',
  '持续腹泻',
  '不吃不喝',
  '呼吸急促',
  '腹部胀大',
  '精神萎靡',
  '精神差',
  '走路不稳',
  '剧烈疼痛',
  '发烧',
  '发热',
];

const _mild = [
  '呕吐',
  '腹泻',
  '软便',
  '咳嗽',
  '打喷嚏',
  '皮肤',
  '瘙痒',
  '掉毛',
  '眼屎',
  '耳螨',
  '食欲下降',
  '流泪',
];

RiskAssessment assessRisk(String userText, {String aiText = ''}) {
  // L3 must come from what the owner reports. Otherwise an educational answer
  // that lists red-flag symptoms (e.g. "如果出现无法排尿…") would wrongly show
  // the emergency card.
  for (final word in _redFlags) {
    if (userText.contains(word)) {
      return const RiskAssessment(
        level: RiskLevel.l3,
        label: '紧急就医',
        advice: '出现可能危及生命的症状，请立即联系或前往宠物医院，不要等待在线建议。',
      );
    }
  }
  final text = '$userText\n$aiText';
  for (final word in _urgent) {
    if (text.contains(word)) {
      return const RiskAssessment(
        level: RiskLevel.l2,
        label: '建议 24 小时内就医',
        advice: '症状需要兽医评估，建议尽快预约就诊，并记录症状变化。',
      );
    }
  }
  for (final word in _mild) {
    if (text.contains(word)) {
      return const RiskAssessment(
        level: RiskLevel.l1,
        label: '先观察',
        advice: '可以先观察精神、食欲和排泄，若持续或加重请及时就医。',
      );
    }
  }
  return const RiskAssessment(
    level: RiskLevel.l0,
    label: '日常照护',
    advice: '',
  );
}

class PetProfileContext {
  const PetProfileContext({
    required this.pet,
    required this.records,
    required this.weights,
  });

  final Pet pet;
  final List<HealthRecord> records;
  final List<WeightRecord> weights;
}

/// System prompt for the account-wide assistant. It knows every pet and must
/// resolve which one the user is talking about instead of guessing.
String buildGlobalSystemPrompt(List<PetProfileContext> contexts) {
  final names = contexts.map((c) => '「${c.pet.name}」').join('、');
  final buffer = StringBuffer()
    ..writeln('你是「喵了个咪」宠物照护助手，账号下有多只宠物：$names。')
    ..writeln('用户可能同时提到多只宠物。先根据名字判断在说哪只；名字不明确时先追问，不要猜。')
    ..writeln('自动记录由客户端完成，不由你完成。客户端会自动记录用户明确陈述的体重、症状、换粮、成长瞬间，'
        '以及带日期的未来照护计划（生成预约）；只读共享的宠物不会被自动写入。')
    ..writeln('你没有写入、修改或查看页面的能力。不要声称已经记录/保存/归档/预约，也不要判断成长记录等页面是否为空；'
        '只有界面上的绿色「已自动记录」或「已创建预约」卡片才代表写入成功。')
    ..writeln('用户要求“记下/记录/归档”时，回答“我会把这条整理成记录，请以下方卡片为准；'
        '如果没出现卡片，请到对应宠物的记录页补记”，不要直接说已完成。')
    ..writeln();
  for (final context in contexts) {
    buffer.writeln('===== ${context.pet.name} 的档案 =====');
    buffer.writeln(buildSystemPrompt(
      pet: context.pet,
      records: context.records,
      weights: context.weights,
    ));
    buffer.writeln();
  }
  return buffer.toString();
}

String buildSystemPrompt({
  required Pet pet,
  required List<HealthRecord> records,
  required List<WeightRecord> weights,
}) {
  final age = _ageText(pet.birthday);
  final lines = <String>[
    '你是「喵了个咪」宠物照护助手，用中文回答，语气温和、简洁、可执行。',
    '当前宠物档案：',
    '- 名字：${pet.name}',
    '- 物种/品种：${pet.speciesLabel}${pet.breed.isEmpty ? '' : ' / ${pet.breed}'}',
    '- 性别：${pet.sexLabel}；绝育：${pet.neuteredLabel}',
    '- 访问权限：${pet.role == 'owner' ? '所有者（可读写）' : pet.role == 'co_caregiver' ? '共同照护（可新增记录）' : '只读共享（不能写入）'}',
    if (age.isNotEmpty) '- 年龄：$age',
    if (pet.currentWeightKg > 0)
      '- 当前体重：${pet.currentWeightKg.toStringAsFixed(1)} kg',
    if (pet.allergies.isNotEmpty) '- 过敏史：${pet.allergies}',
    if (pet.chronicConditions.isNotEmpty) '- 慢性病：${pet.chronicConditions}',
    if (pet.medications.isNotEmpty) '- 长期用药：${pet.medications}',
    '- 电子身份证号：${pet.identityNo}',
  ];
  if (weights.isNotEmpty) {
    final recent =
        weights.length > 4 ? weights.sublist(weights.length - 4) : weights;
    lines.add(
      '- 最近体重：${recent.map((w) => '${w.measuredAt} ${w.weightKg.toStringAsFixed(1)}kg').join('，')}',
    );
  }
  if (records.isNotEmpty) {
    lines.add('最近健康记录：');
    for (final record in records.take(8)) {
      final summary = record.summary.isEmpty ? '' : '（${record.summary}）';
      lines.add(
        '- ${record.occurredAt} ${record.typeLabel}：${record.title}$summary'
        '${record.nextDueAt.isEmpty ? '' : '，下次 ${record.nextDueAt}'}',
      );
    }
  }
  lines.addAll(const [
    '回答规则（必须遵守）：',
    '1. 结合当前宠物档案回答，不要给通用模板；信息不足时先追问。',
    '2. 禁止确诊、开处方、推荐人用药替代或给出具体药物剂量。',
    '3. 出现呼吸困难、抽搐、大量出血、误食毒物、无法排尿、意识丧失、难产、高热、严重外伤等情况，第一句话必须建议立即就医。',
    '4. 自动记录由客户端完成；你没有写入能力。不要声称已记录/已保存/已归档/已预约，也不要判断页面是否为空。'
        '只有绿色「已自动记录」或「已创建预约」卡片才代表写入成功。',
    '5. 只读共享宠物不会被自动写入；需要记录时请让所有者操作。',
  ]);
  return lines.join('\n');
}

String buildRecordExtractionPrompt(Pet pet) {
  return '''
你是宠物照护记录提取器。根据用户与助手的对话，提取一条健康记录。
只输出一个 JSON 对象，不要输出 markdown、解释或代码块。
字段：
{"type":"vaccine|deworming|checkup|medical|medication|grooming|other",
 "occurredAt":"YYYY-MM-DD",
 "title":"不超过 30 字",
 "payload":{"键":"值"},
 "hospital":"","doctor":"",
 "nextDueAt":"YYYY-MM-DD 或空字符串"}
payload 建议键：疫苗 vaccineName/batchNo；驱虫 product/dose/weightKg/method；
体检 weightKg/temperature/conclusion/advice；病历 symptoms/diagnosis/prescription/advice；
用药 product/dose/frequency/period；洗护 item/store/note。
当前日期未知时使用今天；宠物是「${pet.name}」。信息缺失时不要编造，留空字符串。
''';
}

String _ageText(String birthday) {
  final date = DateTime.tryParse(birthday);
  if (date == null) return '';
  final now = DateTime.now();
  var months = (now.year - date.year) * 12 + now.month - date.month;
  if (now.day < date.day) months--;
  if (months < 0) return '';
  if (months < 12) return '$months 个月';
  final years = months ~/ 12;
  final rest = months % 12;
  return rest == 0 ? '$years 岁' : '$years 岁 $rest 个月';
}
