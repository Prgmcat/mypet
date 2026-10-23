import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/models.dart';
import '../../core/session.dart';

class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends ConsumerState<WeightPage> {
  List<WeightRecord>? _weights;
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
      final weights =
          await ref.read(apiClientProvider).listWeights(widget.pet.id);
      if (!mounted) return;
      setState(() {
        _weights = weights;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final value = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('记录体重'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: value,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '体重 (kg)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '测量日期',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(DateFormat('yyyy-MM-dd').format(date)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final kg = double.tryParse(value.text.trim());
    final noteText = note.text.trim();
    value.dispose();
    note.dispose();
    if (kg == null || kg <= 0 || kg > 120) {
      if (!mounted) return;
      showToast(context, '请输入有效体重');
      return;
    }
    try {
      await ref.read(apiClientProvider).createWeight(widget.pet.id, {
        'measuredAt': DateFormat('yyyy-MM-dd').format(date),
        'weightKg': kg,
        'note': noteText,
      });
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showToast(context, e.userMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.pet.name} · 体重')),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              onPressed: _add,
              child: const Icon(Icons.add),
            )
          : null,
      body: _buildBody(),
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
    final weights = _weights ?? const <WeightRecord>[];
    if (weights.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monitor_weight_outlined,
                  size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              const Text('还没有体重记录'),
              const SizedBox(height: 6),
              const Text(
                '至少记录 2 次后可查看体重曲线',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
              if (_canEdit) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _add,
                  child: const Text('记录第一次'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (weights.length >= 2)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
              child: SizedBox(height: 220, child: _chart(weights)),
            ),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '已记录 1 次体重，再记录一次即可生成曲线。',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (final weight in weights.reversed)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1E4D8),
                child: Icon(Icons.monitor_weight_outlined, size: 20),
              ),
              title: Text('${weight.weightKg.toStringAsFixed(1)} kg'),
              subtitle: Text(
                [weight.measuredAt, if (weight.note.isNotEmpty) weight.note]
                    .join(' · '),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chart(List<WeightRecord> weights) {
    final spots = <FlSpot>[
      for (var i = 0; i < weights.length; i++)
        FlSpot(i.toDouble(), weights[i].weightKg),
    ];
    final values = weights.map((w) => w.weightKg);
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final padding = math.max(1.0, (maxValue - minValue) * 0.25);
    final labelStep = math.max(1, (weights.length / 4).ceil());
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (weights.length - 1).toDouble(),
        minY: math.max(0, minValue - padding),
        maxY: maxValue + padding,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 42),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= weights.length) {
                  return const SizedBox.shrink();
                }
                if (index % labelStep != 0 && index != weights.length - 1) {
                  return const SizedBox.shrink();
                }
                final date = DateTime.tryParse(weights[index].measuredAt);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    date == null ? '' : DateFormat('MM-dd').format(date),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF8B5E3C),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF8B5E3C).withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}
