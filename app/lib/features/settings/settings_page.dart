import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/format_time.dart';
import '../../core/models.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import '../ai/ai_settings_page.dart';
import '../auth/account_switcher.dart';
import 'admin_devices_page.dart';
import 'invite_page.dart';
import 'user_admin_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? _serverVersion;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() => _checking = true);
    try {
      final health = await ref.read(apiClientProvider).health();
      if (!mounted) return;
      setState(() {
        _serverVersion = (health['version'] as String?) ?? '未知';
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverVersion = null;
        _checking = false;
      });
    }
  }

  Future<void> _showDevices() async {
    List<Device> devices;
    try {
      devices = await ref.read(apiClientProvider).listDevices();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('设备管理'),
          content: SizedBox(
            width: 380,
            child: devices.isEmpty
                ? const Text('还没有绑定设备')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final d = devices[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.smartphone_outlined),
                        title: Text(d.name.isEmpty ? 'Android' : d.name),
                        subtitle: Text((d.lastSeenAt ?? '').isEmpty
                            ? '尚未上报在线时间'
                            : '最后在线 ${formatLocalTime(d.lastSeenAt!)}'),
                        trailing: IconButton(
                          tooltip: '吊销',
                          icon: const Icon(Icons.logout, size: 20),
                          onPressed: () async {
                            final ok = await _confirm(
                              context,
                              '吊销设备',
                              '吊销后该设备需要重新登录，确定继续吗？',
                            );
                            if (!ok) return;
                            try {
                              await ref
                                  .read(apiClientProvider)
                                  .revokeDevice(d.id);
                              if (!context.mounted) return;
                              // Drop the row right away instead of closing.
                              setDialogState(() {
                                devices = devices
                                    .where((item) => item.id != d.id)
                                    .toList(growable: false);
                              });
                              showToast(context, '设备已吊销');
                            } on ApiException catch (e) {
                              if (!context.mounted) return;
                              showToast(context, e.userMessage, error: true);
                            }
                          },
                        ),
                      );
                    },
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

  Future<void> _changePassword() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改密码'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: oldController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
                validator: (v) => (v == null || v.isEmpty) ? '请输入当前密码' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码',
                  helperText: '8–32 位，需包含字母和数字',
                ),
                validator: (v) {
                  final value = v ?? '';
                  if (value.length < 8 || value.length > 32) {
                    return '密码长度需为 8–32 位';
                  }
                  final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
                  final hasDigit = RegExp(r'[0-9]').hasMatch(value);
                  if (!hasLetter || !hasDigit) return '需同时包含字母和数字';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认新密码'),
                validator: (v) => v != newController.text ? '两次输入的密码不一致' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .changePassword(oldController.text, newController.text);
      if (!mounted) return;
      showToast(context, '密码已修改，其他设备已下线');
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    } finally {
      oldController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _logout() async {
    final ok = await _confirm(
      context,
      '退出登录',
      '退出后会清除本机设备凭证，服务器数据不受影响。',
    );
    if (!ok || !mounted) return;
    await _signOut();
  }

  Future<void> _switchAccount() => showAccountSwitcher(context, ref);

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    try {
      await NotificationService.cancelAll();
    } catch (_) {
      // Notification cleanup must never block logout.
    }
    if (!mounted) return;
    await ref.read(sessionProvider.notifier).logout();
    // The stable root route now shows LoginPage; leave the pushed Settings.
    navigator.popUntil((route) => route.isFirst);
  }

  void _showDataInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据与备份'),
        content: const SingleChildScrollView(
          child: Text(
            '所有宠物与记录都保存在你自托管的服务器上，App 只保留少量只读缓存。\n\n'
            '备份在服务器本机执行：\n'
            'mypet backup -data ./data -out ./backup\n\n'
            '备份包含 SQLite 数据库与附件目录。恢复前会先备份当前数据；'
            '请把备份文件保存在安全位置，建议加密。\n\n'
            'AI 服务的 API Key 只保存在本机安全存储中，不会上传服务端。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于喵了个咪'),
        content: const SingleChildScrollView(
          child: Text(
            '版本 1.0.0\n\n'
            '数据自持的宠物档案 App：宠物档案、健康记录、拍照 OCR、AI 助手、'
            '本地提醒与共享协作。\n\n'
            '隐私说明：\n'
            '· 数据只保存在你自己的服务器上；\n'
            '· 管理员默认不能查看用户的宠物与记录；\n'
            '· 相册/相机仅用于记录与 OCR，麦克风仅用于语音输入；\n'
            '· 访客链接只展示照护必需信息，可随时撤销。\n\n'
            'AI/医疗免责声明：\n'
            'AI 生成内容仅供参考，不能替代兽医面诊；'
            '不提供诊断、处方或具体剂量。出现紧急症状请立即就医。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('服务器'),
                  subtitle: const Text('连接状态与版本'),
                  trailing: Text(
                    _checking
                        ? '检查中…'
                        : _serverVersion == null
                            ? '离线'
                            : '在线 · v$_serverVersion',
                    style: TextStyle(
                      color: _serverVersion == null
                          ? Colors.redAccent
                          : Colors.green,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user?.displayName.isEmpty == false
                      ? user!.displayName
                      : (user?.username ?? '未登录')),
                  subtitle: Text(
                    '${user?.username ?? ''} · ${user?.isAdmin == true ? '管理员' : '普通用户'}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('修改密码'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePassword,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('设备管理'),
                  subtitle: const Text('查看并吊销已登录设备'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showDevices,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.switch_account_outlined),
                  title: const Text('切换账号'),
                  subtitle: const Text('直接切换到已保存的其他账号'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _switchAccount,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 服务设置'),
                  subtitle: const Text('服务商、Base URL、模型与 API Key'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AiSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (user?.isAdmin == true)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('用户管理'),
                    subtitle: const Text('禁用/启用用户、生成密码重置码'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UserAdminPage()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.confirmation_number_outlined),
                    title: const Text('邀请码'),
                    subtitle: const Text('生成邀请码，邀请家人或朋友加入'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InvitePage()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.devices_other_outlined),
                    title: const Text('全部设备'),
                    subtitle: const Text('查看所有用户设备并吊销'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AdminDevicesPage()),
                    ),
                  ),
                ],
              ),
            ),
          if (user?.isAdmin == true) const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('数据与备份'),
                  subtitle: const Text('备份在服务器本机执行'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showDataInfo,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于与隐私'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAbout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return ok == true;
}
