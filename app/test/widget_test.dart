import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/models.dart';

void main() {
  test('Pet parses server payload and labels', () {
    final pet = Pet.fromJson({
      'id': 'p1',
      'ownerUserId': 'u1',
      'name': 'Mimi',
      'species': 'cat',
      'breed': '美短',
      'sex': 'female',
      'neutered': 'yes',
      'identityNo': 'PET2026123456',
      'status': 'active',
      'version': 1,
      'role': 'owner',
      'currentWeightKg': 3.2,
    });

    expect(pet.name, 'Mimi');
    expect(pet.speciesLabel, '猫');
    expect(pet.sexLabel, '母');
    expect(pet.neuteredLabel, '已绝育');
    expect(pet.isOwner, isTrue);
    expect(pet.currentWeightKg, 3.2);
  });

  test('Shared pet is not owner', () {
    final pet = Pet.fromJson({
      'id': 'p2',
      'name': 'DouDou',
      'species': 'dog',
      'role': 'co_caregiver',
    });

    expect(pet.isShared, isTrue);
    expect(pet.speciesLabel, '狗');
  });
}
