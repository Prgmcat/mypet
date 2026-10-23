import 'package:dio/dio.dart';

import 'models.dart';

class ApiException implements Exception {
  final int code;
  final String message;

  ApiException(this.code, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient() : _dio = Dio();

  final Dio _dio;
  String _baseUrl = '';

  String get baseUrl => _baseUrl;

  Map<String, String> get authHeaders => {
        for (final entry in _dio.options.headers.entries)
          entry.key: entry.value.toString(),
      };

  String attachmentUrl(String id) => '$_baseUrl/api/attachments/$id';

  void configure({required String baseUrl, String? token}) {
    _baseUrl = normalizeBaseUrl(baseUrl);
    _dio.options
      ..baseUrl = _baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..headers = {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
  }

  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
    String deviceName = 'Android',
  }) async {
    configure(baseUrl: baseUrl);
    final data = await _post('/api/auth/login', {
      'username': username,
      'password': password,
      'deviceName': deviceName,
    });
    final result = LoginResult(
      token: data['token'] as String,
      user: User.fromJson(data['user'] as Map<String, dynamic>),
      device: Device.fromJson(data['device'] as Map<String, dynamic>),
    );
    configure(baseUrl: baseUrl, token: result.token);
    return result;
  }

  Future<User> register({
    required String baseUrl,
    required String inviteCode,
    required String username,
    required String password,
    String displayName = '',
  }) async {
    configure(baseUrl: baseUrl);
    final data = await _post('/api/auth/register', {
      'inviteCode': inviteCode,
      'username': username,
      'password': password,
      'displayName': displayName,
    });
    return User.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> health() async {
    final data = await _get('/api/health');
    return (data as Map<String, dynamic>?) ?? const {};
  }

  Future<User> me() async {
    final data = await _get('/api/me');
    return User.fromJson((data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _post('/api/auth/logout', const {});
    } finally {
      _dio.options.headers.remove('Authorization');
    }
  }

  Future<List<Pet>> listPets() async {
    final data = await _get('/api/pets');
    if (data == null) return const [];
    return (data as List)
        .map((e) => Pet.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Pet> getPet(String id) async {
    final data = await _get('/api/pets/$id');
    return Pet.fromJson(data as Map<String, dynamic>);
  }

  Future<Pet> createPet(Map<String, dynamic> payload) async {
    final data = await _post('/api/pets', payload);
    return Pet.fromJson(data as Map<String, dynamic>);
  }

  Future<Pet> updatePet(String id, Map<String, dynamic> payload) async {
    final data = await _patch('/api/pets/$id', payload);
    return Pet.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deletePet(String id) async {
    await _delete('/api/pets/$id');
  }

  Future<List<HealthRecord>> listRecords(String petId, {String? type}) async {
    final data = await _get('/api/pets/$petId/records${type == null || type.isEmpty ? '' : '?type=$type'}');
    if (data == null) return const [];
    return (data as List)
        .map((e) => HealthRecord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<HealthRecord> createRecord(String petId, Map<String, dynamic> payload) async {
    final data = await _post('/api/pets/$petId/records', payload);
    return HealthRecord.fromJson(data as Map<String, dynamic>);
  }

  Future<HealthRecord> updateRecord(String recordId, Map<String, dynamic> payload) async {
    final data = await _patch('/api/records/$recordId', payload);
    return HealthRecord.fromJson((data as Map<String, dynamic>)['record'] as Map<String, dynamic>);
  }

  Future<void> deleteRecord(String recordId) async {
    await _delete('/api/records/$recordId');
  }

  Future<List<WeightRecord>> listWeights(String petId) async {
    final data = await _get('/api/pets/$petId/weights');
    if (data == null) return const [];
    return (data as List)
        .map((e) => WeightRecord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<WeightRecord> createWeight(String petId, Map<String, dynamic> payload) async {
    final data = await _post('/api/pets/$petId/weights', payload);
    return WeightRecord.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteWeight(String weightId) async {
    await _delete('/api/weights/$weightId');
  }

  Future<Attachment> uploadAttachment(
    String petId,
    String filePath, {
    String? recordId,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (recordId != null && recordId.isNotEmpty) 'recordId': recordId,
    });
    final data = await _request(() => _dio.post('/api/pets/$petId/attachments', data: form));
    return Attachment.fromJson(data as Map<String, dynamic>);
  }

  Future<List<TimelineEntry>> listTimeline(String petId, {String? type}) async {
    final suffix = (type == null || type.isEmpty) ? '' : '?type=$type';
    final data = await _get('/api/pets/$petId/timeline$suffix');
    if (data == null) return const [];
    return (data as List)
        .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Reminder>> listReminders({String status = 'pending'}) async {
    final data = await _get('/api/reminders?status=$status');
    if (data == null) return const [];
    return (data as List)
        .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Reminder> updateReminder(
    String id,
    String action, {
    int? snoozeHours,
  }) async {
    final data = await _patch('/api/reminders/$id', {
      'action': action,
      if (snoozeHours != null) 'snoozeHours': snoozeHours,
    });
    return Reminder.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ReminderRule>> listReminderRules(String petId) async {
    final data = await _get('/api/pets/$petId/reminder-rules');
    if (data == null) return const [];
    return (data as List)
        .map((e) => ReminderRule.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ReminderRule> updateReminderRule(
    String ruleId,
    Map<String, dynamic> payload,
  ) async {
    final data = await _put('/api/reminder-rules/$ruleId', payload);
    return ReminderRule.fromJson(data as Map<String, dynamic>);
  }

  Future<List<PetMember>> listMembers(String petId) async {
    final data = await _get('/api/pets/$petId/members');
    if (data == null) return const [];
    return (data as List)
        .map((e) => PetMember.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<PetMember> addMember(
    String petId,
    String username,
    String role,
  ) async {
    final data = await _post('/api/pets/$petId/members', {
      'username': username,
      'role': role,
    });
    return PetMember.fromJson(data as Map<String, dynamic>);
  }

  Future<void> removeMember(String petId, String userId) async {
    await _delete('/api/pets/$petId/members/$userId');
  }

  Future<List<ShareGrant>> listShareGrants() async {
    final data = await _get('/api/share-grants');
    if (data == null) return const [];
    return (data as List)
        .map((e) => ShareGrant.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ShareGrant> createShareGrant(
    String petId, {
    required String role,
    int ttlDays = 7,
    String passcode = '',
  }) async {
    final data = await _post('/api/pets/$petId/share-grants', {
      'role': role,
      'ttlDays': ttlDays,
      'passcode': passcode,
    });
    return ShareGrant.fromJson(data as Map<String, dynamic>);
  }

  Future<void> revokeShareGrant(String grantId) async {
    await _post('/api/share-grants/$grantId/revoke', const {});
  }

  String shareUrl(String token) => '$_baseUrl/g/$token';

  Future<List<Device>> listDevices() async {
    final data = await _get('/api/devices');
    if (data == null) return const [];
    return (data as List)
        .map((e) => Device.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> revokeDevice(String deviceId) async {
    await _delete('/api/devices/$deviceId');
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _patch('/api/account/password', {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> setUserStatus(String userId, String status) async {
    await _patch('/api/admin/users/$userId/status', {'status': status});
  }

  Future<Map<String, dynamic>> createResetCode(String userId) async {
    final data = await _post('/api/admin/users/$userId/reset-code', const {});
    return data as Map<String, dynamic>;
  }

  Future<List<AdminDevice>> listAllDevices() async {
    final data = await _get('/api/admin/devices');
    if (data == null) return const [];
    return (data as List)
        .map((e) => AdminDevice.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> adminRevokeDevice(String deviceId) async {
    await _delete('/api/admin/devices/$deviceId');
  }

  Future<List<InviteCode>> listInvites() async {
    final data = await _get('/api/admin/invites');
    if (data == null) return const [];
    return (data as List)
        .map((e) => InviteCode.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> revokeInvite(String inviteId) async {
    await _post('/api/admin/invites/$inviteId/revoke', const {});
  }

  Future<Map<String, dynamic>> createInvite({int maxUses = 1, int ttlHours = 168}) async {
    final data = await _post('/api/admin/invites', {
      'maxUses': maxUses,
      'ttlHours': ttlHours,
    });
    return data as Map<String, dynamic>;
  }

  Future<List<User>> listUsers() async {
    final data = await _get('/api/admin/users');
    if (data == null) return const [];
    return (data as List)
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<dynamic> _get(String path) async {
    return _request(() => _dio.get(path));
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    return _request(() => _dio.post(path, data: body));
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    return _request(() => _dio.patch(path, data: body));
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    return _request(() => _dio.put(path, data: body));
  }

  Future<dynamic> _delete(String path) async {
    return _request(() => _dio.delete(path));
  }

  Future<dynamic> _request(Future<Response<dynamic>> Function() send) async {
    try {
      final response = await send();
      final body = response.data;
      if (body is Map<String, dynamic> && body['code'] == 0) {
        return body['data'];
      }
      if (body is Map<String, dynamic>) {
        throw ApiException(
          (body['code'] as num?)?.toInt() ?? -1,
          (body['message'] as String?) ?? '请求失败',
        );
      }
      throw ApiException(-1, '响应格式不正确');
    } on DioException catch (e) {
      // Keep the diagnostic visible in `adb logcat` while the API surface is
      // still being built; user-facing errors stay short.
      // ignore: avoid_print
      print('mypet dio error: type=${e.type} uri=${e.requestOptions.uri} '
          'message=${e.message} error=${e.error}');
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        throw ApiException(
          (body['code'] as num?)?.toInt() ?? -1,
          (body['message'] as String?) ?? '请求失败',
        );
      }
      throw ApiException(-1, _networkMessage(e));
    }
  }

  String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查服务器地址和网络';
      case DioExceptionType.connectionError:
        return '无法连接服务器，请确认服务端已启动、地址正确';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      default:
        return '网络请求失败';
    }
  }
}

class LoginResult {
  final String token;
  final User user;
  final Device device;

  LoginResult({required this.token, required this.user, required this.device});
}
