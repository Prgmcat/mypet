import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounts.dart';
import '../../core/session.dart';
import '../../core/toast.dart';

/// Opens the account switcher without leaving the current page or signing out
/// first. The switch happens in place once the new credentials are accepted.
Future<void> showAccountSwitcher(BuildContext context, WidgetRef ref) async {
  final accounts = await AccountStore.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AccountSwitcherSheet(accounts: accounts),
  );
}

class _AccountSwitcherSheet extends ConsumerStatefulWidget {
  const _AccountSwitcherSheet({required this.accounts});

  final List<SavedAccount> accounts;

  @override
  ConsumerState<_AccountSwitcherSheet> createState() =>
      _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends ConsumerState<_AccountSwitcherSheet> {
  late List<SavedAccount> _accounts = widget.accounts;
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _switching;
  bool _showAdd = false;
  bool _obscure = true;

  String get _currentUsername => ref.read(sessionProvider).user?.username ?? '';

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _isCurrent(SavedAccount account) =>
      account.username.toLowerCase() == _currentUsername.toLowerCase();

  Future<void> _switchTo(String username, String password) async {
    if (_switching != null) return;
    if (username.toLowerCase() == _currentUsername.toLowerCase()) return;
    setState(() => _switching = username);
    final error = await ref
        .read(sessionProvider.notifier)
        .switchAccount(username: username, password: password);
    if (!mounted) return;
    if (error != null) {
      setState(() => _switching = null);
      showToast(context, error, error: true);
      return;
    }
    final name = ref.read(sessionProvider).user?.displayName ?? username;
    final root = Navigator.of(context, rootNavigator: true);
    final rootContext = root.context;
    Navigator.of(context).pop();
    // Settings may have been pushed; the root now shows the new account.
    root.popUntil((route) => route.isFirst);
    showToast(rootContext, '已切换到 $name');
  }

  Future<void> _submitManual() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      showToast(context, '请输入用户名和密码', error: true);
      return;
    }
    await _switchTo(username, password);
  }

  Future<void> _remove(SavedAccount account) async {
    if (_switching != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除账号'),
        content: Text('从本机移除「${account.username}」后，下次需要重新输入密码。'),
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
    final accounts = await AccountStore.load();
    if (!mounted) return;
    setState(() => _accounts = accounts);
    showToast(context, '已移除 ${account.username}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = _accounts.where((account) => !_isCurrent(account)).toList();
    SavedAccount? current;
    for (final account in _accounts) {
      if (_isCurrent(account)) {
        current = account;
        break;
      }
    }
    final currentName = ref.watch(sessionProvider).user?.displayName ?? '';
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('切换账号',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                Text('当前账号',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: Colors.black54)),
                const SizedBox(height: 8),
                _accountTile(
                  context,
                  username: _currentUsername,
                  displayName:
                      currentName.isEmpty ? _currentUsername : currentName,
                  isCurrent: true,
                  enabled: false,
                  account: current,
                  onRemove: null,
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('可切换的账号',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 8),
                  for (final account in others)
                    _accountTile(
                      context,
                      username: account.username,
                      displayName: account.displayName,
                      isCurrent: false,
                      enabled: _switching == null,
                      account: account,
                      onRemove: () => _remove(account),
                    ),
                ] else ...[
                  const SizedBox(height: 14),
                  Text('暂无其他已保存的账号。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.black45)),
                ],
                const SizedBox(height: 16),
                if (_showAdd) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('登录其他账号',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _username,
                    enabled: _switching == null,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _password,
                    enabled: _switching == null,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submitManual(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _switching == null ? _submitManual : null,
                    child: _switching == null
                        ? const Text('登录并切换')
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text('密码只保存在本机安全存储中。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.black45)),
                ] else
                  OutlinedButton.icon(
                    onPressed: _switching == null
                        ? () => setState(() => _showAdd = true)
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('使用其他账号登录'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountTile(
    BuildContext context, {
    required String username,
    required String displayName,
    required bool isCurrent,
    required bool enabled,
    required SavedAccount? account,
    required VoidCallback? onRemove,
  }) {
    final theme = Theme.of(context);
    final label = displayName.trim().isEmpty ? username : displayName;
    final busy = _switching != null && _switching == username;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isCurrent ? const Color(0xFFF3EFE8) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color:
              isCurrent ? theme.colorScheme.primary : const Color(0x1F000000),
        ),
      ),
      child: ListTile(
        enabled: enabled,
        onTap:
            enabled ? () => _switchTo(username, account?.password ?? '') : null,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFF1E4D8),
          child: Text(
            label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isCurrent
                ? const Text('当前',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                        fontWeight: FontWeight.w600))
                : onRemove != null
                    ? IconButton(
                        tooltip: '移除账号',
                        onPressed: enabled ? onRemove : null,
                        icon: const Icon(Icons.close, size: 20),
                      )
                    : null,
      ),
    );
  }
}
