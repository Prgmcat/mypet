import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format_time.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/toast.dart';

class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key});

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  List<InviteCode>? _invites;
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
      final invites = await ref.read(apiClientProvider).listInvites();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) {
        var maxUses = 1;
        var days = 7;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('生成邀请码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('可邀请人数'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in [1, 3, 5, 10])
                      ChoiceChip(
                        label: Text('$value 人'),
                        selected: maxUses == value,
                        onSelected: (_) =>
                            setDialogState(() => maxUses = value),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('有效期'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in [1, 7, 30])
                      ChoiceChip(
                        label: Text('$value 天'),
                        selected: days == value,
                        onSelected: (_) => setDialogState(() => days = value),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (maxUses, days)),
                child: const Text('生成'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final (maxUses, days) = result;
    try {
      final data = await ref.read(apiClientProvider).createInvite(
            maxUses: maxUses,
            ttlHours: days * 24,
          );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await _showCode(
        (data['code'] as String?) ?? '',
        (data['expiresAt'] as String?) ?? '',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  Future<void> _showCode(String code, String expiresAt) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新邀请码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请现在复制并发送给需要加入的家人或朋友，关闭后无法再次查看。'),
            const SizedBox(height: 14),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            if (expiresAt.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '有效期至 ${formatLocalTime(expiresAt)}',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              showToast(this.context, '已复制邀请码');
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(InviteCode invite) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('作废邀请码'),
        content: const Text('作废后该邀请码不能再用于注册，已注册的账号不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('作废'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).revokeInvite(invite.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showToast(context, '邀请码已作废');
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀请码'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '生成邀请码',
            onPressed: _create,
            icon: const Icon(Icons.add),
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7EFE6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          '邀请码用于新账号注册。生成后请立即复制分享；'
                          '列表里只保留使用情况，无法再次查看完整邀请码。',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_invites == null || _invites!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Column(
                            children: [
                              Icon(Icons.vpn_key_outlined,
                                  size: 40, color: Colors.black26),
                              SizedBox(height: 12),
                              Text('还没有生成过邀请码',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54)),
                            ],
                          ),
                        )
                      else
                        for (final invite in _invites!)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
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
                                '有效期至 ${formatLocalTime(invite.expiresAt)}'
                                '${invite.createdAt.isEmpty ? '' : ' · 创建于 ${formatLocalTime(invite.createdAt)}'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: invite.status == 'active'
                                  ? TextButton(
                                      onPressed: () => _revoke(invite),
                                      child: const Text('作废'),
                                    )
                                  : null,
                            ),
                          ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('生成邀请码'),
      ),
    );
  }
}
