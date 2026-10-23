import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';

class RecordFormPage extends ConsumerStatefulWidget {
  const RecordFormPage({
    super.key,
    required this.pet,
    this.record,
  });

  final Pet pet;
  final HealthRecord? record;

  @override
  ConsumerState<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends ConsumerState<RecordFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _hospital = TextEditingController();
  final _doctor = TextEditingController();
  final _nextDue = TextEditingController();
  final _field1 = TextEditingController();
  final _field2 = TextEditingController();
  final _field3 = TextEditingController();
  final _field4 = TextEditingController();
  final _note = TextEditingController();

  late String _type;
  late DateTime _occurredAt;
  final List<XFile> _pending = [];
  bool _saving = false;

  static const _types = <String, String>{
    'vaccine': '疫苗',
    'deworming': '驱虫',
    'checkup': '体检',
    'medical': '病历',
    'medication': '用药',
    'grooming': '洗护',
    'diet': '饮食',
    'other': '其他',
  };

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _type = record?.type ?? 'deworming';
    _occurredAt = DateTime.tryParse(record?.occurredAt ?? '') ?? DateTime.now();
    _title.text = record?.title ?? '';
    _hospital.text = record?.hospital ?? '';
    _doctor.text = record?.doctor ?? '';
    _nextDue.text = record?.nextDueAt ?? '';
    final payload = record?.payload ?? const <String, dynamic>{};
    _fillPayload(payload);
  }

  void _fillPayload(Map<String, dynamic> payload) {
    _field1.text = payload[_payloadKey(0)]?.toString() ?? '';
    _field2.text = payload[_payloadKey(1)]?.toString() ?? '';
    _field3.text = payload[_payloadKey(2)]?.toString() ?? '';
    _field4.text = payload[_payloadKey(3)]?.toString() ?? '';
    final note = payload['note'];
    if (note != null) _note.text = note.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _hospital,
      _doctor,
      _nextDue,
      _field1,
      _field2,
      _field3,
      _field4,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _fieldLabels => switch (_type) {
        'vaccine' => const ['疫苗名称', '批号', '有效期至 (YYYY-MM-DD)', '接种机构备注'],
        'deworming' => const ['药品名称', '剂量', '当时体重 (kg)', '用药方式'],
        'checkup' => const ['体重 (kg)', '体温', '结论', '建议'],
        'medical' => const ['症状', '诊断', '处方', '医嘱'],
        'medication' => const ['药品名称', '剂量', '频次', '起止日期'],
        'grooming' => const ['项目', '门店', '备注', ''],
        'diet' => const ['品牌/产品', '类型', '份量', '反馈'],
        _ => const ['详情 1', '详情 2', '详情 3', '详情 4'],
      };

  Map<String, dynamic> _payload() {
    final labels = _fieldLabels;
    final values = [_field1.text, _field2.text, _field3.text, _field4.text];
    final payload = <String, dynamic>{};
    for (var i = 0; i < labels.length; i++) {
      final value = values[i].trim();
      if (value.isEmpty || labels[i].isEmpty) continue;
      payload[_payloadKey(i)] = value;
    }
    if (_note.text.trim().isNotEmpty) payload['note'] = _note.text.trim();
    return payload;
  }

  String _payloadKey(int index) {
    return switch (_type) {
      'vaccine' => const ['vaccineName', 'batchNo', 'validUntil', 'clinicNote'][index],
      'deworming' => const ['product', 'dose', 'weightKg', 'method'][index],
      'checkup' => const ['weightKg', 'temperature', 'conclusion', 'advice'][index],
      'medical' => const ['symptoms', 'diagnosis', 'prescription', 'advice'][index],
      'medication' => const ['product', 'dose', 'frequency', 'period'][index],
      'grooming' => const ['item', 'store', 'note', 'extra'][index],
      'diet' => const ['product', 'category', 'amount', 'feedback'][index],
      _ => 'field${index + 1}',
    };
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择日期',
    );
    if (picked != null) setState(() => _occurredAt = picked);
  }

  Future<void> _pickNextDue() async {
    final initial = DateTime.tryParse(_nextDue.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '下次提醒日期',
    );
    if (picked != null) {
      _nextDue.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() => _pending.addAll(picked));
    }
  }

  String _autoNextDue() {
    final days = switch (_type) {
      'vaccine' => 365,
      'deworming' => _field4.text.contains('外') ? 30 : 90,
      'checkup' => 365,
      'grooming' => 30,
      _ => 0,
    };
    if (days <= 0) return '';
    return DateFormat('yyyy-MM-dd')
        .format(_occurredAt.add(Duration(days: days)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final nextDue =
        _nextDue.text.trim().isEmpty ? _autoNextDue() : _nextDue.text.trim();
    final payload = {
      'type': _type,
      'occurredAt': DateFormat('yyyy-MM-dd').format(_occurredAt),
      'title': _title.text.trim().isEmpty ? _types[_type]! : _title.text.trim(),
      'payload': _payload(),
      'hospital': _hospital.text.trim(),
      'doctor': _doctor.text.trim(),
      'nextDueAt': nextDue,
      'source': 'manual',
    };
    try {
      final api = ref.read(apiClientProvider);
      final record = _isEdit
          ? await api.updateRecord(widget.record!.id, payload)
          : await api.createRecord(widget.pet.id, payload);
      var failedUploads = 0;
      for (final image in _pending) {
        try {
          await api.uploadAttachment(widget.pet.id, image.path, recordId: record.id);
        } catch (_) {
          failedUploads++;
        }
      }
      if (!mounted) return;
      if (failedUploads > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录已保存，$failedUploads 张照片上传失败')),
        );
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    }
  }

  void _openAttachment(Attachment attachment) {
    final api = ref.read(apiClientProvider);
    if (attachment.mime.startsWith('image/')) {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    api.attachmentUrl(attachment.id),
                    headers: api.authHeaders,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('图片加载失败'),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(attachment.originalName.isEmpty
            ? '附件'
            : attachment.originalName),
        content: Text(
          '类型：${attachment.mime}\n大小：${(attachment.size / 1024).toStringAsFixed(0)} KB\n\n'
          'PDF 附件需要在电脑浏览器打开；App 内查看 PDF 将在后续版本支持。',
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('删除后 30 天内可恢复。'),
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
      await ref.read(apiClientProvider).deleteRecord(widget.record!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _fieldLabels;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑${_types[_type]}' : '添加健康记录'),
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: '记录类型'),
                  items: _types.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _type = value;
                      if (_title.text.isEmpty ||
                          _types.containsValue(_title.text)) {
                        _title.text = _types[value]!;
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '发生日期',
                            prefixIcon: Icon(Icons.event_outlined),
                          ),
                          child: Text(DateFormat('yyyy-MM-dd').format(_occurredAt)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(labelText: '标题'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '请输入标题' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < labels.length; i++)
                  if (labels[i].isNotEmpty) ...[
                    TextFormField(
                      controller: switch (i) {
                        0 => _field1,
                        1 => _field2,
                        2 => _field3,
                        _ => _field4,
                      },
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: labels[i]),
                    ),
                    const SizedBox(height: 12),
                  ],
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _hospital,
                        decoration: const InputDecoration(labelText: '医院/机构'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _doctor,
                        decoration: const InputDecoration(labelText: '医生'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickNextDue,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '下次提醒日期',
                      helperText: '留空将按默认周期自动计算',
                      prefixIcon: Icon(Icons.alarm_outlined),
                    ),
                    child: Text(
                      _nextDue.text.isEmpty
                          ? (_autoNextDue().isEmpty
                              ? '不设置'
                              : '自动：${_autoNextDue()}')
                          : _nextDue.text,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (widget.record != null && widget.record!.attachments.isNotEmpty) ...[
                  Text('已有附件', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.record!.attachments
                        .map((a) => ActionChip(
                              avatar: Icon(
                                a.mime.startsWith('image/')
                                    ? Icons.image_outlined
                                    : Icons.picture_as_pdf_outlined,
                                size: 18,
                              ),
                              label: Text(
                                a.originalName.isEmpty ? a.mime : a.originalName,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _openAttachment(a),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_pending.isEmpty
                      ? '添加照片'
                      : '已选择 ${_pending.length} 张照片'),
                ),
                if (_pending.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _pending.map((e) => e.name).join('、'),
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEdit ? '保存修改' : '保存记录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
