import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import 'record_form_page.dart';

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  static const _filters = <String, String>{
    '': '全部',
    'vaccine': '疫苗',
    'deworming': '驱虫',
    'checkup': '体检',
    'medical': '病历',
    'medication': '用药',
    'grooming': '洗护',
    'weight': '体重',
  };

  String _filter = '';
  List<TimelineEntry>? _entries;
  String? _error;
  bool _loading = true;

  bool get _canEdit => widget.pet.role != 'viewer';
  bool get _isOwner => widget.pet.role == 'owner';

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
      final entries = await ref
          .read(apiClientProvider)
          .listTimeline(widget.pet.id, type: _filter);
      if (!mounted) return;
      setState(() {
        _entries = entries;
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
        _error = '时间线加载失败';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordFormPage(pet: widget.pet)),
    );
    if (changed == true) _load();
  }

  Future<void> _edit(HealthRecord record) async {
    if (!_canEdit) return;
    final userId = ref.read(sessionProvider).user?.id;
    if (!_isOwner && record.createdByUserId != userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('共同照护者只能编辑自己新增的记录')),
      );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordFormPage(pet: widget.pet, record: record),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.pet.name} · 时间线')),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              onPressed: _add,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final entry in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _filter == entry.key,
                      onSelected: (_) {
                        setState(() => _filter = entry.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final entries = _entries ?? const <TimelineEntry>[];
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Text(
              '还没有记录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              '疫苗、驱虫、体检、病历和体重都会出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          if (entry.kind == 'weight' && entry.weight != null) {
            final w = entry.weight!;
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF1E4D8),
                  child: Icon(Icons.monitor_weight_outlined, size: 20),
                ),
                title: Text('体重 ${w.weightKg.toStringAsFixed(1)} kg'),
                subtitle: Text(
                  [w.measuredAt, if (w.note.isNotEmpty) w.note].join(' · '),
                ),
              ),
            );
          }
          final record = entry.record;
          if (record == null) return const SizedBox.shrink();
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFF1E4D8),
                child: Text(_emoji(record.type),
                    style: const TextStyle(fontSize: 18)),
              ),
              title: Text(record.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text([record.occurredAt, record.typeLabel].join(' · ')),
                  if (record.summary.isNotEmpty)
                    Text(
                      record.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (record.nextDueAt.isNotEmpty)
                    Text('下次 ${record.nextDueAt}',
                        style: const TextStyle(color: Colors.black45)),
                ],
              ),
              trailing: record.attachments.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attachment, size: 16),
                        Text('${record.attachments.length}'),
                      ],
                    ),
              onTap: _canEdit ? () => _edit(record) : null,
            ),
          );
        },
      ),
    );
  }

  String _emoji(String type) => switch (type) {
        'vaccine' => '💉',
        'deworming' => '💊',
        'checkup' => '🩺',
        'medical' => '📋',
        'medication' => '💊',
        'grooming' => '🛁',
        _ => '📝',
      };
}
