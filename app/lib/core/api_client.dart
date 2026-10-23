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
