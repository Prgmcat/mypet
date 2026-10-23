import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/models.dart';
import '../../core/session.dart';

class OcrPage extends ConsumerStatefulWidget {
  const OcrPage({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<OcrPage> createState() => _OcrPageState();
}

class _IndicatorDraft {
  _IndicatorDraft({String name = '', String value = '', String reference = ''})
      : name = TextEditingController(text: name),
        value = TextEditingController(text: value),
        reference = TextEditingController(text: reference);

  final TextEditingController name;
  final TextEditingController value;
  final TextEditingController reference;

  bool get abnormal {
    final v = double.tryParse(
        RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value.text)?.group(0) ?? '');
    if (v == null) return false;
    final nums = RegExp(r'\d+(?:\.\d+)?')
        .allMatches(reference.text)
        .map((m) => double.tryParse(m.group(0)!) ?? 0)
        .toList();
    if (nums.length < 2) return false;
    return v < nums[0] || v > nums[1];
  }

  void dispose() {
    name.dispose();
    value.dispose();
    reference.dispose();
  }

  Map<String, dynamic> toJson() => {
        'name': name.text.trim(),
        'value': value.text.trim(),
        'reference': reference.text.trim(),
        'abnormal': abnormal,
      };
}

class _OcrPageState extends ConsumerState<OcrPage> {
  final _picker = ImagePicker();
  XFile? _image;
  String _rawText = '';
  bool _recognizing = false;
  bool _saving = false;
  String? _error;
  DateTime _date = DateTime.now();
  final _hospital = TextEditingController();
  final _conclusion = TextEditingController();
  final _advice = TextEditingController();
  final List<_IndicatorDraft> _indicators = [];

  @override
  void dispose() {
    _hospital.dispose();
    _conclusion.dispose();
    _advice.dispose();
    for (final indicator in _indicators) {
      indicator.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (file == null) return;
      setState(() {
        _image = file;
        _rawText = '';
        _error = null;
      });
      await _recognize();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法打开图片：$e');
    }
  }

  Future<void> _recognize() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _recognizing = true;
      _error = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final input = InputImage.fromFilePath(image.path);
      final result = await recognizer.processImage(input);
      if (!mounted) return;
      setState(() {
        _rawText = result.text.trim();
        _recognizing = false;
        _applyHeuristics();
      });
      if (_rawText.isEmpty) {
        setState(() => _error = '没有识别到文字，可换一张更清晰的照片或手动填写。');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = '识别失败：$e。可以先手动填写，稍后重试。';
      });
    } finally {
      await recognizer.close();
    }
  }

  void _applyHeuristics() {
    final lines = _rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (_hospital.text.isEmpty) {
      for (final line in lines) {
        final looksLikeClinic =
            line.contains('医院') || line.contains('诊所') || line.contains('宠物');
        if (looksLikeClinic && line.length <= 40) {
          _hospital.text = line.length > 40 ? line.substring(0, 40) : line;
          break;
        }
      }
    }
    final dateMatch =
        RegExp(r'(20\d{2})[-年/.](\d{1,2})[-月/.](\d{1,2})').firstMatch(_rawText);
    if (dateMatch != null) {
      final parsed = DateTime.tryParse(
        '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}',
      );
      if (parsed != null) _date = parsed;
    }
    if (_indicators.isEmpty) {
      _indicators.addAll(_parseIndicators(lines));
    }
  }

  List<_IndicatorDraft> _parseIndicators(List<String> lines) {
    final out = <_IndicatorDraft>[];
    final seen = <String>{};
    for (final line in lines) {
      if (out.length >= 12) break;
      if (line.contains('日期') ||
          line.contains('电话') ||
          line.contains('编号') ||
          line.contains('单号') ||
          line.contains('身份证')) {
        continue;
      }
      final valueMatch = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(line);
      if (valueMatch == null) continue;
      final name = line
          .substring(0, valueMatch.start)
          .replaceAll(RegExp(r'[\s:：]+$'), '')
          .trim();
      if (name.isEmpty || name.length > 24 || seen.contains(name)) continue;
      if (!RegExp(r'[一-龥A-Za-z]').hasMatch(name)) continue;
      final rest = line.substring(valueMatch.end).trim();
      final unit = RegExp(r'^([a-zA-Z%/μ]+)').firstMatch(rest)?.group(1) ?? '';
      final refMatch =
          RegExp(r'(\d+(?:\.\d+)?)\s*[-~—]\s*(\d+(?:\.\d+)?)').firstMatch(line);
      seen.add(name);
      out.add(_IndicatorDraft(
        name: name,
        value: '${valueMatch.group(0)}${unit.isEmpty ? '' : ' $unit'}',
        reference:
            refMatch == null ? '' : '${refMatch.group(1)}-${refMatch.group(2)}',
      ));
    }
    return out;
  }

  Future<void> _save() async {
    if (_image == null || _rawText.isEmpty) {
      setState(() => _error = '请先拍照并完成识别');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final indicators = _indicators
        .where((i) => i.name.text.trim().isNotEmpty)
        .map((i) => i.toJson())
        .toList(growable: false);
    final hospital = _hospital.text.trim();
    final payload = <String, dynamic>{
      'rawText': _rawText,
      'indicators': indicators,
      if (_conclusion.text.trim().isNotEmpty)
        'conclusion': _conclusion.text.trim(),
      if (_advice.text.trim().isNotEmpty) 'advice': _advice.text.trim(),
    };
    try {
      final api = ref.read(apiClientProvider);
      final record = await api.createRecord(widget.pet.id, {
        'type': 'checkup',
        'occurredAt': DateFormat('yyyy-MM-dd').format(_date),
        'title': hospital.isEmpty ? '化验单' : '化验单 · $hospital',
        'payload': payload,
        'hospital': hospital,
        'doctor': '',
        'nextDueAt': '',
        'source': 'ocr',
      });
      try {
        await api.uploadAttachment(widget.pet.id, _image!.path,
            recordId: record.id);
      } catch (_) {
        // The record is still valuable if the original image upload fails.
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, '化验单已写入体检记录');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.pet.name} · 化验单识别'),
        actions: [
          if (_rawText.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_image == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.document_scanner_outlined,
                        size: 56, color: Colors.black26),
                    const SizedBox(height: 12),
                    const Text('拍一张化验单或疫苗本'),
                    const SizedBox(height: 6),
                    const Text(
                      '图片只在本机识别，不会上传到服务端之外的任何地方；'
                      '确认前不会写入档案。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black45, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _pick(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('拍照'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('相册'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  Image.file(File(_image!.path),
                      height: 220, width: double.infinity, fit: BoxFit.cover),
                  if (_recognizing)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.refresh),
                      tooltip: '重新拍照',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBE9E7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFF9B2C2C), fontSize: 13)),
            ),
          if (_recognizing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('正在本机识别文字…', style: TextStyle(color: Colors.black54)),
            ),
          if (_rawText.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('基础信息',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hospital,
                      decoration:
                          const InputDecoration(labelText: '医院/机构（可编辑）'),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '化验日期',
                          prefixIcon: Icon(Icons.event_outlined),
                        ),
                        child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('指标（低置信请核对）',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(
                              () => _indicators.add(_IndicatorDraft())),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加'),
                        ),
                      ],
                    ),
                    if (_indicators.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '没有自动解析出指标，可以在下方原文中查看并手动添加。',
                          style: TextStyle(color: Colors.black45, fontSize: 13),
                        ),
                      ),
                    for (var i = 0; i < _indicators.length; i++)
                      _IndicatorRow(
                        draft: _indicators[i],
                        onRemove: () {
                          setState(() => _indicators.removeAt(i).dispose());
                        },
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('结论与建议（可选）',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _conclusion,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '医生结论'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _advice,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '建议'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('识别原文'),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F3EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _rawText,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认写入体检记录'),
            ),
            const SizedBox(height: 8),
            const Text(
              '确认后才会写入；识别结果仅供整理，不作为诊断依据。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  const _IndicatorRow({
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  final _IndicatorDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color:
            draft.abnormal ? const Color(0xFFFDF0DC) : const Color(0xFFF9F6F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: draft.name,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '项目',
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.value,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '结果',
                    filled: false,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                tooltip: '删除',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.reference,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '参考范围',
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (draft.abnormal)
                const Text('超出参考范围',
                    style: TextStyle(color: Color(0xFF8A4B08), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
