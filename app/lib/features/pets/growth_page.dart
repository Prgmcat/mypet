import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/toast.dart';

/// A diary-like timeline for happy moments and milestones. Entries are stored
/// as health records with type `growth`, so they share history, sync and
/// permissions with the rest of the pet profile.
class GrowthPage extends ConsumerStatefulWidget {
  const GrowthPage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends ConsumerState<GrowthPage> {
  List<HealthRecord>? _entries;
  String? _error;
  bool _loading = true;

  bool get _canEdit => widget.pet.role != 'viewer';

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
          .listRecords(widget.pet.id, type: 'growth');
      if (!mounted) return;
      setState(() {
        _entries = entries;
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
        _error = '成长记录加载失败';
        _loading = false;
      });
    }
  }

  Future<void> _edit([HealthRecord? record]) async {
    final draft = await showDialog<_GrowthDraft>(
      context: context,
      builder: (_) => _GrowthEditorDialog(record: record),
    );
    if (draft == null || !mounted) return;
    final payload = <String, dynamic>{
      'type': 'growth',
      'occurredAt': draft.date,
      'title': draft.title,
      'payload': {'note': draft.note},
      'hospital': '',
      'doctor': '',
      'nextDueAt': '',
      'source': record?.source ?? 'manual',
    };
    try {
      final api = ref.read(apiClientProvider);
      if (record == null) {
        await api.createRecord(widget.pet.id, payload);
      } else {
        await api.updateRecord(record.id, payload);
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showToast(context, record == null ? '已记入成长历程' : '已更新');
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  Future<void> _delete(HealthRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录'),
        content: Text('删除「${record.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteRecord(record.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showToast(context, '已删除');
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  String _noteOf(HealthRecord record) =>
      (record.payload['note']?.toString() ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.pet.name} 的成长'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.edit_note),
              label: const Text('记一笔'),
            )
          : null,
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
                      if (_entries == null || _entries!.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 70),
                          child: Column(
                            children: [
                              const Text('🌱', style: TextStyle(fontSize: 44)),
                              const SizedBox(height: 12),
                              Text('还没有成长记录',
                                  style: theme.textTheme.titleMedium),
                            ],
                          ),
                        )
                      else
                        for (final record in _entries!) _entryCard(record),
                    ],
                  ),
                ),
    );
  }

  Widget _entryCard(HealthRecord record) {
    final note = _noteOf(record);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1E4D8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    record.occurredAt,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF7A4A1E)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      record.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (_canEdit)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') _edit(record);
                      if (value == 'delete') _delete(record);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
            if (note.isNotEmpty && note != record.title) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  note,
                  style: const TextStyle(
                      color: Colors.black87, fontSize: 13, height: 1.6),
                ),
              ),
            ],
            if (record.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${record.attachments.length} 张照片',
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GrowthDraft {
  const _GrowthDraft({
    required this.date,
    required this.title,
    required this.note,
  });

  final String date;
  final String title;
  final String note;
}

class _GrowthEditorDialog extends StatefulWidget {
  const _GrowthEditorDialog({this.record});

  final HealthRecord? record;

  @override
  State<_GrowthEditorDialog> createState() => _GrowthEditorDialogState();
}

class _GrowthEditorDialogState extends State<_GrowthEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late DateTime _date;

  String _format(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _title = TextEditingController(text: record?.title ?? '');
    _note = TextEditingController(
        text: (record?.payload['note']?.toString() ?? '').trim());
    _date = DateTime.tryParse(record?.occurredAt ?? '') ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast(context, '写一句这段经历吧', error: true);
      return;
    }
    Navigator.of(context).pop(_GrowthDraft(
      date: _format(_date),
      title: title,
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.record == null ? '记一笔成长' : '编辑成长记录'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_format(_date)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: '发生了什么',
                hintText: '例如：第一次抓到蝴蝶',
              ),
            ),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '详细描述（可选）',
                hintText: '当时的样子、你的心情……',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
