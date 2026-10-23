import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../pets/pet_detail_page.dart';
import '../pets/pet_form_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<Pet>? _pets;
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
      final pets = await ref.read(apiClientProvider).listPets();
      if (!mounted) return;
      setState(() {
        _pets = pets;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败，请检查服务器连接';
        _loading = false;
      });
    }
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

  Future<void> _showInvite() async {
    final code = await ref.read(sessionProvider.notifier).createInvite();
    if (!mounted) return;
    if (code == null || code.startsWith('ERR:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(code?.replaceFirst('ERR:', '') ?? '创建失败')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('邀请码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('把这串邀请码发给新用户，默认 7 天有效、可用 1 次。'),
            const SizedBox(height: 16),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已复制邀请码')));
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
  }

  Future<void> _showUsers() async {
    try {
      final users = await ref.read(sessionProvider.notifier).listUsers();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('用户列表'),
          content: SizedBox(
            width: 360,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final u = users[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(u.displayName.isEmpty ? u.username : u.displayName),
                  subtitle: Text(u.username),
                  trailing: u.isAdmin
                      ? const Chip(label: Text('管理员'))
                      : Text(u.status == 'active' ? '正常' : '已禁用'),
                );
              },
            ),
          ),
          actions: [
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
    if (ok == true) {
      await ref.read(sessionProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('喵了个咪',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'invite':
                  _showInvite();
                  break;
                case 'users':
                  _showUsers();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (user?.isAdmin == true) ...[
                const PopupMenuItem(
                  value: 'invite',
                  child: ListTile(
                    leading: Icon(Icons.vpn_key_outlined),
                    title: Text('创建邀请码'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'users',
                  child: ListTile(
                    leading: Icon(Icons.group_outlined),
                    title: Text('用户列表'),
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('退出登录'),
                ),
              ),
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
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFFF1E4D8),
                child: Text(
                  pet.species == 'cat' ? '🐱' : pet.species == 'dog' ? '🐶' : '🐾',
                  style: const TextStyle(fontSize: 28),
                ),
              ),
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
