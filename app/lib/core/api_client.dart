import 'package:dio/dio.dart';

import 'models.dart';

class ApiException implements Exception {
  final int code;
  final String message;

  ApiException(this.code, this.message);

  /// Chinese text safe to show in the UI. Server messages are English and
  /// largely internal, so anything unrecognized falls back to a neutral one.
  String get userMessage => localizeApiMessage(code, message);

  @override
  String toString() => userMessage;
}

const _apiMessages = <String, String>{
  'invalid json': '请求格式不正确',
  'action must be complete, snooze or skip': '不支持的操作',
  'advanceOffsets must be unique values between 0 and 365':
      '提前提醒天数需为 0–365 之间的不同数值',
  'advanceOffsets must contain 1 to 6 values': '提前提醒天数需要 1–6 个',
  'intervalDays must be between 1 and 3650': '提醒周期需在 1–3650 天之间',
  'invalid date or weight': '日期或体重格式不正确',
  'invalid invite code, username or password': '邀请码、用户名或密码格式不正确',
  'new password does not meet requirements': '新密码不符合要求',
  'passcode must be 4 digits': '共享口令需为 4 位数字',
  'role must be viewer or co_caregiver': '角色不正确',
  'status must be active or disabled': '用户状态不正确',
  'status must be pending, done, skipped or all': '提醒状态不正确',
  'ttlDays must be between 1 and 30': '有效期需在 1–30 天之间',
  'username is required': '请输入用户名',
  'username or password does not meet requirements': '用户名或密码不符合要求',
  'file is too large or invalid multipart form': '文件过大或上传格式不正确',
  'file field is required': '请选择文件',
  'could not read file': '文件读取失败',
  'avatar must be at most 5 MB': '头像不能超过 5 MB',
  'file exceeds 10 MB': '文件不能超过 10 MB',
  'file exceeds 20 MB': '文件不能超过 20 MB',
  'only JPEG, PNG or WebP are allowed': '仅支持 JPEG、PNG 或 WebP 图片',
  'only JPEG, PNG, WebP or PDF are allowed': '仅支持 JPEG、PNG、WebP 或 PDF',
  'record does not belong to this pet': '记录不属于这只宠物',
  'missing bearer token': '登录已失效，请重新登录',
  'invalid or revoked token': '登录已失效，请重新登录',
  'admin only': '需要管理员权限',
  'setup is only allowed from localhost': '仅允许本机初始化',
  'invalid username or password': '用户名或密码错误',
  'invalid passcode': '共享口令错误',
  'passcode required': '请输入共享口令',
  'already initialized': '服务已初始化',
  'old password is incorrect': '原密码不正确',
  'avatar not found': '头像不存在',
  'avatar not set': '还没有设置头像',
  'not found': '记录不存在或已被删除',
  'username already exists': '用户名已存在',
  'invite code is invalid, expired or used': '邀请码无效、已过期或已使用',
  'reset code is invalid or expired': '重置码无效或已过期',
  'co-caregiver can only edit records they created': '只能修改自己创建的记录',
  'forbidden': '没有权限执行此操作',
  'no permission to delete this weight record': '没有权限删除这条体重记录',
  'no permission to write records': '没有权限写入记录',
  'only the owner can change the avatar': '只有主人可以修改头像',
  'only the owner can edit this pet': '只有主人可以编辑宠物',
  'only the owner can manage sharing': '只有主人可以管理共享',
  'only the owner can restore records': '只有主人可以恢复记录',
  'viewer cannot complete reminders': '访客不能完成提醒',
  'viewer cannot create records': '访客不能创建记录',
  'viewer cannot download medical attachments': '访客不能下载病历附件',
  'viewer cannot edit records': '访客不能编辑记录',
  'viewer cannot read health records': '访客不能查看健康记录',
  'viewer cannot upload photos': '访客不能上传照片',
  'user not found': '用户不存在',
  'cannot invite the pet owner': '不能邀请宠物主人',
  'share link is invalid, expired or revoked': '共享链接无效、已过期或被撤销',
  'too many attempts, try again later': '操作过于频繁，请稍后再试',
  'too many failed attempts, try again later': '登录失败次数过多，请稍后再试',
  'internal server error': '服务器开小差了，请稍后重试',
  'database error': '数据读写失败，请稍后重试',
  'password hashing failed': '密码处理失败，请稍后重试',
  'token generation failed': '登录凭证生成失败，请稍后重试',
  'device creation failed': '设备登记失败，请稍后重试',
};

String localizeApiMessage(int code, String message) {
  final direct = _apiMessages[message];
  if (direct != null) return direct;
  switch (code) {
    case 10001:
      return '请求格式不正确';
    case 20001:
    case 20002:
      return '登录已失效，请重新登录';
    case 20003:
      return '需要管理员权限';
    case 20005:
      return '用户名或密码错误';
    case 30003:
      return '记录不存在或已被删除';
    case 30004:
      return '用户名已存在';
    case 30005:
      return '邀请码无效、已过期或已使用';
    case 30007:
      return '没有权限执行此操作';
    case 30008:
      return '用户不存在';
    case 40001:
    case 40002:
      return '操作过于频繁，请稍后再试';
    default:
      return '操作失败，请稍后重试';
  }
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

  String avatarUrl(String petId, int version) =>
      '$_baseUrl/api/pets/$petId/avatar?v=$version';

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
    return User.fromJson(
        (data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    // SessionController clears local state; a later login reconfigures headers.
    await _post('/api/auth/logout', const {});
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
    final data = await _get(
        '/api/pets/$petId/records${type == null || type.isEmpty ? '' : '?type=$type'}');
    if (data == null) return const [];
    return (data as List)
        .map((e) => HealthRecord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<HealthRecord> createRecord(
      String petId, Map<String, dynamic> payload) async {
    final data = await _post('/api/pets/$petId/records', payload);
    return HealthRecord.fromJson(data as Map<String, dynamic>);
  }

  Future<HealthRecord> updateRecord(
      String recordId, Map<String, dynamic> payload) async {
    final data = await _patch('/api/records/$recordId', payload);
    return HealthRecord.fromJson(
        (data as Map<String, dynamic>)['record'] as Map<String, dynamic>);
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

  Future<WeightRecord> createWeight(
      String petId, Map<String, dynamic> payload) async {
    final data = await _post('/api/pets/$petId/weights', payload);
    return WeightRecord.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteWeight(String weightId) async {
    await _delete('/api/weights/$weightId');
  }

  Future<Pet> uploadPetAvatar(String petId, String filePath) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final data = await _request(
      () => _dio.post('/api/pets/$petId/avatar', data: form),
    );
    return Pet.fromJson(data as Map<String, dynamic>);
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
    final data = await _request(
        () => _dio.post('/api/pets/$petId/attachments', data: form));
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

  Future<List<Appointment>> listAppointments(
      {String status = 'pending'}) async {
    final data = await _get('/api/appointments?status=$status');
    if (data == null) return const [];
    return (data as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Appointment>> listPetAppointments(
    String petId, {
    String status = 'pending',
  }) async {
    final data = await _get('/api/pets/$petId/appointments?status=$status');
    if (data == null) return const [];
    return (data as List)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Appointment> createAppointment(
    String petId,
    Map<String, dynamic> payload,
  ) async {
    final data = await _post('/api/pets/$petId/appointments', payload);
    return Appointment.fromJson(data as Map<String, dynamic>);
  }

  Future<Appointment> updateAppointment(
    String appointmentId,
    Map<String, dynamic> payload,
  ) async {
    final data = await _patch('/api/appointments/$appointmentId', payload);
    return Appointment.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteAppointment(String appointmentId) async {
    await _delete('/api/appointments/$appointmentId');
  }

  Future<Appointment> completeAppointment(String appointmentId) async {
    final data =
        await _post('/api/appointments/$appointmentId/complete', const {});
    return Appointment.fromJson(data as Map<String, dynamic>);
  }

  Future<Appointment> skipAppointment(String appointmentId) async {
    final data = await _post('/api/appointments/$appointmentId/skip', const {});
    return Appointment.fromJson(data as Map<String, dynamic>);
  }

  Future<Appointment> snoozeAppointment(
    String appointmentId, {
    int hours = 24,
  }) async {
    final data = await _post(
      '/api/appointments/$appointmentId/snooze',
      {'hours': hours},
    );
    return Appointment.fromJson(data as Map<String, dynamic>);
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

  Future<Map<String, dynamic>> createInvite(
      {int maxUses = 1, int ttlHours = 168}) async {
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
    return _request(
      () => _dio.patch(path, data: body),
      overrideMethod: 'PATCH',
      path: path,
      data: body,
    );
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    return _request(
      () => _dio.put(path, data: body),
      overrideMethod: 'PUT',
      path: path,
      data: body,
    );
  }

  Future<dynamic> _delete(String path) async {
    return _request(
      () => _dio.delete(path),
      overrideMethod: 'DELETE',
      path: path,
    );
  }

  Future<dynamic> _request(
    Future<Response<dynamic>> Function() send, {
    String? overrideMethod,
    String? path,
    Map<String, dynamic>? data,
  }) async {
    Response<dynamic> response;
    try {
      response = await send();
    } on DioException catch (e) {
      // Some public HTTP tunnels (e.g. Oray/iask.in) only forward GET/POST and
      // abort PATCH/PUT/DELETE. Retry those as POST with an override header.
      if (overrideMethod != null && path != null && _isConnectionFailure(e)) {
        try {
          response = await _dio.post(
            path,
            data: data,
            options: Options(headers: {
              'X-HTTP-Method-Override': overrideMethod,
            }),
          );
        } on DioException catch (retryError) {
          throw _toApiException(retryError);
        }
      } else {
        throw _toApiException(e);
      }
    }
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
  }

  bool _isConnectionFailure(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        (e.type == DioExceptionType.unknown && e.response == null);
  }

  ApiException _toApiException(DioException e) {
    // Keep the diagnostic visible in `adb logcat` while the API surface is
    // still being built; user-facing errors stay short.
    // ignore: avoid_print
    print('mypet dio error: type=${e.type} uri=${e.requestOptions.uri} '
        'message=${e.message} error=${e.error}');
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      return ApiException(
        (body['code'] as num?)?.toInt() ?? -1,
        (body['message'] as String?) ?? '请求失败',
      );
    }
    return ApiException(-1, _networkMessage(e));
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
