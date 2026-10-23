import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/cache.dart';
import '../../core/models.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';

class ReminderPage extends ConsumerStatefulWidget {
  const ReminderPage({super.key});

  @override
  ConsumerState<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends ConsumerState<ReminderPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final Map<String, List<Reminder>> _byStatus = {
    'pending': const [],
    'done': const [],
    'skipped': const [],
  };
  bool _loading = true;
  bool _offline = false;
  String? _error;

  static const _statuses = ['pending', 'done', 'skipped'];
  static const _labels = ['待办', '已完成', '已跳过'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final userId = ref.read(sessionProvider).user?.id;
    List<List<Reminder>> results;
    try {
      results = await Future.wait(
        _statuses.map((status) => api.listReminders(status: status)),
      );
    } on ApiException catch (e) {
      await _loadCached(e.userMessage);
      return;
    } catch (e) {
      debugPrint('reminders load failed: $e');
      await _loadCached('提醒加载失败，请检查服务器连接');
      return;
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _statuses.length; i++) {
        _byStatus[_statuses[i]] = results[i];
      }
      _loading = false;
      _offline = false;
    });
    // Caching and notification scheduling are best effort; neither should
    // turn a successful online load into an "offline" screen.
    if (userId != null) {
      try {
        for (var i = 0; i < _statuses.length; i++) {
          await LocalCache.saveReminders(userId, _statuses[i], results[i]);
        }
      } catch (e) {
        debugPrint('reminders cache save failed: $e');
      }
    }
    try {
      await NotificationService.syncReminders(_byStatus['pending']!);
    } catch (e) {
      debugPrint('reminders notification sync failed: $e');
    }
  }

  Future<void> _loadCached(String message) async {
    final userId = ref.read(sessionProvider).user?.id;
    if (userId != null) {
      var hasData = false;
      final cachedByStatus = <String, List<Reminder>>{};
      for (final status in _statuses) {
        final rows = await LocalCache.loadReminders(userId, status);
        cachedByStatus[status] = rows;
        if (rows.isNotEmpty) hasData = true;
      }
      if (hasData && mounted) {
        setState(() {
          _byStatus.addAll(cachedByStatus);
          _loading = false;
          _error = null;
          _offline = true;
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _act(Reminder reminder, String action) async {
    if (action == 'skip') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('跳过这次提醒'),
          content: Text(
              '将跳过「${reminder.petName} · ${reminder.typeLabel}」的本次提醒，周期设置保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('跳过'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(apiClientProvider).updateReminder(
            reminder.id,
            action,
            snoozeHours: action == 'snooze' ? 24 : null,
          );
      if (!mounted) return;
      final message = switch (action) {
        'complete' => '已完成，下次提醒已自动计算',
        'snooze' => '已稍后提醒（24 小时）',
        _ => '已跳过本次提醒',
      };
      showToast(context, message);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('照护提醒'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            for (var i = 0; i < _labels.length; i++)
              Tab(text: '${_labels[i]}（${_byStatus[_statuses[i]]!.length}）'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    if (_offline)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: const Color(0xFFFDF0DC),
                        child: const Text(
                          '离线：显示最近缓存的提醒',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF8A4B08)),
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          for (final status in _statuses)
                            _ReminderList(
                              reminders: _byStatus[status]!,
                              status: status,
                              onRefresh: _load,
                              onAct: _act,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.reminders,
    required this.status,
    required this.onRefresh,
    required this.onAct,
  });

  final List<Reminder> reminders;
  final String status;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Reminder, String) onAct;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 140),
            Text(
              status == 'pending' ? '🐾\n今天没有待办' : '这里还没有记录',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.8),
            ),
            if (status == 'pending')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '新增带「下次提醒日期」的记录后会自动生成',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 13),
                ),
              ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: reminders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final r = reminders[index];
          final overdue = status == 'pending' && r.dueAt.compareTo(today) < 0;
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFF1E4D8),
                        child:
                            Text(r.emoji, style: const TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.petName} · ${r.typeLabel}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '到期 ${r.dueAt}${overdue ? ' · 已逾期' : ''}'
                              '${r.status == 'snoozed' ? ' · 已稍后' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: overdue
                                    ? Colors.red.shade400
                                    : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (status == 'done')
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 20)
                      else if (status == 'skipped')
                        const Icon(Icons.remove_circle_outline,
                            color: Colors.black26, size: 20),
                    ],
                  ),
                  if (status == 'pending' && r.canAct) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => onAct(r, 'skip'),
                          child: const Text('跳过'),
                        ),
                        TextButton(
                          onPressed: () => onAct(r, 'snooze'),
                          child: const Text('稍后'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => onAct(r, 'complete'),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.black38),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
