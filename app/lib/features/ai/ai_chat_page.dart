import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/ai_capture.dart';
import '../../core/toast.dart';
import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_safety.dart';
import '../../core/ai/ai_sessions.dart';
import '../../core/api_client.dart';
import '../../core/chat_images.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../pets/pet_form_page.dart';
import '../records/record_form_page.dart';
import 'ai_settings_page.dart';
import 'assistant_drawer.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({
    super.key,
    this.pet,
    this.session,
    this.global = false,
  });

  /// Focused pet for the per-pet entry; null for the account-wide assistant.
  final Pet? pet;
  final AiSession? session;
  final bool global;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  late Pet? _pet = widget.pet;
  late AiSession _session = widget.session ?? _newSession(widget.pet);
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<Pet> _pets = const [];
  List<PetProfileContext> _contexts = const [];
  List<HealthRecord> _records = const [];
  List<WeightRecord> _weights = const [];
  List<AiProviderConfig> _providers = const [];
  AiProviderConfig? _config;
  String _apiKey = '';
  bool _configLoaded = false;
  String _streamingText = '';
  bool _sending = false;
  String? _error;
  CancelToken? _cancelToken;
  bool _showRedCard = false;
  List<CaptureEvent> _pendingCaptures = const [];
  final List<String> _pendingImages = [];
  bool _pickingImages = false;

  bool get _isGlobal => widget.global;
  String get _userId => ref.read(sessionProvider).user?.id ?? 'anonymous';

  static AiSession _newSession(Pet? pet) => AiSession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        petId: pet?.id ?? '',
        petName: pet?.name ?? '全部宠物',
        title: '新对话',
        updatedAt: DateTime.now().toIso8601String(),
        messages: [],
      );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    for (final path in _pendingImages) {
      ChatImages.delete(path);
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Resolve the provider first so the UI never flashes the "not configured"
    // banner while pet contexts are still loading.
    await _loadConfig();
    if (mounted) setState(() {});
    try {
      final api = ref.read(apiClientProvider);
      final pets = await api.listPets();
      _pets = pets;
      final focused = _pet;
      if (_isGlobal || focused == null) {
        _contexts = await _loadContexts(api, pets);
      } else {
        final contexts = await _loadContexts(api, [focused]);
        _contexts = contexts;
        if (contexts.isNotEmpty) {
          _records = contexts.first.records;
          _weights = contexts.first.weights;
        }
      }
    } catch (_) {
      // Context is best-effort; chat can still work without it.
    }
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  Future<List<PetProfileContext>> _loadContexts(
    ApiClient api,
    List<Pet> pets,
  ) async {
    final contexts = <PetProfileContext>[];
    for (final pet in pets.take(6)) {
      try {
        final results = await Future.wait([
          api.listRecords(pet.id),
          api.listWeights(pet.id),
        ]);
        contexts.add(PetProfileContext(
          pet: pet,
          records: results[0] as List<HealthRecord>,
          weights: results[1] as List<WeightRecord>,
        ));
      } catch (_) {
        contexts.add(PetProfileContext(
          pet: pet,
          records: const [],
          weights: const [],
        ));
      }
    }
    return contexts;
  }

  Future<void> _loadConfig() async {
    final configs = await AiConfigStore.load(_userId);
    final usable = <AiProviderConfig>[];
    final keys = <String, String>{};
    for (final config in configs) {
      final key = await AiConfigStore.apiKey(_userId, config.id);
      if (key != null && key.isNotEmpty) {
        usable.add(config);
        keys[config.id] = key;
      }
    }
    _providers = usable;
    AiProviderConfig? picked;
    if (_session.providerId.isNotEmpty) {
      for (final config in usable) {
        if (config.id == _session.providerId) picked = config;
      }
    }
    if (picked == null) {
      for (final config in usable) {
        if (config.isDefault) picked = config;
      }
    }
    if (picked == null && usable.isNotEmpty) picked = usable.first;
    _configLoaded = true;
    if (picked == null) {
      _config = null;
      _apiKey = '';
      _session.providerId = '';
      return;
    }
    _config = picked;
    _apiKey = keys[picked.id]!;
    _session.providerId = picked.id;
  }

  Future<void> _selectProvider(AiProviderConfig config) async {
    final key = await AiConfigStore.apiKey(_userId, config.id) ?? '';
    if (key.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _config = config;
      _apiKey = key;
      _session.providerId = config.id;
    });
    await AiSessionStore.upsert(_userId, _session);
    _snack('本会话使用 ${config.name} · ${config.model}');
  }

  Future<void> _reloadContext() async {
    try {
      final api = ref.read(apiClientProvider);
      final focused = _pet;
      if (_isGlobal || focused == null) {
        _contexts = await _loadContexts(api, _pets);
      } else {
        final contexts = await _loadContexts(api, [focused]);
        _contexts = contexts;
        if (contexts.isNotEmpty) {
          _records = contexts.first.records;
          _weights = contexts.first.weights;
        }
      }
    } catch (_) {
      // Ignore.
    }
  }

  void _startNewChat() {
    _cancelToken?.cancel();
    setState(() {
      _session = _newSession(_isGlobal ? null : _pet);
      _pendingCaptures = const [];
      _pendingImages.clear();
      _streamingText = '';
      _error = null;
      _showRedCard = false;
      _sending = false;
    });
    _input.clear();
    _reloadContext();
  }

  Future<void> _openSession(AiSession session) async {
    Pet? matched;
    for (final pet in _pets) {
      if (pet.id == session.petId) matched = pet;
    }
    setState(() {
      _session = session;
      _pet = matched;
      _pendingCaptures = const [];
      _streamingText = '';
      _error = null;
    });
    await _reloadContext();
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  Future<void> _addPet() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PetFormPage()),
    );
    try {
      _pets = await ref.read(apiClientProvider).listPets();
    } catch (_) {
      // Keep the previous list when the refresh fails.
    }
    await _reloadContext();
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiSettingsPage()),
    );
    await _loadConfig();
    if (mounted) setState(() {});
  }

  Future<void> _send({String? retryText, List<String>? retryImages}) async {
    if (_sending) return;
    final isRetry = retryText != null || retryImages != null;
    final text = (retryText ?? _input.text).trim();
    final images = isRetry
        ? List<String>.from(retryImages ?? const [])
        : List<String>.from(_pendingImages);
    if (text.isEmpty && images.isEmpty) return;
    if (!_configLoaded) {
      await _loadConfig();
      if (!mounted) return;
      setState(() {});
    }
    if (_config == null || _apiKey.isEmpty) {
      _snack('还没有可用的 AI 服务，请先在设置中配置 Key');
      await _openSettings();
      return;
    }
    if (images.isNotEmpty && _config?.supportsVision != true) {
      _snack('当前服务商未开启视觉能力，请在 AI 设置中开启或切换支持图片的模型');
      return;
    }
    _input.clear();
    if (!isRetry) _pendingImages.clear();
    setState(() {
      _sending = true;
      _error = null;
      _streamingText = '';
      _showRedCard = false;
    });
    final risk = assessRisk(text);
    if (risk.isRed) {
      setState(() => _showRedCard = true);
    }
    final userMessage = AiStoredMessage(
      role: 'user',
      content: text,
      riskLevel: 'l${risk.level.index}',
      createdAt: DateTime.now().toIso8601String(),
      images: images,
    );
    _session.messages.add(userMessage);
    if (_session.title == '新对话') {
      _session.title = text.isNotEmpty
          ? (text.length > 18 ? '${text.substring(0, 18)}…' : text)
          : '图片咨询';
    }
    await AiSessionStore.upsert(_userId, _session);
    _scrollToBottom();

    String system;
    if (_isGlobal) {
      system = buildGlobalSystemPrompt(_contexts);
    } else if (_pet != null) {
      system = buildSystemPrompt(
        pet: _pet!,
        records: _records,
        weights: _weights,
      );
    } else if (_contexts.isNotEmpty) {
      system = buildGlobalSystemPrompt(_contexts);
    } else {
      system = '你是宠物照护助手。用中文简洁回答，不确诊、不开药、不给剂量；'
          '紧急症状建议立即就医。';
    }
    final history = _session.messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();
    final start = history.length > 20 ? history.length - 20 : 0;
    final recent = history.sublist(start);
    var lastUserIndex = -1;
    for (var i = 0; i < recent.length; i++) {
      if (recent[i].role == 'user') lastUserIndex = i;
    }
    final messages = [
      for (var i = 0; i < recent.length; i++)
        AiMessage(
          role: recent[i].role,
          content: recent[i].content,
          imagePaths: i == lastUserIndex ? recent[i].images : const <String>[],
        ),
    ];
    final buffer = StringBuffer();
    var answer = '';
    _cancelToken = CancelToken();

    // Capture facts from the user's own words. Local rules are deterministic
    // and free; the model is only asked when local rules found nothing.
    // A bare "记下吧" command has no facts, so use the previous user message.
    final capturePets = _isGlobal || _pet == null ? _pets : <Pet>[_pet!];
    var captureText = text;
    var localCaptures =
        isRetry ? <CaptureEvent>[] : parseLocalCaptures(text, capturePets);
    if (!isRetry && localCaptures.isEmpty && isRecordCommand(text)) {
      final previous = previousUserTextForCapture(_session.messages);
      if (previous != null) {
        captureText = previous;
        localCaptures = parseLocalCaptures(captureText, capturePets);
      }
    }
    Future<List<CaptureEvent>>? fallbackCaptures;
    if (!isRetry &&
        localCaptures.isEmpty &&
        (shouldTryAiCapture(captureText, capturePets) || isRecordCommand(text)) &&
        _config != null) {
      fallbackCaptures = () async {
        try {
          return await extractCapturesWithAi(
            client: AiClient(),
            config: _config!,
            apiKey: _apiKey,
            pets: capturePets,
            text: captureText,
            cancelToken: _cancelToken,
          );
        } catch (_) {
          return <CaptureEvent>[];
        }
      }();
    }
    try {
      await for (final delta in AiClient().stream(
        config: _config!,
        apiKey: _apiKey,
        systemPrompt: system,
        messages: messages,
        cancelToken: _cancelToken,
      )) {
        buffer.write(delta);
        if (!mounted) return;
        setState(() => _streamingText = buffer.toString());
        _scrollToBottom();
      }
      if (!mounted) return;
      answer = buffer.toString().trim();
      if (answer.isEmpty) {
        throw AiException('模型没有返回内容，请重试');
      }
      final answerRisk = assessRisk(text, aiText: answer);
      _session.messages.add(AiStoredMessage(
        role: 'assistant',
        content: answer,
        riskLevel: 'l${answerRisk.level.index}',
        createdAt: DateTime.now().toIso8601String(),
      ));
      await AiSessionStore.upsert(_userId, _session);
      if (!mounted) return;
      setState(() {
        _streamingText = '';
        _sending = false;
        _showRedCard = answerRisk.isRed;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _finishPartial(buffer.toString(), text);
        return;
      }
      _fail(e.toString());
    } on AiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('AI 请求失败，请检查网络或模型配置');
    } finally {
      if (!isRetry) {
        final wrote = await _handleCaptures(localCaptures, fallbackCaptures);
        if (!wrote && answer.isNotEmpty && _claimsWrite(answer)) {
          await _appendCaptureDisclaimer(answer);
        }
      }
    }
  }

  static final _writeClaimPattern = RegExp(
    r'(已(记录|保存|归档|写入|添加)|记下了|帮你记|记录好了|存好了|已经记|写进(了)?档案|归档到)',
  );

  bool _claimsWrite(String text) => _writeClaimPattern.hasMatch(text);

  Future<void> _appendCaptureDisclaimer(String answer) async {
    const note = '\n\n（提示：本条尚未写入档案，请以界面上的「已自动记录」卡片为准；'
        '如需保存，请到对应宠物的成长/健康记录页补记。）';
    for (var i = _session.messages.length - 1; i >= 0; i--) {
      final message = _session.messages[i];
      if (message.role == 'assistant' && message.content == answer) {
        if (message.content.contains('本条尚未写入档案')) return;
        message.content = '${message.content}$note';
        await AiSessionStore.upsert(_userId, _session);
        if (mounted) setState(() {});
        return;
      }
    }
  }

  Future<bool> _handleCaptures(
    List<CaptureEvent> local,
    Future<List<CaptureEvent>>? fallback,
  ) async {
    var events = local;
    if (events.isEmpty && fallback != null) {
      try {
        events = await fallback;
      } catch (_) {
        events = const [];
      }
    }
    if (events.isEmpty) return false;
    final pets = _isGlobal || _pet == null ? _pets : <Pet>[_pet!];
    final resolved = <CaptureEvent>[];
    final pending = <CaptureEvent>[];
    final blocked = <String>{};
    for (final event in events) {
      if (event.kind == 'pet') {
        resolved.add(event);
      } else if (event.petId.isNotEmpty) {
        Pet? target;
        for (final pet in pets) {
          if (pet.id == event.petId) target = pet;
        }
        if (target != null && !canAutoWrite(target)) {
          blocked.add(target.name);
        } else {
          resolved.add(event);
        }
      } else if (pets.length == 1) {
        if (!canAutoWrite(pets.first)) {
          blocked.add(pets.first.name);
        } else {
          event.petId = pets.first.id;
          event.petName = pets.first.name;
          resolved.add(event);
        }
      } else {
        pending.add(event);
      }
    }
    final api = ref.read(apiClientProvider);
    final captures = <AiCapture>[];
    for (final event in resolved) {
      try {
        captures.add(await applyCapture(api, event));
      } catch (e) {
        _snack('自动记录失败：$e');
      }
    }
    if (captures.isNotEmpty) {
      _session.messages.add(AiStoredMessage(
        role: 'capture',
        content: '已自动记录',
        captures: captures,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await AiSessionStore.upsert(_userId, _session);
      if (mounted) {
        if (captures.any((c) => c.kind == 'pet')) {
          await _reloadPets();
        } else {
          await _reloadContext();
        }
      }
    }
    if (!mounted) return captures.isNotEmpty;
    if (blocked.isNotEmpty) {
      _snack('「${blocked.join('、')}」是共享只读宠物，无法自动记录');
    }
    setState(() => _pendingCaptures = pending);
    _scrollToBottom();
    return captures.isNotEmpty;
  }

  Future<void> _reloadPets() async {
    try {
      _pets = await ref.read(apiClientProvider).listPets();
    } catch (_) {
      // Keep the previous list if the refresh fails.
    }
    await _reloadContext();
  }

  Future<void> _applyPendingTo(Pet pet) async {
    final events = _pendingCaptures;
    if (events.isEmpty) return;
    if (!canAutoWrite(pet)) {
      _snack('「${pet.name}」是共享只读宠物，无法自动记录');
      return;
    }
    setState(() => _pendingCaptures = const []);
    final api = ref.read(apiClientProvider);
    final captures = <AiCapture>[];
    for (final event in events) {
      event.petId = pet.id;
      event.petName = pet.name;
      try {
        captures.add(await applyCapture(api, event));
      } catch (e) {
        _snack('自动记录失败：$e');
      }
    }
    if (captures.isNotEmpty) {
      _session.messages.add(AiStoredMessage(
        role: 'capture',
        content: '已自动记录',
        captures: captures,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await AiSessionStore.upsert(_userId, _session);
      if (mounted) {
        await _reloadContext();
        setState(() {});
      }
      _scrollToBottom();
    }
  }

  Future<void> _undoCaptures(AiStoredMessage message) async {
    final api = ref.read(apiClientProvider);
    var changed = false;
    for (final capture in message.captures) {
      if (capture.undone) continue;
      try {
        await undoCapture(api, capture);
        capture.undone = true;
        changed = true;
      } catch (e) {
        _snack('撤销失败：$e');
      }
    }
    if (!changed) return;
    await AiSessionStore.upsert(_userId, _session);
    if (mounted) {
      if (message.captures.any((c) => c.kind == 'pet')) {
        await _reloadPets();
      } else {
        await _reloadContext();
      }
      setState(() {});
    }
  }

  void _finishPartial(String partial, String question) {
    if (!mounted) return;
    final text = partial.trim();
    if (text.isNotEmpty) {
      _session.messages.add(AiStoredMessage(
        role: 'assistant',
        content: '$text\n\n（已取消生成）',
        riskLevel: 'l${assessRisk(question, aiText: text).level.index}',
        createdAt: DateTime.now().toIso8601String(),
      ));
      AiSessionStore.upsert(_userId, _session);
    }
    setState(() {
      _streamingText = '';
      _sending = false;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _streamingText = '';
      _sending = false;
      _error = message;
    });
  }

  void _stop() {
    _cancelToken?.cancel();
  }

  Future<void> _retry() async {
    final lastUser = _session.messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => AiStoredMessage(role: 'user', content: ''),
    );
    if (lastUser.content.isEmpty && lastUser.images.isEmpty) return;
    if (_session.messages.isNotEmpty &&
        _session.messages.last.role == 'assistant') {
      _session.messages.removeLast();
    }
    await _send(
      retryText: lastUser.content,
      retryImages: lastUser.images,
    );
  }

  Future<void> _pickImages() async {
    if (_pickingImages) return;
    if (!_configLoaded) {
      await _loadConfig();
      if (!mounted) return;
      setState(() {});
    }
    final config = _config;
    if (config == null) {
      _snack('请先配置 AI 服务');
      await _openSettings();
      return;
    }
    if (!config.supportsVision) {
      _snack('当前服务商未开启视觉能力，请在 AI 设置中开启或切换支持图片的模型');
      return;
    }
    if (_pendingImages.length >= 4) {
      _snack('每条消息最多 4 张图片');
      return;
    }
    setState(() => _pickingImages = true);
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 80,
        maxWidth: 1920,
      );
      for (final file in picked) {
        if (_pendingImages.length >= 4) break;
        final path = await ChatImages.persist(file.path);
        _pendingImages.add(path);
      }
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _snack('选择图片失败：$e');
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  void _removePendingImage(String path) {
    setState(() => _pendingImages.remove(path));
    ChatImages.delete(path);
  }

  void _viewImage(String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('图片已不存在'),
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
  }

  Future<void> _switchPet(Pet pet) async {
    if (_pet != null && pet.id == _pet!.id) return;
    setState(() {
      _pet = pet;
      _session = _newSession(pet);
      _streamingText = '';
      _error = null;
      _showRedCard = false;
    });
    await _reloadContext();
    if (mounted) setState(() {});
  }

  Future<void> _showHistory() async {
    final sessions = await AiSessionStore.load(_userId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新对话'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _session = _newSession(_pet));
              },
            ),
            const Divider(height: 1),
            if (sessions.isEmpty)
              const ListTile(enabled: false, title: Text('还没有历史会话')),
            for (final session
                in sessions.where((s) => _isGlobal || s.petId == _pet?.id))
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(session.title, maxLines: 1),
                subtitle: Text(
                  '${session.petName} · ${session.updatedAt.split('T').first}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    await AiSessionStore.delete(_userId, session.id);
                    sessions.removeWhere((s) => s.id == session.id);
                    setSheetState(() {});
                  },
                ),
                onTap: () async {
                  Navigator.pop(context);
                  Pet? matched;
                  for (final p in _pets) {
                    if (p.id == session.petId) matched = p;
                  }
                  setState(() {
                    _session = session;
                    _pet = matched;
                  });
                  await _reloadContext();
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _extractRecord() async {
    final pet = _pet;
    if (pet == null) {
      _snack('请从宠物详情进入再使用记录草稿');
      return;
    }
    if (_config == null || _apiKey.isEmpty) {
      _snack('请先配置 AI 服务');
      return;
    }
    final conversation = _session.messages
        .map((m) => '${m.role == 'user' ? '用户' : '助手'}：${m.content}')
        .join('\n');
    if (conversation.trim().isEmpty) {
      _snack('先聊几句再提取记录');
      return;
    }
    setState(() => _sending = true);
    _cancelToken = CancelToken();
    try {
      final raw = await AiClient().complete(
        config: _config!,
        apiKey: _apiKey,
        systemPrompt: buildRecordExtractionPrompt(pet),
        messages: [
          AiMessage(role: 'user', content: conversation),
        ],
        cancelToken: _cancelToken,
      );
      final draft = _parseDraft(raw);
      if (!mounted) return;
      setState(() => _sending = false);
      if (draft == null) {
        _snack('没有成功提取记录，可以打开手动表单');
        _openManualRecord();
        return;
      }
      await _confirmDraft(draft);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      if (CancelToken.isCancel(e)) {
        _snack('已取消提取');
      } else {
        _snack('提取失败，可以打开手动表单');
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _snack('提取失败，可以打开手动表单');
    }
  }

  Map<String, dynamic>? _parseDraft(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final json = jsonDecode(raw.substring(start, end + 1));
      if (json is! Map<String, dynamic>) return null;
      const types = {
        'vaccine',
        'deworming',
        'checkup',
        'medical',
        'medication',
        'grooming',
        'other',
      };
      final type = (json['type'] as String?) ?? '';
      final occurred = (json['occurredAt'] as String?) ?? '';
      final title = (json['title'] as String?) ?? '';
      if (!types.contains(type) ||
          DateTime.tryParse(occurred) == null ||
          title.trim().isEmpty) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmDraft(Map<String, dynamic> draft) async {
    final pet = _pet;
    if (pet == null) return;
    final type = draft['type'] as String;
    final payload = (draft['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 记录草稿'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('确认后才会写入档案。'),
              const SizedBox(height: 12),
              _draftRow('类型', _typeLabel(type)),
              _draftRow('日期', (draft['occurredAt'] as String?) ?? ''),
              _draftRow('标题', (draft['title'] as String?) ?? ''),
              if ((draft['hospital'] as String?)?.isNotEmpty == true)
                _draftRow('医院', draft['hospital'] as String),
              if ((draft['nextDueAt'] as String?)?.isNotEmpty == true)
                _draftRow('下次', draft['nextDueAt'] as String),
              for (final entry in payload.entries)
                if (entry.value != null &&
                    entry.value.toString().trim().isNotEmpty)
                  _draftRow(entry.key, entry.value.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              _openManualRecord();
            },
            child: const Text('手动修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('写入记录'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).createRecord(pet.id, {
        'type': type,
        'occurredAt': draft['occurredAt'],
        'title': draft['title'],
        'payload': payload,
        'hospital': (draft['hospital'] as String?) ?? '',
        'doctor': (draft['doctor'] as String?) ?? '',
        'nextDueAt': (draft['nextDueAt'] as String?) ?? '',
        'source': 'ai',
      });
      if (!mounted) return;
      _snack('已写入记录，提醒会按下次日期自动计算');
      await _reloadContext();
    } on ApiException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    }
  }

  void _openManualRecord() {
    final pet = _pet;
    if (pet == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecordFormPage(pet: pet)),
    );
  }

  String _typeLabel(String type) => switch (type) {
        'vaccine' => '疫苗',
        'deworming' => '驱虫',
        'checkup' => '体检',
        'medical' => '病历',
        'medication' => '用药',
        'grooming' => '洗护',
        'diet' => '饮食',
        _ => '其他',
      };

  Widget _draftRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('已复制');
  }

  void _feedback(AiStoredMessage message, int value) {
    setState(() {
      message.feedback = message.feedback == value ? 0 : value;
    });
    AiSessionStore.upsert(_userId, _session);
    _snack(message.feedback == 1
        ? '已标记为有用'
        : message.feedback == -1
            ? '已标记为无用，我们会继续改进'
            : '已取消反馈');
  }

  void _snack(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  Widget _inputIcon(
    IconData icon, {
    required String tooltip,
    VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: color,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _isGlobal
          ? AssistantDrawer(
              currentSessionId: _session.id,
              onNewChat: _startNewChat,
              onOpenSession: _openSession,
            )
          : null,
      appBar: AppBar(
        centerTitle: _isGlobal,
        title: _isGlobal
            ? const Text(
                '喵了个咪 AI',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 助手 · ${_pet?.name ?? ''}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    '当前宠物：${_pet?.name ?? ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
        actions: [
          if (_isGlobal)
            IconButton(
              tooltip: '新对话',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _startNewChat,
            ),
          PopupMenuButton<String>(
            tooltip: '切换模型服务商',
            icon: const Icon(Icons.memory),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            color: Colors.white,
            elevation: 8,
            offset: const Offset(0, 6),
            constraints: const BoxConstraints(minWidth: 210),
            onSelected: (value) async {
              if (value == 'settings') {
                await _openSettings();
                return;
              }
              for (final config in _providers) {
                if (config.id == value) {
                  await _selectProvider(config);
                  return;
                }
              }
            },
            itemBuilder: (context) => [
              for (final config in _providers)
                CheckedPopupMenuItem(
                  value: config.id,
                  checked: config.id == _config?.id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(config.name),
                      Text(
                        config.model,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              if (_providers.isEmpty)
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('还没有可用的服务商'),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'settings',
                child: Text('AI 服务设置'),
              ),
            ],
          ),
          if (!_isGlobal && _pets.length > 1)
            IconButton(
              tooltip: '切换宠物',
              icon: const Icon(Icons.pets),
              onPressed: () async {
                final pet = await showModalBottomSheet<Pet>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => ListView(
                    children: [
                      for (final p in _pets)
                        ListTile(
                          leading: Text(p.species == 'cat' ? '🐱' : '🐶'),
                          title: Text(p.name),
                          subtitle:
                              Text(p.breed.isEmpty ? p.speciesLabel : p.breed),
                          onTap: () => Navigator.pop(context, p),
                        ),
                    ],
                  ),
                );
                if (pet != null) await _switchPet(pet);
              },
            ),
          if (!_isGlobal)
            IconButton(
              tooltip: '历史会话',
              icon: const Icon(Icons.history),
              onPressed: _showHistory,
            ),
          if (!_isGlobal)
            IconButton(
              tooltip: 'AI 设置',
              icon: const Icon(Icons.tune),
              onPressed: _openSettings,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_configLoaded && _config == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFFDF0DC),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '还没有配置 AI 服务。Key 只保存在本机，不会上传服务端。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A4B08)),
                    ),
                  ),
                  TextButton(
                    onPressed: _openSettings,
                    child: const Text('去配置'),
                  ),
                ],
              ),
            ),
          if (_showRedCard)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFBEAE9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE7B4AE)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🚨 紧急就医提示',
                    style: TextStyle(
                      color: Color(0xFF9B2C2C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '你的描述包含紧急红旗症状：请立即联系或前往宠物医院，'
                    '不要等待在线建议。若在途中，保持宠物安静并避免自行喂药。',
                    style: TextStyle(
                      color: Color(0xFF9B2C2C),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _session.messages.isEmpty && _streamingText.isEmpty
                ? _emptyState()
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    children: [
                      for (final message in _session.messages) _bubble(message),
                      if (_streamingText.isNotEmpty) _streamingBubble(),
                      if (_error != null) _errorBanner(),
                    ],
                  ),
          ),
          if (_session.messages.isNotEmpty && !_isGlobal && _pet != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextButton.icon(
                onPressed: _sending ? null : _extractRecord,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('把这段对话转成记录草稿'),
              ),
            ),
          if (_pendingCaptures.isNotEmpty) _pendingCaptureCard(),
          if (_pendingImages.isNotEmpty) _pendingImagesStrip(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE9E1D7)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _inputIcon(
                      Icons.add_photo_alternate_outlined,
                      tooltip: '发送图片',
                      onPressed: _pickingImages ? null : _pickImages,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                        decoration: const InputDecoration(
                          hintText: '发消息…',
                          border: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _sending
                          ? IconButton.filled(
                              onPressed: _stop,
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              constraints: const BoxConstraints.tightFor(
                                  width: 40, height: 40),
                              icon: const Icon(Icons.stop),
                              tooltip: '停止生成',
                            )
                          : IconButton.filled(
                              onPressed: () => _send(),
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              constraints: const BoxConstraints.tightFor(
                                  width: 40, height: 40),
                              icon: const Icon(Icons.arrow_upward),
                              tooltip: '发送',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingImagesStrip() {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final path = _pendingImages[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => _viewImage(path),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(path),
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 76,
                      height: 76,
                      color: const Color(0xFFF1E4D8),
                      child: const Icon(Icons.broken_image, size: 20),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  onTap: () => _removePendingImage(path),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF2F2A26),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child:
                        const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pendingCaptureCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAD9B5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '检测到可以记录的内容，要记到哪只宠物？',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _pendingCaptures.map((e) => e.label).join('、'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final pet in _pets)
                FilledButton.tonal(
                  onPressed: () => _applyPendingTo(pet),
                  child: Text(pet.name),
                ),
              TextButton(
                onPressed: () => setState(() => _pendingCaptures = const []),
                child: const Text('忽略'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final userName = ref.read(sessionProvider).user?.displayName ?? '';
    final prompts = _isGlobal
        ? const [
            '多久洗一次澡比较合适？',
            '疫苗和驱虫要怎么安排？',
            '它能吃哪些人类食物？',
            '它晚上总闹怎么办？',
          ]
        : const [
            '最近食欲下降，需要观察什么？',
            '下次驱虫是什么时候？',
            '带它出门需要注意什么？',
          ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      children: [
        Text(
          _isGlobal
              ? (userName.isEmpty ? '你好' : '你好，$userName')
              : '咨询「${_pet?.name ?? ''}」',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _isGlobal
              ? '我是你的宠物助手。可以聊喂养和健康，也可以直接说一句，'
                  '我会顺手记进宠物档案。'
              : '回答会结合宠物档案（年龄、品种、疫苗、体重、病史）。\n'
                  '你陈述的体重、症状、换粮也会自动记录。',
          style:
              const TextStyle(color: Colors.black54, fontSize: 13, height: 1.6),
        ),
        if (_isGlobal && _pets.isEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE9E1D7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '还没有宠物档案',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  '先建一份档案，回答会更贴合它的年龄、品种和病史。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _addPet,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加宠物'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        const Text(
          '可以这样问我',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in prompts)
              ActionChip(
                label: Text(prompt),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE9E1D7)),
                shape: const StadiumBorder(),
                onPressed: () {
                  _input.text = prompt;
                  _send();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(AiStoredMessage message) {
    if (message.isCapture) {
      final active = message.captures.where((c) => !c.undone).toList();
      final petsOnly = message.captures.isNotEmpty &&
          message.captures.every((c) => c.kind == 'pet');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3E7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC9DDC1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: Color(0xFF3E6B4F)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      petsOnly ? '已自动添加宠物' : '已自动记录',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3E6B4F),
                      ),
                    ),
                    const SizedBox(height: 3),
                    for (final capture in message.captures)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          capture.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: capture.undone
                                ? Colors.black38
                                : Colors.black87,
                            decoration: capture.undone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (active.isNotEmpty)
                TextButton(
                  onPressed: () => _undoCaptures(message),
                  child: const Text('撤销'),
                ),
            ],
          ),
        ),
      );
    }
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFF1E4D8),
              child: Text('🐾', style: TextStyle(fontSize: 14)),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment:
                          isUser ? WrapAlignment.end : WrapAlignment.start,
                      children: [
                        for (final path in message.images)
                          GestureDetector(
                            onTap: () => _viewImage(path),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 120,
                                  height: 120,
                                  color: const Color(0xFFF1E4D8),
                                  child: const Icon(Icons.broken_image,
                                      size: 24, color: Colors.black38),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (message.content.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF8B5E3C) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        height: 1.5,
                        fontSize: 14,
                      ),
                    ),
                  ),
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('AI 生成，仅供参考',
                            style:
                                TextStyle(fontSize: 10, color: Colors.black38)),
                        const SizedBox(width: 8),
                        _iconAction(
                            Icons.copy, '复制', () => _copy(message.content)),
                        _iconAction(
                          message.feedback == 1
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          '有用',
                          () => _feedback(message, 1),
                        ),
                        _iconAction(
                          message.feedback == -1
                              ? Icons.thumb_down
                              : Icons.thumb_down_outlined,
                          '无用',
                          () => _feedback(message, -1),
                        ),
                        if (message == _session.messages.last)
                          _iconAction(Icons.refresh, '重试', _retry),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _streamingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFF1E4D8),
            child: Text('🐾', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '$_streamingText▍',
                style: const TextStyle(height: 1.5, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE9E7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(_error!,
                style: const TextStyle(color: Color(0xFF9B2C2C), fontSize: 13)),
          ),
          TextButton(onPressed: _retry, child: const Text('重试')),
          TextButton(
            onPressed: () => setState(() => _error = null),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
    );
  }
}
