import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import 'pet_form_page.dart';

class PetDetailPage extends ConsumerStatefulWidget {
  const PetDetailPage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<PetDetailPage> createState() => _PetDetailPageState();
}

class _PetDetailPageState extends ConsumerState<PetDetailPage> {
  late final Pet _pet = widget.pet;
  bool _deleting = false;

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_pet.name),
        actions: [
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
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: const Color(0xFFF1E4D8),
                    child: Text(
                      _pet.species == 'cat'
                          ? '🐱'
                          : _pet.species == 'dog'
                              ? '🐶'
                              : '🐾',
                      style: const TextStyle(fontSize: 42),
                    ),
                  ),
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
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _InfoRow(label: '生日', value: _pet.birthday.isEmpty ? '未填写' : _pet.birthday),
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
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('下一步',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    '健康记录、提醒、OCR 与 AI 会话会在这个档案里继续展开。',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
                child: Text(label,
                    style: const TextStyle(color: Colors.black54)),
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
