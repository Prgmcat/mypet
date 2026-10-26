import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounts.dart';
import '../../core/session.dart';
import '../../core/toast.dart';
import 'register_page.dart';

const _manageAccountsValue = '__manage_accounts__';

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
  bool _matched = false;
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

  SavedAccount? _findAccount(String username) {
    final key = username.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final account in _accounts) {
      if (account.username.toLowerCase() == key) return account;
    }
    return null;
  }

  void _applyAccount(SavedAccount account) {
    _username.text = account.username;
    _password.text = account.password;
    setState(() => _matched = true);
    FocusScope.of(context).unfocus();
  }

  /// Typing a username that matches a saved account fills its password; any
  /// other input leaves the password field untouched for manual entry.
  void _onUsernameChanged(String value) {
    final account = _findAccount(value);
    if (account == null) {
      if (_matched) setState(() => _matched = false);
      return;
    }
    _password.text = account.password;
    setState(() => _matched = true);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final username = _username.text.trim();
    setState(() => _loading = true);
    await ref.read(sessionProvider.notifier).login(
          username: username,
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    final session = ref.read(sessionProvider);
    final error = session.error;
    if (error == null) return;
    // A saved password that no longer works should not be retried automatically.
    if (session.errorCode == 20005 && _findAccount(username) != null) {
      await AccountStore.remove(username);
      await _loadAccounts();
      if (!mounted) return;
      showToast(context, '账号密码已变更，请手动输入密码', error: true);
      return;
    }
    showToast(context, error, error: true);
  }

  Future<void> _manageAccounts() async {
    if (_accounts.isEmpty) {
      showToast(context, '还没有保存的账号');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('已保存的账号'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final account in _accounts)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFF1E4D8),
                      child: Text(
                        _initialOf(account),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      account.displayName.trim().isEmpty
                          ? account.username
                          : account.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('@${account.username}'),
                    trailing: IconButton(
                      tooltip: '移除账号',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        await AccountStore.remove(account.username);
                        final accounts = await AccountStore.load();
                        if (!mounted) return;
                        setState(() => _accounts = accounts);
                        if (dialogContext.mounted) {
                          setDialogState(() {});
                        }
                        showToast(context, '已移除 ${account.username}');
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editServer() async {
    final state = ref.read(sessionProvider);
    final controller = TextEditingController(
      text: state.serverIsCustom ? state.serverUrl : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自建服务器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '填写独立部署的服务器地址；留空则使用默认服务器。',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.10:8787',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final error = await ref.read(sessionProvider.notifier).setServerUrl(result);
    if (!mounted) return;
    if (error != null) {
      showToast(context, error, error: true);
      return;
    }
    showToast(context, result.trim().isEmpty ? '已恢复默认服务器' : '服务器地址已保存');
  }

  String _initialOf(SavedAccount account) {
    final label = account.displayName.trim().isEmpty
        ? account.username
        : account.displayName;
    return label.isEmpty ? '?' : label.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
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
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      onChanged: _onUsernameChanged,
                      decoration: InputDecoration(
                        labelText: '用户名',
                        prefixIcon: const Icon(Icons.person_outline),
                        suffixIcon: _accounts.isEmpty
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: '选择已保存的账号',
                                enabled: !_loading,
                                icon: const Icon(Icons.arrow_drop_down),
                                onSelected: (value) {
                                  if (value == _manageAccountsValue) {
                                    _manageAccounts();
                                    return;
                                  }
                                  final account = _findAccount(value);
                                  if (account != null) _applyAccount(account);
                                },
                                itemBuilder: (context) => [
                                  for (final account in _accounts)
                                    PopupMenuItem<String>(
                                      value: account.username,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor:
                                                const Color(0xFFF1E4D8),
                                            child: Text(
                                              _initialOf(account),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    theme.colorScheme.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  account.displayName
                                                          .trim()
                                                          .isEmpty
                                                      ? account.username
                                                      : account.displayName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '@${account.username}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black45,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem<String>(
                                    value: _manageAccountsValue,
                                    child: Text('管理已保存的账号'),
                                  ),
                                ],
                              ),
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
                        helperText: _matched ? '已自动填入保存的密码' : null,
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
                    TextButton.icon(
                      onPressed: _loading ? null : _editServer,
                      icon: const Icon(Icons.dns_outlined, size: 16),
                      label: Text(
                        session.serverIsCustom
                            ? '自建服务器：${Uri.tryParse(session.serverUrl)?.authority ?? session.serverUrl}'
                            : '使用自建服务器',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
