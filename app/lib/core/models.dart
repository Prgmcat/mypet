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

class InviteCode {
  final String id;
  final int maxUses;
  final int usedCount;
  final String expiresAt;
  final String status;
  final String createdAt;

  InviteCode({
    required this.id,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAt,
    required this.status,
    required this.createdAt,
  });

  factory InviteCode.fromJson(Map<String, dynamic> json) => InviteCode(
        id: json['id'] as String,
        maxUses: (json['maxUses'] as num?)?.toInt() ?? 0,
        usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
        expiresAt: (json['expiresAt'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
        createdAt: (json['createdAt'] as String?) ?? '',
      );

  String get statusLabel => switch (status) {
        'active' => '有效',
        'used' => '已用完',
        'revoked' => '已作废',
        'expired' => '已过期',
        _ => status,
      };
}

class AdminDevice {
  final String id;
  final String userId;
  final String username;
  final String name;
  final String lastSeenAt;
  final String createdAt;
  final String revokedAt;

  AdminDevice({
    required this.id,
    required this.userId,
    required this.username,
    required this.name,
    required this.lastSeenAt,
    required this.createdAt,
    required this.revokedAt,
  });

  factory AdminDevice.fromJson(Map<String, dynamic> json) => AdminDevice(
        id: json['id'] as String,
        userId: (json['userId'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        lastSeenAt: (json['lastSeenAt'] as String?) ?? '',
        createdAt: (json['createdAt'] as String?) ?? '',
        revokedAt: (json['revokedAt'] as String?) ?? '',
      );

  bool get active => revokedAt.isEmpty;
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

class Attachment {
  final String id;
  final String petId;
  final String recordId;
  final String originalName;
  final String mime;
  final int size;

  Attachment({
    required this.id,
    required this.petId,
    required this.recordId,
    required this.originalName,
    required this.mime,
    required this.size,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        petId: (json['petId'] as String?) ?? '',
        recordId: (json['recordId'] as String?) ?? '',
        originalName: (json['originalName'] as String?) ?? '',
        mime: (json['mime'] as String?) ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'recordId': recordId,
        'originalName': originalName,
        'mime': mime,
        'size': size,
      };
}

class HealthRecord {
  final String id;
  final String petId;
  final String type;
  final String occurredAt;
  final String title;
  final Map<String, dynamic> payload;
  final String hospital;
  final String doctor;
  final String nextDueAt;
  final String source;
  final String createdByType;
  final String createdByUserId;
  final int version;
  final List<Attachment> attachments;

  HealthRecord({
    required this.id,
    required this.petId,
    required this.type,
    required this.occurredAt,
    required this.title,
    required this.payload,
    required this.hospital,
    required this.doctor,
    required this.nextDueAt,
    required this.source,
    required this.createdByType,
    required this.createdByUserId,
    required this.version,
    required this.attachments,
  });

  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        id: json['id'] as String,
        petId: (json['petId'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'other',
        occurredAt: (json['occurredAt'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        hospital: (json['hospital'] as String?) ?? '',
        doctor: (json['doctor'] as String?) ?? '',
        nextDueAt: (json['nextDueAt'] as String?) ?? '',
        source: (json['source'] as String?) ?? 'manual',
        createdByType: (json['createdByType'] as String?) ?? 'user',
        createdByUserId: (json['createdByUserId'] as String?) ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        attachments: ((json['attachments'] as List?) ?? const [])
            .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  String get typeLabel => switch (type) {
        'vaccine' => '疫苗',
        'deworming' => '驱虫',
        'checkup' => '体检',
        'medical' => '病历',
        'medication' => '用药',
        'grooming' => '洗护',
        'diet' => '饮食',
        _ => '其他',
      };

  String get summary {
    final entries = payload.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .take(3)
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    return entries;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'type': type,
        'occurredAt': occurredAt,
        'title': title,
        'payload': payload,
        'hospital': hospital,
        'doctor': doctor,
        'nextDueAt': nextDueAt,
        'source': source,
        'createdByType': createdByType,
        'createdByUserId': createdByUserId,
        'version': version,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };
}

class WeightRecord {
  final String id;
  final String petId;
  final String measuredAt;
  final double weightKg;
  final String note;

  WeightRecord({
    required this.id,
    required this.petId,
    required this.measuredAt,
    required this.weightKg,
    required this.note,
  });

  factory WeightRecord.fromJson(Map<String, dynamic> json) => WeightRecord(
        id: json['id'] as String,
        petId: (json['petId'] as String?) ?? '',
        measuredAt: (json['measuredAt'] as String?) ?? '',
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        note: (json['note'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'measuredAt': measuredAt,
        'weightKg': weightKg,
        'note': note,
      };
}

class TimelineEntry {
  final String kind;
  final String at;
  final HealthRecord? record;
  final WeightRecord? weight;

  TimelineEntry({
    required this.kind,
    required this.at,
    this.record,
    this.weight,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        kind: (json['kind'] as String?) ?? 'record',
        at: (json['at'] as String?) ?? '',
        record: json['record'] == null
            ? null
            : HealthRecord.fromJson(json['record'] as Map<String, dynamic>),
        weight: json['weight'] == null
            ? null
            : WeightRecord.fromJson(json['weight'] as Map<String, dynamic>),
      );
}

class Reminder {
  final String id;
  final String ruleId;
  final String petId;
  final String petName;
  final String type;
  final String occurrenceKey;
  final String dueAt;
  final String status;
  final List<int> advanceOffsets;
  final String snoozedUntil;
  final String completedAt;
  final String recordId;
  final String role;

  Reminder({
    required this.id,
    required this.ruleId,
    required this.petId,
    required this.petName,
    required this.type,
    required this.occurrenceKey,
    required this.dueAt,
    required this.status,
    required this.advanceOffsets,
    required this.snoozedUntil,
    required this.completedAt,
    required this.recordId,
    required this.role,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as String,
        ruleId: (json['ruleId'] as String?) ?? '',
        petId: (json['petId'] as String?) ?? '',
        petName: (json['petName'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'other',
        occurrenceKey: (json['occurrenceKey'] as String?) ?? '',
        dueAt: (json['dueAt'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'pending',
        advanceOffsets: ((json['advanceOffsets'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(growable: false),
        snoozedUntil: (json['snoozedUntil'] as String?) ?? '',
        completedAt: (json['completedAt'] as String?) ?? '',
        recordId: (json['recordId'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'owner',
      );

  String get typeLabel => switch (type) {
        'vaccine' => '疫苗',
        'deworming' => '驱虫',
        'checkup' => '体检',
        'birthday' => '生日',
        'grooming' => '洗护',
        _ => '照护',
      };

  String get emoji => switch (type) {
        'vaccine' => '💉',
        'deworming' => '💊',
        'checkup' => '🩺',
        'birthday' => '🎂',
        'grooming' => '🛁',
        _ => '📝',
      };

  bool get canAct => role != 'viewer' && status != 'done' && status != 'skipped';

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleId': ruleId,
        'petId': petId,
        'petName': petName,
        'type': type,
        'occurrenceKey': occurrenceKey,
        'dueAt': dueAt,
        'status': status,
        'advanceOffsets': advanceOffsets,
        'snoozedUntil': snoozedUntil,
        'completedAt': completedAt,
        'recordId': recordId,
        'role': role,
      };
}

class ReminderRule {
  final String id;
  final String petId;
  final String type;
  final int intervalDays;
  final String nextDueAt;
  final List<int> advanceOffsets;
  final bool enabled;

  ReminderRule({
    required this.id,
    required this.petId,
    required this.type,
    required this.intervalDays,
    required this.nextDueAt,
    required this.advanceOffsets,
    required this.enabled,
  });

  factory ReminderRule.fromJson(Map<String, dynamic> json) => ReminderRule(
        id: json['id'] as String,
        petId: (json['petId'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 0,
        nextDueAt: (json['nextDueAt'] as String?) ?? '',
        advanceOffsets: ((json['advanceOffsets'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(growable: false),
        enabled: json['enabled'] == true,
      );
}

class PetMember {
  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String role;
  final String joinedAt;

  PetMember({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  factory PetMember.fromJson(Map<String, dynamic> json) => PetMember(
        id: json['id'] as String,
        userId: (json['userId'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'viewer',
        joinedAt: (json['joinedAt'] as String?) ?? '',
      );

  String get roleLabel => role == 'co_caregiver' ? '共同照护' : '只读';
}

class ShareGrant {
  final String id;
  final String petId;
  final String petName;
  final String role;
  final String expiresAt;
  final bool hasPasscode;
  final String status;
  final String createdAt;
  final String token;

  ShareGrant({
    required this.id,
    required this.petId,
    required this.petName,
    required this.role,
    required this.expiresAt,
    required this.hasPasscode,
    required this.status,
    required this.createdAt,
    required this.token,
  });

  factory ShareGrant.fromJson(Map<String, dynamic> json) => ShareGrant(
        id: json['id'] as String,
        petId: (json['petId'] as String?) ?? '',
        petName: (json['petName'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'viewer',
        expiresAt: (json['expiresAt'] as String?) ?? '',
        hasPasscode: json['hasPasscode'] == true,
        status: (json['status'] as String?) ?? 'active',
        createdAt: (json['createdAt'] as String?) ?? '',
        token: (json['token'] as String?) ?? '',
      );

  String get roleLabel => role == 'co_caregiver' ? '共同照护' : '只读';
  String get statusLabel => switch (status) {
        'active' => '有效',
        'revoked' => '已撤销',
        'expired' => '已过期',
        _ => status,
      };
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
  final String avatarPath;

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
    this.avatarPath = '',
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
        avatarPath: (json['avatarPath'] as String?) ?? '',
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUserId': ownerUserId,
        'name': name,
        'species': species,
        'breed': breed,
        'sex': sex,
        'birthday': birthday,
        'birthdayEstimated': birthdayEstimated,
        'neutered': neutered,
        'currentWeightKg': currentWeightKg,
        'allergies': allergies,
        'chronicConditions': chronicConditions,
        'medications': medications,
        'identityNo': identityNo,
        'status': status,
        'version': version,
        'role': role,
        'avatarPath': avatarPath,
      };
}
