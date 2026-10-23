class User {
  final String id;
  final String username;
  final String displayName;
  final bool isAdmin;
  final String status;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isAdmin,
    required this.status,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: (json['displayName'] as String?) ?? '',
        isAdmin: json['isAdmin'] == true,
        status: (json['status'] as String?) ?? 'active',
      );
}

class Device {
  final String id;
  final String name;
  final String? lastSeenAt;

  Device({required this.id, required this.name, this.lastSeenAt});

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        lastSeenAt: json['lastSeenAt'] as String?,
      );
}

class Pet {
  final String id;
  final String ownerUserId;
  final String name;
  final String species;
  final String breed;
  final String sex;
  final String birthday;
  final bool birthdayEstimated;
  final String neutered;
  final double currentWeightKg;
  final String allergies;
  final String chronicConditions;
  final String medications;
  final String identityNo;
  final String status;
  final int version;
  final String role;

  Pet({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.species,
    required this.breed,
    required this.sex,
    required this.birthday,
    required this.birthdayEstimated,
    required this.neutered,
    required this.currentWeightKg,
    required this.allergies,
    required this.chronicConditions,
    required this.medications,
    required this.identityNo,
    required this.status,
    required this.version,
    required this.role,
  });

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        id: json['id'] as String,
        ownerUserId: (json['ownerUserId'] as String?) ?? '',
        name: json['name'] as String,
        species: (json['species'] as String?) ?? '',
        breed: (json['breed'] as String?) ?? '',
        sex: (json['sex'] as String?) ?? 'unknown',
        birthday: (json['birthday'] as String?) ?? '',
        birthdayEstimated: json['birthdayEstimated'] == true,
        neutered: (json['neutered'] as String?) ?? 'unknown',
        currentWeightKg: (json['currentWeightKg'] as num?)?.toDouble() ?? 0,
        allergies: (json['allergies'] as String?) ?? '',
        chronicConditions: (json['chronicConditions'] as String?) ?? '',
        medications: (json['medications'] as String?) ?? '',
        identityNo: (json['identityNo'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
        version: (json['version'] as num?)?.toInt() ?? 1,
        role: (json['role'] as String?) ?? 'owner',
      );

  bool get isOwner => role == 'owner';
  bool get isShared => role != 'owner';

  String get speciesLabel => switch (species) {
        'cat' => '猫',
        'dog' => '狗',
        _ => '其他',
      };

  String get sexLabel => switch (sex) {
        'male' => '公',
        'female' => '母',
        _ => '未知',
      };

  String get neuteredLabel => switch (neutered) {
        'yes' => '已绝育',
        'no' => '未绝育',
        _ => '未知',
      };
}
