import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/models.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import 'appointment_form_page.dart';

class AppointmentPage extends ConsumerStatefulWidget {
  const AppointmentPage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends ConsumerState<AppointmentPage> {
  List<Appointment> _pending = const [];
  List<Appointment> _history = const [];
  bool _loading = true;
  String? _error;

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
        api.listPetAppointments(widget.pet.id, status: 'pending'),
        api.listPetAppointments(widget.pet.id, status: 'done'),
        api.listPetAppointments(widget.pet.id, status: 'skipped'),
      ]);
      final history = <Appointment>[
        ...results[1],
        ...results[2],
      ]..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      if (!mounted) return;
      setState(() {
        _pending = results[0];
        _history = history;
        _loading = false;
      });
      await _syncNotifications();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '预约加载失败，请检查服务器连接';
        _loading = false;
      });
    }
  }

  /// Keeps local notifications aligned with every pending task, not just this
  /// pet, because syncing replaces the whole scheduled set.
  Future<void> _syncNotifications() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.listReminders(status: 'pending'),
        api.listAppointments(status: 'pending'),
      ]);
      await NotificationService.syncTasks(
        reminders: results[0] as List<Reminder>,
        appointments: results[1] as List<Appointment>,
      );
    } catch (_) {
      // Notification scheduling is best effort.
    }
  }

  Future<void> _openForm([Appointment? appointment]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AppointmentFormPage(
          pet: widget.pet,
          appointment: appointment,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _act(Appointment appointment, String action) async {
    if (action == 'skip') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('跳过这次预约'),
          content: Text('将跳过「${appointment.title}」，不会生成健康记录。'),
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
    final api = ref.read(apiClientProvider);
    try {
      switch (action) {
        case 'complete':
          final done = await api.completeAppointment(appointment.id);
          if (!mounted) return;
          showToast(
            context,
            done.recordId.isEmpty ? '预约已完成' : '预约已完成，已生成健康记录',
          );
        case 'snooze':
          await api.snoozeAppointment(appointment.id);
          if (!mounted) return;
          showToast(context, '已稍后提醒（24 小时）');
        default:
          await api.skipAppointment(appointment.id);
          if (!mounted) return;
          showToast(context, '已跳过本次预约');
      }
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
        title: Text('预约 · ${widget.pet.name}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_alarm),
        label: const Text('新增预约'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      if (_pending.isEmpty && _history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Text(
                            '📅\n还没有预约\n比如「下周一带它去驱虫」',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, height: 1.8),
                          ),
                        ),
                      if (_pending.isNotEmpty) ...[
                        const _SectionTitle('待办预约'),
                        for (final appointment in _pending)
                          _AppointmentCard(
                            appointment: appointment,
                            pending: true,
                            onTap: () => _openForm(appointment),
                            onAct: (action) => _act(appointment, action),
                          ),
                      ],
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const _SectionTitle('历史预约'),
                        for (final appointment in _history)
                          _AppointmentCard(
                            appointment: appointment,
                            pending: false,
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.pending,
    this.onTap,
    this.onAct,
  });

  final Appointment appointment;
  final bool pending;
  final VoidCallback? onTap;
  final void Function(String action)? onAct;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        StringBuffer('${appointment.scheduledAt} · ${appointment.typeLabel}');
    if (appointment.note.isNotEmpty) subtitle.write(' · ${appointment.note}');
    if (!pending) {
      subtitle.write(appointment.status == 'skipped' ? ' · 已跳过' : ' · 已完成');
      if (appointment.recordId.isNotEmpty) subtitle.write('，已生成健康记录');
    } else if (appointment.status == 'snoozed') {
      subtitle.write(' · 已稍后');
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: pending ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF1E4D8),
                    child: Text(appointment.emoji,
                        style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appointment.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle.toString(),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (pending)
                    const Icon(Icons.chevron_right)
                  else if (appointment.status == 'done')
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 20)
                  else
                    const Icon(Icons.remove_circle_outline,
                        color: Colors.black26, size: 20),
                ],
              ),
              if (pending && appointment.canAct) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => onAct?.call('skip'),
                      child: const Text('跳过'),
                    ),
                    TextButton(
                      onPressed: () => onAct?.call('snooze'),
                      child: const Text('稍后'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => onAct?.call('complete'),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
