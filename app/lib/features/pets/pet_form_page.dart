import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import 'pet_avatar.dart';

class PetFormPage extends ConsumerStatefulWidget {
  const PetFormPage({super.key, this.pet});

  final Pet? pet;

  @override
  ConsumerState<PetFormPage> createState() => _PetFormPageState();
}

class _PetFormPageState extends ConsumerState<PetFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _weight;
  late final TextEditingController _allergies;
  late final TextEditingController _chronic;
  late final TextEditingController _medications;
  late String _species;
  late String _sex;
  late String _neutered;
  String? _birthday;
  XFile? _avatarFile;
  bool _saving = false;

  bool get _isEdit => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final pet = widget.pet;
    _name = TextEditingController(text: pet?.name ?? '');
    _breed = TextEditingController(text: pet?.breed ?? '');
    _weight = TextEditingController(
      text: (pet?.currentWeightKg ?? 0) > 0
          ? pet!.currentWeightKg.toStringAsFixed(1)
          : '',
    );
    _allergies = TextEditingController(text: pet?.allergies ?? '');
    _chronic = TextEditingController(text: pet?.chronicConditions ?? '');
    _medications = TextEditingController(text: pet?.medications ?? '');
    _species = pet?.species ?? 'cat';
    _sex = pet?.sex ?? 'unknown';
    _neutered = pet?.neutered ?? 'unknown';
    _birthday = (pet?.birthday.isEmpty ?? true) ? null : pet!.birthday;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _weight.dispose();
    _allergies.dispose();
    _chronic.dispose();
    _medications.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (picked != null && mounted) {
        setState(() => _avatarFile = picked);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('选择图片失败')));
    }
  }

  String get _avatarEmoji {
    final species = _isEdit ? widget.pet!.species : _species;
    return species == 'cat' ? '🐱' : species == 'dog' ? '🐶' : '🐾';
  }

  Widget _avatarPreview() {
    if (_avatarFile != null) {
      return ClipOval(
        child: Image.file(
          File(_avatarFile!.path),
          width: 88,
          height: 88,
          fit: BoxFit.cover,
        ),
      );
    }
    if (_isEdit && widget.pet!.avatarPath.isNotEmpty) {
      return PetAvatar(pet: widget.pet!, radius: 44);
    }
    return CircleAvatar(
      radius: 44,
      backgroundColor: const Color(0xFFF1E4D8),
      child: Text(_avatarEmoji, style: const TextStyle(fontSize: 40)),
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday == null
        ? DateTime(now.year - 1, now.month, now.day)
        : DateTime.tryParse(_birthday!) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: now,
      helpText: '选择生日',
    );
    if (picked != null) {
      setState(() => _birthday = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'species': _species,
      'breed': _breed.text.trim(),
      'sex': _sex,
      'birthday': _birthday ?? '',
      'birthdayEstimated': false,
      'neutered': _neutered,
      'currentWeightKg': double.tryParse(_weight.text.trim()) ?? 0,
      'allergies': _allergies.text.trim(),
      'chronicConditions': _chronic.text.trim(),
      'medications': _medications.text.trim(),
    };
    try {
      final api = ref.read(apiClientProvider);
      final saved = _isEdit
          ? await api.updatePet(widget.pet!.id, payload)
          : await api.createPet(payload);
      if (_avatarFile != null) {
        await api.uploadPetAvatar(saved.id, _avatarFile!.path);
      }
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑宠物' : '新建宠物档案')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _avatarPreview(),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: InkWell(
                          onTap: _saving ? null : _pickAvatar,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _pickAvatar,
                    child: const Text('设置头像'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名字',
                    prefixIcon: Icon(Icons.pets),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入名字' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _species,
                  decoration: const InputDecoration(labelText: '物种'),
                  items: const [
                    DropdownMenuItem(value: 'cat', child: Text('猫')),
                    DropdownMenuItem(value: 'dog', child: Text('狗')),
                    DropdownMenuItem(value: 'other', child: Text('其他')),
                  ],
                  onChanged: (v) => setState(() => _species = v ?? 'cat'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _breed,
                  decoration: const InputDecoration(
                    labelText: '品种',
                    hintText: '如：美短、金毛、混血',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sex,
                        decoration: const InputDecoration(labelText: '性别'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('公')),
                          DropdownMenuItem(value: 'female', child: Text('母')),
                          DropdownMenuItem(value: 'unknown', child: Text('未知')),
                        ],
                        onChanged: (v) => setState(() => _sex = v ?? 'unknown'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _neutered,
                        decoration: const InputDecoration(labelText: '绝育'),
                        items: const [
                          DropdownMenuItem(value: 'yes', child: Text('已绝育')),
                          DropdownMenuItem(value: 'no', child: Text('未绝育')),
                          DropdownMenuItem(value: 'unknown', child: Text('未知')),
                        ],
                        onChanged: (v) =>
                            setState(() => _neutered = v ?? 'unknown'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickBirthday,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '生日',
                            prefixIcon: Icon(Icons.cake_outlined),
                          ),
                          child: Text(_birthday ?? '未填写'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _weight,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '体重 (kg)',
                          prefixIcon: Icon(Icons.monitor_weight_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final value = double.tryParse(v.trim());
                          if (value == null || value <= 0 || value > 120) {
                            return '请输入 0–120';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _allergies,
                  decoration: const InputDecoration(
                    labelText: '过敏史（可选）',
                    prefixIcon: Icon(Icons.warning_amber_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _chronic,
                  decoration: const InputDecoration(
                    labelText: '慢性病（可选）',
                    prefixIcon: Icon(Icons.favorite_border),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _medications,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '长期用药（可选）',
                    prefixIcon: Icon(Icons.medication_outlined),
                  ),
                ),
                const SizedBox(height: 26),
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
                      : Text(_isEdit ? '保存修改' : '创建档案'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
