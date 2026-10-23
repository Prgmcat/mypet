import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'cache.dart';
import 'models.dart';

const defaultServerUrl = 'http://10.0.2.2:8787';
const _tokenKey = 'mypet_device_token';
const _serverKey = 'mypet_server_url';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.read(apiClientProvider));
});

class SessionState {
  final bool loading;
  final String serverUrl;
  final String? token;
  final User? user;
  final String? error;

  const SessionState({
    required this.loading,
    required this.serverUrl,
    this.token,
    this.user,
    this.error,
  });

  factory SessionState.initial() => const SessionState(
        loading: true,
        serverUrl: defaultServerUrl,
      );

  bool get isLoggedIn => token != null && user != null;

  SessionState copyWith({
    bool? loading,
    String? serverUrl,
    String? token,
    User? user,
    String? error,
    bool clearToken = false,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return SessionState(
      loading: loading ?? this.loading,
      serverUrl: serverUrl ?? this.serverUrl,
      token: clearToken ? null : (token ?? this.token),
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._api) : super(SessionState.initial()) {
    _restore();
  }

  final ApiClient _api;
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_serverKey) ?? defaultServerUrl;
    final token = await _secure.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      state = SessionState(
        loading: false,
        serverUrl: serverUrl,
      );
      return;
    }
    try {
      _api.configure(baseUrl: serverUrl, token: token);
      final user = await _api.me();
      state = SessionState(
        loading: false,
        serverUrl: serverUrl,
        token: token,
        user: user,
      );
    } catch (_) {
      await _secure.delete(key: _tokenKey);
      state = SessionState(
        loading: false,
        serverUrl: serverUrl,
      );
    }
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    state = state.copyWith(loading: true, clearError: true, serverUrl: serverUrl);
    try {
      final result = await _api.login(
        baseUrl: serverUrl,
        username: username,
        password: password,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverKey, ApiClient.normalizeBaseUrl(serverUrl));
      await _secure.write(key: _tokenKey, value: result.token);
      state = SessionState(
        loading: false,
        serverUrl: ApiClient.normalizeBaseUrl(serverUrl),
        token: result.token,
        user: result.user,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(loading: false, error: '登录失败，请稍后重试');
    }
  }

  Future<String?> register({
    required String serverUrl,
    required String inviteCode,
    required String username,
    required String password,
    required String displayName,
  }) async {
    try {
      await _api.register(
        baseUrl: serverUrl,
        inviteCode: inviteCode,
        username: username,
        password: password,
        displayName: displayName,
      );
      await login(serverUrl: serverUrl, username: username, password: password);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return '注册失败，请稍后重试';
    }
  }

  Future<void> logout() async {
    final userId = state.user?.id;
    try {
      await _api.logout();
    } catch (_) {
      // Local logout should still succeed when the server is unreachable.
    }
    await _secure.delete(key: _tokenKey);
    if (userId != null) await LocalCache.clear(userId);
    state = SessionState(
      loading: false,
      serverUrl: state.serverUrl,
    );
  }

  Future<String?> createInvite({int maxUses = 1, int ttlHours = 168}) async {
    try {
      final data = await _api.createInvite(maxUses: maxUses, ttlHours: ttlHours);
      return data['code'] as String?;
    } on ApiException catch (e) {
      return 'ERR:${e.message}';
    } catch (_) {
      return 'ERR:创建邀请码失败';
    }
  }

  Future<List<User>> listUsers() => _api.listUsers();
}
