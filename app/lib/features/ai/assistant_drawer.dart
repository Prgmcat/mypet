import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_sessions.dart';
import '../../core/session.dart';
import '../auth/account_switcher.dart';
import '../home/home_page.dart';
import '../reminders/reminder_page.dart';
import '../settings/settings_page.dart';

/// Left drawer for the assistant landing page, modelled on the chat apps the
/// product is compared with: new chat, main sections, recent conversations and
/// the current account at the bottom.
class AssistantDrawer extends ConsumerStatefulWidget {
  const AssistantDrawer({
    super.key,
    required this.currentSessionId,
    required this.onNewChat,
    required this.onOpenSession,
  });

  final String currentSessionId;
  final VoidCallback onNewChat;
  final ValueChanged<AiSession> onOpenSession;

  @override
  ConsumerState<AssistantDrawer> createState() => _AssistantDrawerState();
}

class _AssistantDrawerState extends ConsumerState<AssistantDrawer> {
  List<AiSession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(sessionProvider).user?.id;
    if (userId == null) return;
    final sessions = await AiSessionStore.load(userId);
    if (!mounted) return;
    setState(() => _sessions = sessions);
  }

  void _close() => Navigator.of(context).pop();

  void _open(Widget page) {
    _close();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _delete(AiSession session) async {
    final userId = ref.read(sessionProvider).user?.id;
    if (userId == null) return;
    await AiSessionStore.delete(userId, session.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;
    final name = (user?.displayName ?? '').trim().isEmpty
        ? (user?.username ?? '')
        : user!.displayName;
    final recent = _sessions.take(12).toList();
    return Drawer(
      backgroundColor: const Color(0xFFFBF7F1),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  const Text('🐾', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(
                    '喵了个咪',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新对话'),
              onTap: () {
                _close();
                widget.onNewChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.pets_outlined),
              title: const Text('宠物档案'),
              onTap: () => _open(const HomePage()),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('照护提醒'),
              onTap: () => _open(const ReminderPage()),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () => _open(const SettingsPage()),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Text(
                '最近对话',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.black45),
              ),
            ),
            Expanded(
              child: recent.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        '还没有对话记录',
                        style: TextStyle(fontSize: 12, color: Colors.black38),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final session in recent)
                          ListTile(
                            dense: true,
                            selected: session.id == widget.currentSessionId,
                            selectedTileColor: const Color(0xFFF1E4D8),
                            leading: Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                              color: session.id == widget.currentSessionId
                                  ? const Color(0xFF8A4B08)
                                  : Colors.black45,
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              _dateLabel(session.updatedAt),
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              tooltip: '删除对话',
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => _delete(session),
                            ),
                            onTap: () {
                              _close();
                              widget.onOpenSession(session);
                            },
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF1E4D8),
                child: Text(
                  name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(name.isEmpty ? '未登录' : name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('@${user?.username ?? ''}'),
              trailing: const Icon(Icons.swap_horiz, size: 20),
              onTap: () {
                _close();
                showAccountSwitcher(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(String updatedAt) {
    final date = DateTime.tryParse(updatedAt)?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '今天 $h:$m';
    }
    return '${date.month}-${date.day.toString().padLeft(2, '0')}';
  }
}
