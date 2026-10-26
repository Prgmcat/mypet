import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/models.dart';
import '../../core/session.dart';

const appointmentTypes = <String, String>{
  'deworming': '驱虫',
  'vaccine': '疫苗',
  'checkup': '体检',
  'medical': '就诊',
  'medication': '用药',
  'grooming': '洗护',
  'other': '其他',
};

class AppointmentFormPage extends ConsumerStatefulWidget {
  const AppointmentFormPage({
    super.key,
    required this.pet,
    this.appointment,
  });

  final Pet pet;
  final Appointment? appointment;

  @override
  ConsumerState<AppointmentFormPage> createState() =>
      _AppointmentFormPageState();
}

class _AppointmentFormPageState extends ConsumerState<AppointmentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _note = TextEditingController();

  late String _type;
  late DateTime _scheduledAt;
  bool _saving = false;

  bool get _isEdit => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    _type = appointment?.type ?? 'deworming';
    _scheduledAt = DateTime.tryParse(appointment?.scheduledAt ?? '') ??
        DateTime.now().add(const Duration(days: 1));
    _title.text = appointment?.title ?? appointmentTypes[_type]!;
    _note.text = appointment?.note ?? '';
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
      initialDate: _scheduledAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择预约日期',
    );
    if (picked != null) setState(() => _scheduledAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = {
      'type': _type,
      'title': _title.text.trim(),
      'scheduledAt': DateFormat('yyyy-MM-dd').format(_scheduledAt),
      'note': _note.text.trim(),
    };
    try {
      final api = ref.read(apiClientProvider);
      if (_isEdit) {
        await api.updateAppointment(widget.appointment!.id, payload);
      } else {
        await api.createAppointment(widget.pet.id, payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, e.userMessage, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '保存失败，请稍后重试');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除预约'),
        content: const Text('只删除这次预约，不会影响已有的健康记录。'),
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
      await ref
          .read(apiClientProvider)
          .deleteAppointment(widget.appointment!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑预约' : '新增预约'),
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
                  decoration: const InputDecoration(labelText: '预约类型'),
                  items: appointmentTypes.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      final previous = appointmentTypes[_type]!;
                      _type = value;
                      if (_title.text.isEmpty ||
                          _title.text == previous ||
                          appointmentTypes.containsValue(_title.text)) {
                        _title.text = appointmentTypes[value]!;
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '标题'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入标题' : null,
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '预约日期',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(DateFormat('yyyy-MM-dd').format(_scheduledAt)),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '例如要带的资料、医院或药品',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '到期前会通过「照护提醒」通知你；完成后会自动生成一条健康记录。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
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
                      : Text(_isEdit ? '保存修改' : '保存预约'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
