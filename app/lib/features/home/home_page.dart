import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/cache.dart';
import '../../core/models.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import '../auth/account_switcher.dart';
import '../pets/pet_avatar.dart';
import '../pets/pet_detail_page.dart';
import '../pets/pet_form_page.dart';
import '../reminders/reminder_page.dart';
import '../settings/settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<Pet>? _pets;
  String? _error;
  bool _loading = true;
  bool _offline = false;
  DateTime? _cachedAt;
  List<Reminder> _pending = const [];

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
    final userId = ref.read(sessionProvider).user?.id;
    try {
      final pets = await ref.read(apiClientProvider).listPets();
      if (!mounted) return;
      setState(() {
        _pets = pets;
        _loading = false;
        _offline = false;
      });
      if (userId != null) await LocalCache.savePets(userId, pets);
      await _loadReminders();
    } on ApiException catch (e) {
      await _loadCachedOrError(e.userMessage);
    } catch (_) {
      await _loadCachedOrError('加载失败，请检查服务器连接');
    }
  }

  Future<void> _loadCachedOrError(String message) async {
    final userId = ref.read(sessionProvider).user?.id;
    if (userId != null) {
      final cached = await LocalCache.loadPets(userId);
      final at = await LocalCache.lastSaved(userId);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _pets = cached;
          _loading = false;
          _error = null;
          _offline = true;
          _cachedAt = at;
        });
        final reminders = await LocalCache.loadReminders(userId, 'pending');
        if (reminders.isNotEmpty && mounted) {
          setState(() => _pending = reminders);
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _loadReminders() async {
    final userId = ref.read(sessionProvider).user?.id;
    try {
      final pending =
          await ref.read(apiClientProvider).listReminders(status: 'pending');
      if (!mounted) return;
      setState(() => _pending = pending);
      if (userId != null) {
        await LocalCache.saveReminders(userId, 'pending', pending);
      }
      await NotificationService.syncReminders(pending);
    } catch (_) {
      // Reminders should never block the pet list.
      if (userId != null) {
        final cached = await LocalCache.loadReminders(userId, 'pending');
        if (cached.isNotEmpty && mounted) setState(() => _pending = cached);
      }
    }
  }

  Future<void> _openReminders() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReminderPage()),
    );
    if (mounted) await _loadReminders();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (mounted) _load();
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PetFormPage()),
    );
    if (changed == true) _load();
  }

  Future<void> _openDetail(Pet pet) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PetDetailPage(pet: pet)),
    );
    if (changed == true) _load();
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 20, color: danger ? Colors.red : Colors.black54),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: danger ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后会清除本机设备凭证，服务器数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true) await _signOut();
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
    // Home may be pushed from the assistant drawer; show the login page.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('宠物档案', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '照护提醒',
            onPressed: _openReminders,
            icon: Badge(
              isLabelVisible: _pending.isNotEmpty,
              label: Text('${_pending.length}'),
              child: const Icon(Icons.notifications_none),
            ),
          ),
          PopupMenuButton<String>(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            color: Colors.white,
            elevation: 8,
            offset: const Offset(0, 6),
            constraints: const BoxConstraints(minWidth: 190),
            onSelected: (value) {
              switch (value) {
                case 'reminders':
                  _openReminders();
                  break;
                case 'settings':
                  _openSettings();
                  break;
                case 'switch':
                  _switchAccount();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              _menuItem('reminders', Icons.notifications_none, '照护提醒'),
              _menuItem('settings', Icons.settings_outlined, '设置'),
              _menuItem('switch', Icons.switch_account_outlined, '切换账号'),
              const PopupMenuDivider(height: 1),
              _menuItem('logout', Icons.logout, '退出登录', danger: true),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(user),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('添加宠物'),
      ),
    );
  }

  Widget _buildBody(User? user) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.black38),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    final pets = _pets ?? const <Pet>[];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (_offline)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF0DC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '离线：显示最近缓存'
              '${_cachedAt == null ? '' : '（${_cachedAt!.year}-${_cachedAt!.month.toString().padLeft(2, '0')}-${_cachedAt!.day.toString().padLeft(2, '0')}）'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A4B08)),
            ),
          ),
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '你好，${user.displayName.isEmpty ? user.username : user.displayName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        if (pets.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              children: [
                Text('🐱', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('还没有宠物档案'),
                SizedBox(height: 6),
                Text('点击右下角，为第一只毛孩子建档',
                    style: TextStyle(color: Colors.black54)),
              ],
            ),
          )
        else
          ...pets.map(
            (pet) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PetCard(
                pet: pet,
                onTap: () => _openDetail(pet),
              ),
            ),
          ),
      ],
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.pet, required this.onTap});

  final Pet pet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              PetAvatar(pet: pet, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pet.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pet.isShared)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0E4),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              pet.role == 'co_caregiver' ? '共同照护' : '只读共享',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pet.speciesLabel} · ${pet.breed.isEmpty ? '未填写品种' : pet.breed}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pet.identityNo}${pet.currentWeightKg > 0 ? ' · ${pet.currentWeightKg.toStringAsFixed(1)} kg' : ''}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
