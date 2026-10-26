import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'api_client.dart';
import 'cache.dart';
import 'models.dart';
import 'server_scope.dart';

/// Built-in server used when the user has not configured a self-hosted one.
/// It can also be overridden at build time with `--dart-define=SERVER_URL=...`.
const defaultServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://yangqingwen0911.iask.in',
);
const _serverKey = 'mypet_custom_server_url';

/// The device token belongs to one server. The built-in server keeps the
/// legacy key; self-hosted servers get a scope prefix.
String get _tokenKey => '${ServerScope.prefix}mypet_device_token';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.read(apiClientProvider));
});

class SessionState {
  final bool loading;
  final String serverUrl;
  final bool serverIsCustom;
  final String? token;
  final User? user;
  final String? error;
  final int? errorCode;

  const SessionState({
    required this.loading,
    required this.serverUrl,
    this.serverIsCustom = false,
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
    bool? serverIsCustom,
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
      serverIsCustom: serverIsCustom ?? this.serverIsCustom,
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
    final custom = await _loadCustomServer();
    final serverUrl = custom ?? defaultServerUrl;
    final isCustom = custom != null;
    final isolated = isCustom &&
        ServerScope.normalize(custom) !=
            ServerScope.normalize(defaultServerUrl);
    ServerScope.setFor(serverUrl, isCustom: isolated);
    final token = await _secure.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      state = SessionState(
        loading: false,
        serverUrl: serverUrl,
        serverIsCustom: isCustom,
      );
      return;
    }
    try {
      _api.configure(baseUrl: serverUrl, token: token);
      final user = await _api.me();
      state = SessionState(
        loading: false,
        serverUrl: serverUrl,
        serverIsCustom: isCustom,
        token: token,
        user: user,
      );
    } catch (_) {
      await _secure.delete(key: _tokenKey);
      state = SessionState(
        loading: false,
        serverUrl: serverUrl,
        serverIsCustom: isCustom,
      );
    }
  }

  Future<String?> _loadCustomServer() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_serverKey)?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  /// Persists a user-supplied self-hosted server address. An empty value
  /// restores the built-in default. Returns a validation error, or null.
  Future<String?> setServerUrl(String raw) async {
    if (state.isLoggedIn) return '请先退出登录再切换服务器';
    final value = raw.trim();
    String? custom;
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        return '请输入 http:// 或 https:// 开头的完整地址';
      }
      custom = value.replaceFirst(RegExp(r'/+$'), '');
    }
    final prefs = await SharedPreferences.getInstance();
    if (custom == null) {
      await prefs.remove(_serverKey);
    } else {
      await prefs.setString(_serverKey, custom);
    }
    final serverUrl = custom ?? defaultServerUrl;
    final isolated = custom != null &&
        ServerScope.normalize(custom) !=
            ServerScope.normalize(defaultServerUrl);
    ServerScope.setFor(serverUrl, isCustom: isolated);
    _api.configure(baseUrl: serverUrl);
    state = state.copyWith(
      serverUrl: serverUrl,
      serverIsCustom: custom != null,
    );
    return null;
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    // Do not flip `loading` here: the root route would swap the login page for
    // the splash screen and the failure message would never be seen. The login
    // page owns its own progress indicator.
    final serverUrl = state.serverUrl;
    state = state.copyWith(clearError: true, serverUrl: serverUrl);
    try {
      final result = await _api.login(
        baseUrl: serverUrl,
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
        serverUrl: serverUrl,
        serverIsCustom: state.serverIsCustom,
        token: result.token,
        user: result.user,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.userMessage,
        errorCode: e.code,
      );
    } catch (_) {
      state = state.copyWith(loading: false, error: '登录失败，请稍后重试');
    }
  }

  /// Switches to another account without showing the login page.
  ///
  /// The new credentials are validated first, so a typo neither logs the user
  /// out nor leaves them without a working token. Returns null on success or a
  /// localized error message.
  Future<String?> switchAccount({
    required String username,
    required String password,
  }) async {
    final previousUser = state.user;
    final previousToken = state.token;
    final serverUrl = state.serverUrl;
    LoginResult result;
    try {
      result = await _api.login(
        baseUrl: serverUrl,
        username: username,
        password: password,
        deviceName: await _deviceName(),
      );
    } on ApiException catch (e) {
      return e.userMessage;
    } catch (_) {
      return '切换失败，请检查网络后重试';
    }
    if (previousToken != null) {
      // The shared client now carries the new token, so revoke the previous
      // device through a short-lived client of its own.
      try {
        final oldApi = ApiClient()
          ..configure(baseUrl: serverUrl, token: previousToken);
        await oldApi.logout().timeout(const Duration(seconds: 3));
      } catch (_) {
        // A stale device entry is better than failing the switch.
      }
    }
    try {
      await _secure.write(key: _tokenKey, value: result.token);
    } catch (_) {
      // The in-memory session still works for this run.
    }
    await AccountStore.remember(
      username: username,
      password: password,
      displayName: result.user.displayName,
    );
    if (previousUser != null && previousUser.id != result.user.id) {
      try {
        await LocalCache.clear(previousUser.id);
      } catch (_) {
        // Cache cleanup is best effort.
      }
    }
    state = SessionState(
      loading: false,
      serverUrl: serverUrl,
      serverIsCustom: state.serverIsCustom,
      token: result.token,
      user: result.user,
    );
    return null;
  }

  Future<String?> register({
    required String inviteCode,
    required String username,
    required String password,
    required String displayName,
  }) async {
    try {
      await _api.register(
        baseUrl: state.serverUrl,
        inviteCode: inviteCode,
        username: username,
        password: password,
        displayName: displayName,
      );
      await login(username: username, password: password);
      return null;
    } on ApiException catch (e) {
      return e.userMessage;
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
    state = SessionState(
      loading: false,
      serverUrl: state.serverUrl,
      serverIsCustom: state.serverIsCustom,
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
      final data =
          await _api.createInvite(maxUses: maxUses, ttlHours: ttlHours);
      return data['code'] as String?;
    } on ApiException catch (e) {
      return 'ERR:${e.userMessage}';
    } catch (_) {
      return 'ERR:创建邀请码失败';
    }
  }

  Future<List<User>> listUsers() => _api.listUsers();
}
