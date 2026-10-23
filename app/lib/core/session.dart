import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'accounts.dart';
import 'api_client.dart';
import 'cache.dart';
import 'models.dart';

/// The app is intentionally single-server: the domain is built in and the
/// interface never asks the user to configure it.
const defaultServerUrl = 'http://yangqingwen0911.iask.in';
const _tokenKey = 'mypet_device_token';

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
  final int? errorCode;

  const SessionState({
    required this.loading,
    required this.serverUrl,
    this.token,
    this.user,
    this.error,
    this.errorCode,
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
    int? errorCode,
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
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
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
    const serverUrl = defaultServerUrl;
    final token = await _secure.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      state = const SessionState(
        loading: false,
        serverUrl: defaultServerUrl,
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
      state = const SessionState(
        loading: false,
        serverUrl: defaultServerUrl,
      );
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(
      loading: true,
      clearError: true,
      serverUrl: defaultServerUrl,
    );
    try {
      final result = await _api.login(
        baseUrl: defaultServerUrl,
        username: username,
        password: password,
        deviceName: await _deviceName(),
      );
      await _secure.write(key: _tokenKey, value: result.token);
      await AccountStore.remember(
        username: username,
        password: password,
        displayName: result.user.displayName,
      );
      state = SessionState(
        loading: false,
        serverUrl: defaultServerUrl,
        token: result.token,
        user: result.user,
      );
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message, errorCode: e.code);
    } catch (_) {
      state = state.copyWith(loading: false, error: '登录失败，请稍后重试');
    }
  }

  Future<String?> register({
    required String inviteCode,
    required String username,
    required String password,
    required String displayName,
  }) async {
    try {
      await _api.register(
        baseUrl: defaultServerUrl,
        inviteCode: inviteCode,
        username: username,
        password: password,
        displayName: displayName,
      );
      await login(username: username, password: password);
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
      // Never let a slow tunnel or unreachable server block local logout.
      await _api.logout().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Local logout should still succeed when the server is unreachable.
    }
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {
      // A broken Keystore entry must not keep the user signed in.
    }
    try {
      if (userId != null) await LocalCache.clear(userId);
    } catch (_) {
      // Cache cleanup is best effort.
    }
    state = const SessionState(
      loading: false,
      serverUrl: defaultServerUrl,
    );
  }

  Future<String> _deviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final name = [info.manufacturer.trim(), info.model.trim()]
            .where((part) => part.isNotEmpty)
            .join(' ');
        if (name.isNotEmpty) {
          return name.length > 60 ? name.substring(0, 60) : name;
        }
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final name = info.utsname.machine.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {
      // Fall back to a generic label when the platform channel is unavailable.
    }
    return 'Android';
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
