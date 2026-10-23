import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/cache.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../ai/ai_chat_page.dart';
import '../ocr/ocr_page.dart';
import 'pet_avatar.dart';
import '../records/record_form_page.dart';
import '../records/timeline_page.dart';
import '../records/weight_page.dart';
import '../sharing/pet_share_page.dart';
import 'pet_form_page.dart';

class PetDetailPage extends ConsumerStatefulWidget {
  const PetDetailPage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<PetDetailPage> createState() => _PetDetailPageState();
}

class _PetDetailPageState extends ConsumerState<PetDetailPage> {
  late Pet _pet = widget.pet;
  bool _deleting = false;
  bool _loadingDetails = true;
  List<HealthRecord> _records = const [];
  List<WeightRecord> _weights = const [];
  String? _detailsError;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loadingDetails = true;
      _detailsError = null;
    });
    final userId = ref.read(sessionProvider).user?.id;
    try {
      final api = ref.read(apiClientProvider);
      final pet = await api.getPet(_pet.id);
      final records = await api.listRecords(_pet.id);
      final weights = await api.listWeights(_pet.id);
      if (!mounted) return;
      setState(() {
        _pet = pet;
        _records = records;
        _weights = weights;
        _loadingDetails = false;
        _offline = false;
      });
      if (userId != null) {
        await LocalCache.saveRecords(userId, _pet.id, records);
        await LocalCache.saveWeights(userId, _pet.id, weights);
      }
    } on ApiException catch (e) {
      await _loadCachedDetails(e.userMessage);
    } catch (_) {
      await _loadCachedDetails('记录加载失败');
    }
  }

  Future<void> _loadCachedDetails(String message) async {
    final userId = ref.read(sessionProvider).user?.id;
    if (userId != null) {
      final records = await LocalCache.loadRecords(userId, _pet.id);
      final weights = await LocalCache.loadWeights(userId, _pet.id);
      if ((records.isNotEmpty || weights.isNotEmpty) && mounted) {
        setState(() {
          _records = records;
          _weights = weights;
          _detailsError = null;
          _offline = true;
          _loadingDetails = false;
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _detailsError = message;
      _loadingDetails = false;
    });
  }

  bool get _canEditRecords => _pet.role != 'viewer';

  Future<void> _addRecord() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordFormPage(pet: _pet)),
    );
    if (changed == true) _loadDetails();
  }

  Future<void> _editRecord(HealthRecord record) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordFormPage(pet: _pet, record: record),
      ),
    );
    if (changed == true) _loadDetails();
  }

  Future<void> _openTimeline() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TimelinePage(pet: _pet)),
    );
    if (mounted) _loadDetails();
  }

  Future<void> _openWeights() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WeightPage(pet: _pet)),
    );
    if (mounted) _loadDetails();
  }

  Future<void> _openShare() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PetSharePage(pet: _pet)),
    );
  }

  Future<void> _openAi() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AiChatPage(pet: _pet)),
    );
  }

  Future<void> _showQrCode() async {
    try {
      final api = ref.read(apiClientProvider);
      final grant = await api.createShareGrant(
        _pet.id,
        role: 'viewer',
        ttlDays: 7,
      );
      if (!mounted) return;
      final url = api.shareUrl(grant.token);
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_pet.name} · 电子身份证',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: QrImageView(
                      data: url,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    url,
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '扫码可免登录查看宠物摘要与今日待办；只读、7 天有效，可在共享页随时撤销。',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: url));
                            Navigator.pop(context);
                            showToast(context, '链接已复制');
                          },
                          child: const Text('复制链接'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  Future<void> _openOcr() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OcrPage(pet: _pet)),
    );
    if (changed == true) _loadDetails();
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PetFormPage(pet: _pet)),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除宠物档案'),
        content: Text('确定删除「${_pet.name}」吗？30 天内可在服务器数据中恢复。'),
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
    setState(() => _deleting = true);
    try {
      await ref.read(apiClientProvider).deletePet(_pet.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showToast(context, e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_pet.name),
        actions: [
          IconButton(
            onPressed: _openAi,
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'AI 助手',
          ),
          if (_canEditRecords)
            IconButton(
              onPressed: _openOcr,
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: '拍照识别化验单',
            ),
          if (_pet.isOwner)
            IconButton(
              onPressed: _openShare,
              icon: const Icon(Icons.people_alt_outlined),
              tooltip: '共享',
            ),
          if (_pet.isOwner)
            IconButton(
              onPressed: _deleting ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
            ),
          if (_pet.isOwner)
            IconButton(
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  PetAvatar(pet: _pet, radius: 44),
                  const SizedBox(height: 12),
                  Text(
                    _pet.name,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_pet.speciesLabel} · ${_pet.breed.isEmpty ? '未填写品种' : _pet.breed} · ${_pet.sexLabel}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (_pet.isShared)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0E4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _pet.role == 'co_caregiver'
                            ? '共享给我 · 共同照护'
                            : '共享给我 · 只读',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F2A26),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('电子身份证',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(
                          _pet.identityNo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_pet.name} · ${_pet.speciesLabel} · ${_pet.neuteredLabel}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (_pet.isOwner) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showQrCode,
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('证件卡二维码'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _InfoRow(
                    label: '生日',
                    value: _pet.birthday.isEmpty ? '未填写' : _pet.birthday),
                _InfoRow(
                  label: '体重',
                  value: _pet.currentWeightKg > 0
                      ? '${_pet.currentWeightKg.toStringAsFixed(1)} kg'
                      : '未填写',
                ),
                _InfoRow(label: '绝育', value: _pet.neuteredLabel),
                _InfoRow(
                  label: '过敏史',
                  value: _pet.allergies.isEmpty ? '无' : _pet.allergies,
                ),
                _InfoRow(
                  label: '慢性病',
                  value: _pet.chronicConditions.isEmpty
                      ? '无'
                      : _pet.chronicConditions,
                ),
                _InfoRow(
                  label: '长期用药',
                  value: _pet.medications.isEmpty ? '无' : _pet.medications,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text('健康记录',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('${_records.length} 条记录 · 查看时间线'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '时间线',
                        onPressed: _openTimeline,
                        icon: const Icon(Icons.timeline, size: 20),
                      ),
                      if (_canEditRecords)
                        TextButton.icon(
                          onPressed: _addRecord,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加'),
                        ),
                    ],
                  ),
                  onTap: _openTimeline,
                ),
                if (_loadingDetails)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else if (_offline)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '离线：显示最近缓存记录',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF8A4B08)),
                      ),
                    ),
                  )
                else if (_detailsError != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(_detailsError!),
                    trailing: IconButton(
                      onPressed: _loadDetails,
                      icon: const Icon(Icons.refresh),
                    ),
                  )
                else if (_records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('还没有健康记录，先添加一条疫苗或驱虫记录。',
                          style: TextStyle(color: Colors.black54)),
                    ),
                  )
                else
                  ..._records.take(20).map(
                        (record) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFF1E4D8),
                            child: Text(
                              _recordEmoji(record.type),
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          title: Text(record.title),
                          subtitle: Text(
                            [
                              record.occurredAt,
                              if (record.summary.isNotEmpty) record.summary,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                          onTap: _canEditRecords
                              ? () => _editRecord(record)
                              : null,
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
                  title: Text('体重',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    _weights.isEmpty
                        ? (_pet.currentWeightKg > 0
                            ? '当前 ${_pet.currentWeightKg.toStringAsFixed(1)} kg'
                            : '还没有体重记录')
                        : '最近 ${_weights.last.weightKg.toStringAsFixed(1)} kg · ${_weights.last.measuredAt}',
                  ),
                  trailing: TextButton.icon(
                    onPressed: _openWeights,
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: Text(_weights.length >= 2 ? '曲线' : '记录'),
                  ),
                  onTap: _openWeights,
                ),
                if (_weights.length >= 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '共 ${_weights.length} 次记录，点击查看体重曲线。',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _recordEmoji(String type) {
    return switch (type) {
      'vaccine' => '💉',
      'deworming' => '💊',
      'checkup' => '🩺',
      'medical' => '📋',
      'medication' => '💊',
      'grooming' => '🛁',
      'diet' => '🍚',
      _ => '📝',
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child:
                    Text(label, style: const TextStyle(color: Colors.black54)),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        ),
        if (!last) const Divider(height: 1, indent: 18, endIndent: 18),
      ],
    );
  }
}
