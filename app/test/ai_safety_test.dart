import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/ai/ai_safety.dart';
import 'package:miaolegemi/core/models.dart';

Pet buildPet() => Pet(
      id: 'pet-1',
      ownerUserId: 'u1',
      name: '咪咪',
      species: 'cat',
      breed: '美短',
      sex: 'female',
      birthday: '2021-03-05',
      birthdayEstimated: false,
      neutered: 'yes',
      currentWeightKg: 4.2,
      allergies: '鸡肉过敏',
      chronicConditions: '慢性肾病',
      medications: '处方粮',
      identityNo: 'PET2026123456',
      status: 'active',
      version: 1,
      role: 'owner',
    );

void main() {
  test('red flag symptoms are L3 regardless of model output', () {
    final risk = assessRisk('咪咪突然呼吸困难，牙龈发白');
    expect(risk.level, RiskLevel.l3);
    expect(risk.isRed, true);
    expect(risk.advice, contains('立即'));
  });

  test('urgent symptoms are L2', () {
    final risk = assessRisk('从昨晚开始持续呕吐');
    expect(risk.level, RiskLevel.l2);
  });

  test('mild symptoms are L1 and normal questions are L0', () {
    expect(assessRisk('有点软便').level, RiskLevel.l1);
    expect(assessRisk('下次驱虫是什么时候').level, RiskLevel.l0);
  });

  test('educational red flags in the answer do not raise L3', () {
    final risk = assessRisk('它不太舒服', aiText: '如果出现抽搐、无法排尿请立刻就医');
    expect(risk.level, isNot(RiskLevel.l3));
  });

  test('system prompt includes the pet profile and safety rules', () {
    final prompt = buildSystemPrompt(
      pet: buildPet(),
      records: [
        HealthRecord(
          id: 'r1',
          petId: 'pet-1',
          type: 'vaccine',
          occurredAt: '2026-01-01',
          title: '猫三联',
          payload: const {'vaccineName': '猫三联'},
          hospital: '',
          doctor: '',
          nextDueAt: '2027-01-01',
          source: 'manual',
          createdByType: 'user',
          createdByUserId: 'u1',
          version: 1,
          attachments: const [],
        ),
      ],
      weights: [
        WeightRecord(
          id: 'w1',
          petId: 'pet-1',
          measuredAt: '2026-10-01',
          weightKg: 4.2,
          note: '',
        ),
      ],
    );
    expect(prompt, contains('咪咪'));
    expect(prompt, contains('鸡肉过敏'));
    expect(prompt, contains('慢性肾病'));
    expect(prompt, contains('猫三联'));
    expect(prompt, contains('禁止确诊'));
    expect(prompt, contains('紧急就医'));
  });

  test('record extraction prompt requests a single JSON object', () {
    final prompt = buildRecordExtractionPrompt(buildPet());
    expect(prompt, contains('只输出一个 JSON 对象'));
    expect(prompt, contains('occurredAt'));
    expect(prompt, contains('咪咪'));
  });
}
