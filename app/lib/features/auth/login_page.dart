import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounts.dart';
import '../../core/session.dart';
import '../../core/toast.dart';
import 'register_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  List<SavedAccount> _accounts = const [];
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await AccountStore.load();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await ref.read(sessionProvider.notifier).login(
          username: _username.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    final error = ref.read(sessionProvider).error;
    if (error != null) {
      showToast(context, error, error: true);
    }
  }

  /// One-tap sign-in with a locally remembered account.
  Future<void> _loginWith(SavedAccount account) async {
    if (_loading) return;
    _username.text = account.username;
    _password.text = account.password;
    setState(() => _loading = true);
    await ref.read(sessionProvider.notifier).login(
          username: account.username,
          password: account.password,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    final session = ref.read(sessionProvider);
    final error = session.error;
    if (error == null) return;
    // The stored password no longer works; drop it so the next tap cannot
    // fail the same way. Any other error (network, server) keeps it.
    if (session.errorCode == 20005) {
      await AccountStore.remove(account.username);
      await _loadAccounts();
      if (!mounted) return;
      showToast(context, '账号密码已变更，请手动输入密码登录', error: true);
      return;
    }
    showToast(context, error, error: true);
  }

  Future<void> _removeAccount(SavedAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除账号'),
        content: Text('从本机移除「${account.username}」后，下次需要手动输入密码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AccountStore.remove(account.username);
    await _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('🐾',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 12),
                    Text('喵了个咪',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('记录健康与成长，陪伴毛孩子每一天',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.black54)),
                    const SizedBox(height: 28),
                    if (_accounts.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('已保存的账号',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: Colors.black54)),
                      ),
                      const SizedBox(height: 8),
                      for (final account in _accounts)
                        _SavedAccountTile(
                          account: account,
                          enabled: !_loading,
                          onTap: () => _loginWith(account),
                          onRemove: () => _removeAccount(account),
                        ),
                      const SizedBox(height: 4),
                      Text('点按账号即可登录；密码只保存在本机安全存储。',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.black45)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('使用其他账号',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.black45)),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterPage(),
                                ),
                              ),
                      child: const Text('有邀请码？注册新账号'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedAccountTile extends StatelessWidget {
  const _SavedAccountTile({
    required this.account,
    required this.enabled,
    required this.onTap,
    required this.onRemove,
  });

  final SavedAccount account;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = account.displayName.trim().isEmpty
        ? account.username
        : account.displayName;
    final initial = label.isEmpty ? '?' : label.substring(0, 1).toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x1F000000)),
      ),
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFF1E4D8),
          child: Text(
            initial,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '@${account.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: '移除账号',
          onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.close, size: 20),
        ),
      ),
    );
  }
}
