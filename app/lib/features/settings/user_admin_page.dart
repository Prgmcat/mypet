import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';

class UserAdminPage extends ConsumerStatefulWidget {
  const UserAdminPage({super.key});

  @override
  ConsumerState<UserAdminPage> createState() => _UserAdminPageState();
}

class _UserAdminPageState extends ConsumerState<UserAdminPage> {
  List<User>? _users;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ref.read(apiClientProvider).listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _toggleStatus(User user) async {
    final next = user.status == 'active' ? 'disabled' : 'active';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(next == 'disabled' ? '禁用用户' : '启用用户'),
        content: Text(
          next == 'disabled'
              ? '禁用后「${user.username}」的所有设备会立即下线，无法登录。'
              : '启用后「${user.username}」可以重新登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(next == 'disabled' ? '禁用' : '启用'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).setUserStatus(user.id, next);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resetCode(User user) async {
    try {
      final data = await ref.read(apiClientProvider).createResetCode(user.id);
      if (!mounted) return;
      final code = (data['code'] as String?) ?? '';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${user.username} 的密码重置码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('重置码 15 分钟内有效且只能使用一次。请通过可信渠道交给用户。'),
              const SizedBox(height: 16),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制重置码')),
                );
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _createInvite() async {
    try {
      final data = await ref.read(apiClientProvider).createInvite();
      if (!mounted) return;
      final code = (data['code'] as String?) ?? '';
      final expires = (data['expiresAt'] as String?) ?? '';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('新邀请码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('默认 7 天有效、可使用 1 次。'),
              const SizedBox(height: 12),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              if (expires.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('有效期至 $expires',
                    style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制邀请码')),
                );
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showInvites() async {
    try {
      final invites = await ref.read(apiClientProvider).listInvites();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('邀请码'),
            content: SizedBox(
              width: 380,
              child: invites.isEmpty
                  ? const Text('还没有创建过邀请码')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: invites.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            invite.status == 'active'
                                ? Icons.vpn_key_outlined
                                : Icons.vpn_key_off_outlined,
                            color: invite.status == 'active'
                                ? Colors.green
                                : Colors.black26,
                          ),
                          title: Text(
                            '${invite.statusLabel} · 已用 ${invite.usedCount}/${invite.maxUses}',
                          ),
                          subtitle: Text(
                            '有效期至 ${invite.expiresAt}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: invite.status == 'active'
                              ? TextButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(apiClientProvider)
                                          .revokeInvite(invite.id);
                                      invites[index] = InviteCode(
                                        id: invite.id,
                                        maxUses: invite.maxUses,
                                        usedCount: invite.usedCount,
                                        expiresAt: invite.expiresAt,
                                        status: 'revoked',
                                        createdAt: invite.createdAt,
                                      );
                                      setDialogState(() {});
                                    } on ApiException catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(e.message)));
                                    }
                                  },
                                  child: const Text('作废'),
                                )
                              : null,
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selfId = ref.watch(sessionProvider).user?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户管理'),
        actions: [
          IconButton(
            onPressed: _showInvites,
            icon: const Icon(Icons.list_alt),
            tooltip: '邀请码列表',
          ),
          IconButton(
            onPressed: _createInvite,
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: '创建邀请码',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                          onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: _users!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final user = _users![index];
                      final active = user.status == 'active';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                user.isAdmin
                                    ? const Color(0xFFE8F0E4)
                                    : const Color(0xFFF1E4D8),
                            child: Icon(
                              user.isAdmin
                                  ? Icons.shield_outlined
                                  : Icons.person_outline,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.displayName.isEmpty
                                      ? user.username
                                      : user.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (user.isAdmin)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text('管理员',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.black45)),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${user.username} · ${active ? '正常' : '已禁用'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (user.id != selfId)
                                IconButton(
                                  tooltip: '重置密码',
                                  icon: const Icon(Icons.key_outlined, size: 20),
                                  onPressed: () => _resetCode(user),
                                ),
                              if (user.id != selfId && !user.isAdmin)
                                Switch(
                                  value: active,
                                  onChanged: (_) => _toggleStatus(user),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
