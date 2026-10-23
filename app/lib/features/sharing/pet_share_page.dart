import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/models.dart';
import '../../core/session.dart';

String _formatTime(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  return DateFormat('yyyy-MM-dd HH:mm').format(date);
}

class PetSharePage extends ConsumerStatefulWidget {
  const PetSharePage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<PetSharePage> createState() => _PetSharePageState();
}

class _PetSharePageState extends ConsumerState<PetSharePage> {
  List<PetMember>? _members;
  List<ShareGrant>? _grants;
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
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.listMembers(widget.pet.id),
        api.listShareGrants(),
      ]);
      if (!mounted) return;
      setState(() {
        _members = results[0] as List<PetMember>;
        _grants = (results[1] as List<ShareGrant>)
            .where((g) => g.petId == widget.pet.id)
            .toList(growable: false);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '共享信息加载失败';
        _loading = false;
      });
    }
  }

  Future<void> _inviteMember() async {
    final username = TextEditingController();
    var role = 'viewer';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('邀请注册用户'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: username,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '对方用户名',
                  helperText: '需要精确用户名，不支持模糊搜索',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: '权限'),
                items: const [
                  DropdownMenuItem(value: 'viewer', child: Text('只读')),
                  DropdownMenuItem(value: 'co_caregiver', child: Text('共同照护')),
                ],
                onChanged: (v) => setDialogState(() => role = v ?? 'viewer'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('邀请'),
            ),
          ],
        ),
      ),
    );
    final name = username.text.trim();
    username.dispose();
    if (ok != true || name.isEmpty) return;
    try {
      await ref.read(apiClientProvider).addMember(widget.pet.id, name, role);
      if (!mounted) return;
      showToast(context, '已邀请，对方登录后即可看到共享宠物');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  Future<void> _removeMember(PetMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('移除后「${member.username}」将立即失去访问权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .removeMember(widget.pet.id, member.userId);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  Future<void> _createGrant() async {
    var role = 'viewer';
    var ttlDays = 7;
    var usePasscode = false;
    final passcode = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建访客链接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: '权限'),
                items: const [
                  DropdownMenuItem(value: 'viewer', child: Text('只读')),
                  DropdownMenuItem(value: 'co_caregiver', child: Text('共同照护')),
                ],
                onChanged: (v) => setDialogState(() => role = v ?? 'viewer'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: ttlDays,
                decoration: const InputDecoration(labelText: '有效期'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 天')),
                  DropdownMenuItem(value: 7, child: Text('7 天')),
                  DropdownMenuItem(value: 30, child: Text('30 天')),
                ],
                onChanged: (v) => setDialogState(() => ttlDays = v ?? 7),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设置 4 位数字口令'),
                value: usePasscode,
                onChanged: (v) => setDialogState(() => usePasscode = v),
              ),
              if (usePasscode)
                TextField(
                  controller: passcode,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(labelText: '口令'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('生成链接'),
            ),
          ],
        ),
      ),
    );
    final code = passcode.text.trim();
    passcode.dispose();
    if (ok != true) return;
    if (usePasscode && !RegExp(r'^[0-9]{4}$').hasMatch(code)) {
      if (!mounted) return;
      showToast(context, '口令需为 4 位数字');
      return;
    }
    try {
      final grant = await ref.read(apiClientProvider).createShareGrant(
            widget.pet.id,
            role: role,
            ttlDays: ttlDays,
            passcode: usePasscode ? code : '',
          );
      if (!mounted) return;
      final url = ref.read(apiClientProvider).shareUrl(grant.token);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('访客链接已生成'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('链接只显示这一次，请复制后发给家人。'),
                  const SizedBox(height: 12),
                  SelectableText(url, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  Text(
                    '权限：${grant.roleLabel} · 有效期至 ${_formatTime(grant.expiresAt)}'
                    '${grant.hasPasscode ? ' · 需要口令' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
                showToast(context, '链接已复制');
              },
              child: const Text('复制链接'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  Future<void> _revoke(ShareGrant grant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销访客链接'),
        content: const Text('撤销后链接立即失效，访客已完成的照护记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).revokeShareGrant(grant.id);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('共享「${widget.pet.name}」')),
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '只读：查看摘要、照护说明与提醒。\n'
                          '共同照护：额外可完成提醒、新增照护记录和上传照片。\n'
                          '所有者随时可以移除成员或撤销链接，立即生效。',
                          style: TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionHeader(
                      title: '注册用户',
                      action: TextButton.icon(
                        onPressed: _inviteMember,
                        icon: const Icon(Icons.person_add_alt, size: 18),
                        label: const Text('邀请'),
                      ),
                    ),
                    if (_members!.isEmpty)
                      const _EmptyHint('还没有邀请注册用户共同照护')
                    else
                      for (final member in _members!)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFE8F0E4),
                              child: Icon(Icons.person_outline, size: 20),
                            ),
                            title: Text(member.displayName.isEmpty
                                ? member.username
                                : member.displayName),
                            subtitle: Text(
                              '${member.username} · ${member.roleLabel} · 加入于 ${_formatTime(member.joinedAt).split(' ').first}',
                            ),
                            trailing: IconButton(
                              tooltip: '移除',
                              icon: const Icon(Icons.person_remove_outlined,
                                  size: 20),
                              onPressed: () => _removeMember(member),
                            ),
                          ),
                        ),
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: '访客链接',
                      action: TextButton.icon(
                        onPressed: _createGrant,
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('创建'),
                      ),
                    ),
                    if (_grants!.isEmpty)
                      const _EmptyHint('还没有访客链接')
                    else
                      for (final grant in _grants!)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              grant.status == 'active'
                                  ? Icons.link
                                  : Icons.link_off,
                              color: grant.status == 'active'
                                  ? Colors.green
                                  : Colors.black26,
                            ),
                            title: Text(
                              '${grant.roleLabel} · ${grant.statusLabel}',
                            ),
                            subtitle: Text(
                              '有效期至 ${_formatTime(grant.expiresAt)}'
                              '${grant.hasPasscode ? ' · 需要口令' : ''}',
                            ),
                            trailing: grant.status == 'active'
                                ? TextButton(
                                    onPressed: () => _revoke(grant),
                                    child: const Text('撤销'),
                                  )
                                : null,
                          ),
                        ),
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        action,
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text,
          style: const TextStyle(color: Colors.black45, fontSize: 13)),
    );
  }
}
