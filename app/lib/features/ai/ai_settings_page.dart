import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_config.dart';
import '../../core/session.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  List<AiProviderConfig> _configs = const [];
  final Map<String, String> _keyHints = {};
  bool _loading = true;

  String get _userId => ref.read(sessionProvider).user?.id ?? 'anonymous';

  List<AiProviderConfig> get _configured =>
      _configs.where((c) => _keyHints.containsKey(c.id)).toList();

  AiProviderConfig? get _active {
    final configured = _configured;
    if (configured.isEmpty) return null;
    for (final config in configured) {
      if (config.isDefault) return config;
    }
    return configured.first;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var configs = await AiConfigStore.load(_userId);
    final hints = <String, String>{};
    for (final config in configs) {
      final key = await AiConfigStore.apiKey(_userId, config.id);
      if (key != null && key.isNotEmpty) {
        hints[config.id] =
            key.length <= 8 ? '已保存' : '已保存 · 末 4 位 ${key.substring(key.length - 4)}';
      }
    }
    final configured =
        configs.where((c) => hints.containsKey(c.id)).toList();
    if (configured.isNotEmpty) {
      AiProviderConfig active = configured.first;
      for (final config in configured) {
        if (config.isDefault) active = config;
      }
      final defaults = configs.where((c) => c.isDefault).toList();
      final normalized = defaults.length != 1 || defaults.first.id != active.id;
      if (normalized) {
        configs = configs
            .map((c) => c.copyWith(isDefault: c.id == active.id))
            .toList(growable: false);
        await AiConfigStore.save(_userId, configs);
      }
    }
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _keyHints
        ..clear()
        ..addAll(hints);
      _loading = false;
    });
  }

  Future<void> _edit(AiProviderConfig config) async {
    final baseUrl = TextEditingController(text: config.baseUrl);
    final model = TextEditingController(text: config.model);
    final name = TextEditingController(text: config.name);
    final key = TextEditingController();
    var makeDefault = config.isDefault || _configured.isEmpty;
    var supportsVision = config.supportsVision;
    var loadingModels = false;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('配置 ${config.name}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '显示名称'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      helperText: config.kind == 'anthropic'
                          ? '例如 https://api.anthropic.com'
                          : '需包含 /v1，例如 https://api.deepseek.com/v1',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '请输入 Base URL'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: model,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      helperText: '可手动填写，或点右侧按钮拉取厂商模型列表',
                      suffixIcon: IconButton(
                        tooltip: '获取模型列表',
                        onPressed: loadingModels
                            ? null
                            : () async {
                                final keyText = key.text.trim().isNotEmpty
                                    ? key.text.trim()
                                    : (await AiConfigStore.apiKey(
                                            _userId, config.id) ??
                                        '');
                                if (keyText.isEmpty) {
                                  _snack('请先填写 API Key');
                                  return;
                                }
                                setDialogState(() => loadingModels = true);
                                try {
                                  final models =
                                      await AiClient().fetchModels(
                                    config: config.copyWith(
                                      name: name.text.trim(),
                                      baseUrl: baseUrl.text.trim(),
                                      model: model.text.trim(),
                                    ),
                                    apiKey: keyText,
                                  );
                                  if (!context.mounted) return;
                                  setDialogState(() => loadingModels = false);
                                  if (models.isEmpty) {
                                    _snack('没有返回可用模型，可手动填写');
                                    return;
                                  }
                                  final picked =
                                      await showModalBottomSheet<String>(
                                    context: context,
                                    showDragHandle: true,
                                    builder: (sheetContext) => ListView(
                                      children: [
                                        const ListTile(
                                          title: Text('选择模型',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                        for (final m in models)
                                          ListTile(
                                            title: Text(m),
                                            onTap: () => Navigator.pop(
                                                sheetContext, m),
                                          ),
                                      ],
                                    ),
                                  );
                                  if (picked != null && context.mounted) {
                                    setDialogState(() => model.text = picked);
                                  }
                                } on AiException catch (e) {
                                  if (!context.mounted) return;
                                  setDialogState(() => loadingModels = false);
                                  _snack(e.message);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  setDialogState(() => loadingModels = false);
                                  _snack('获取模型列表失败，请检查地址和 Key');
                                }
                              },
                        icon: loadingModels
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.list_alt),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入模型名称' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: key,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      helperText: _keyHints[config.id]?.isNotEmpty == true
                          ? '${_keyHints[config.id]}；留空表示不修改'
                          : '仅保存在本机安全存储，填写后才会出现在列表中',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('支持图片输入（视觉）'),
                    subtitle: const Text('开启后可在对话中发送照片'),
                    value: supportsVision,
                    onChanged: (v) =>
                        setDialogState(() => supportsVision = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('设为当前使用'),
                    value: makeDefault,
                    onChanged: (v) => setDialogState(() => makeDefault = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final keyText = key.text.trim();
      if (keyText.isEmpty && !_keyHints.containsKey(config.id)) {
        if (mounted) _snack('请填写 API Key 后再保存');
      } else {
        if (keyText.isNotEmpty) {
          await AiConfigStore.setApiKey(_userId, config.id, keyText);
        }
        final updatedConfig = config.copyWith(
          name: name.text.trim(),
          baseUrl: baseUrl.text.trim(),
          model: model.text.trim(),
          supportsVision: supportsVision,
        );
        var list = _configs
            .map((c) => c.id == config.id ? updatedConfig : c)
            .toList(growable: false);
        if (makeDefault) {
          list = list
              .map((c) => c.copyWith(isDefault: c.id == config.id))
              .toList(growable: false);
        }
        await AiConfigStore.save(_userId, list);
        await _load();
        if (mounted) _snack('已保存');
      }
    }
    // Let the dialog's closing animation finish before releasing controllers.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    baseUrl.dispose();
    model.dispose();
    name.dispose();
    key.dispose();
  }

  Future<void> _addService() async {
    final available = aiProviderPresets
        .where((p) => !_keyHints.containsKey(p.id))
        .toList();
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('添加 AI 服务',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('选择厂商后填写 Base URL、模型与 API Key'),
          ),
          const Divider(height: 1),
          for (final preset in available)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE8F0E4),
                child: Text(preset.name.substring(0, 1).toUpperCase()),
              ),
              title: Text(preset.name),
              subtitle: Text(preset.model),
              onTap: () => Navigator.pop(context, preset.id),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('自定义服务商'),
            onTap: () => Navigator.pop(context, '__custom__'),
          ),
        ],
      ),
    );
    if (selectedId == null || !mounted) return;
    if (selectedId == '__custom__') {
      await _addCustom();
      return;
    }
    for (final preset in aiProviderPresets) {
      if (preset.id == selectedId) {
        await _edit(preset);
        return;
      }
    }
  }

  Future<void> _test(AiProviderConfig config) async {
    final key = await AiConfigStore.apiKey(_userId, config.id);
    if (key == null || key.isEmpty) {
      _snack('请先配置 API Key');
      return;
    }
    _snack('正在测试连接…');
    try {
      final result =
          await AiClient().testConnection(config: config, apiKey: key);
      _snack(result);
    } on AiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('连接失败，请检查网络与配置');
    }
  }

  Future<void> _setDefault(AiProviderConfig config) async {
    final list = _configs
        .map((c) => c.copyWith(isDefault: c.id == config.id))
        .toList(growable: false);
    await AiConfigStore.save(_userId, list);
    await _load();
    if (mounted) _snack('已切换到 ${config.name}');
  }

  Future<void> _deleteKey(AiProviderConfig config) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 API Key'),
        content: Text('将从本机删除 ${config.name} 的 Key，该服务会从列表中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiConfigStore.deleteApiKey(_userId, config.id);
    await _load();
  }

  Future<void> _addCustom() async {
    final name = TextEditingController();
    final baseUrl = TextEditingController();
    final model = TextEditingController();
    final key = TextEditingController();
    var kind = 'openai';
    var supportsVision = false;
    var loadingModels = false;
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加自定义服务商'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '显示名称'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: kind,
                    decoration: const InputDecoration(labelText: '协议'),
                    items: const [
                      DropdownMenuItem(value: 'openai', child: Text('OpenAI 兼容')),
                      DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
                    ],
                    onChanged: (v) => setDialogState(() => kind = v ?? 'openai'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Base URL'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '请输入 Base URL'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: model,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      helperText: '可手动填写，或点右侧按钮拉取厂商模型列表',
                      suffixIcon: IconButton(
                        tooltip: '获取模型列表',
                        onPressed: loadingModels
                            ? null
                            : () async {
                                final keyText = key.text.trim();
                                if (keyText.isEmpty) {
                                  _snack('请先填写 API Key');
                                  return;
                                }
                                setDialogState(() => loadingModels = true);
                                try {
                                  final models =
                                      await AiClient().fetchModels(
                                    config: AiProviderConfig(
                                      id: '__draft__',
                                      name: name.text.trim(),
                                      kind: kind,
                                      baseUrl: baseUrl.text.trim(),
                                      model: model.text.trim(),
                                    ),
                                    apiKey: keyText,
                                  );
                                  if (!context.mounted) return;
                                  setDialogState(() => loadingModels = false);
                                  if (models.isEmpty) {
                                    _snack('没有返回可用模型，可手动填写');
                                    return;
                                  }
                                  final picked =
                                      await showModalBottomSheet<String>(
                                    context: context,
                                    showDragHandle: true,
                                    builder: (sheetContext) => ListView(
                                      children: [
                                        const ListTile(
                                          title: Text('选择模型',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                        for (final m in models)
                                          ListTile(
                                            title: Text(m),
                                            onTap: () => Navigator.pop(
                                                sheetContext, m),
                                          ),
                                      ],
                                    ),
                                  );
                                  if (picked != null && context.mounted) {
                                    setDialogState(() => model.text = picked);
                                  }
                                } on AiException catch (e) {
                                  if (!context.mounted) return;
                                  setDialogState(() => loadingModels = false);
                                  _snack(e.message);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  setDialogState(() => loadingModels = false);
                                  _snack('获取模型列表失败，请检查地址和 Key');
                                }
                              },
                        icon: loadingModels
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.list_alt),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '请输入模型名称'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: key,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      helperText: '仅保存在本机安全存储',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('支持图片输入（视觉）'),
                    value: supportsVision,
                    onChanged: (v) =>
                        setDialogState(() => supportsVision = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final config = AiProviderConfig(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name.text.trim(),
        kind: kind,
        baseUrl: baseUrl.text.trim(),
        model: model.text.trim(),
        isDefault: _configured.isEmpty,
        supportsVision: supportsVision,
      );
      await AiConfigStore.setApiKey(_userId, config.id, key.text.trim());
      await AiConfigStore.save(_userId, [..._configs, config]);
      await _load();
      if (mounted) _snack('已添加 ${config.name}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final configured = _configured;
    final activeId = _active?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 服务设置'),
        actions: [
          IconButton(
            onPressed: _addService,
            icon: const Icon(Icons.add),
            tooltip: '添加 AI 服务',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'AI 请求由手机直连模型厂商，服务端不接收、不代理。\n'
                      'API Key 只保存在本机安全存储，按账号隔离，界面只显示末 4 位。\n'
                      '模型费用由你与厂商结算；AI 内容仅供参考，不能替代兽医。',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (configured.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.auto_awesome_outlined,
                              size: 40, color: Colors.black26),
                          const SizedBox(height: 12),
                          const Text('还没有配置 AI 服务'),
                          const SizedBox(height: 6),
                          const Text(
                            '添加服务商并填写 API Key 后，才会出现在这里并可用于对话。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black45, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _addService,
                            icon: const Icon(Icons.add),
                            label: const Text('添加 AI 服务'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      '已配置的服务（点击卡片编辑）',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                  for (final config in configured)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _providerCard(
                        config,
                        selected: config.id == activeId,
                      ),
                    ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _addService,
                    icon: const Icon(Icons.add),
                    label: const Text('添加 AI 服务'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _providerCard(AiProviderConfig config, {required bool selected}) {
    return Card(
      elevation: 0,
      color: selected ? const Color(0xFFEAF3E7) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? const Color(0xFF8FB57F) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              selected ? const Color(0xFFD7E8D0) : const Color(0xFFF1E4D8),
          child: Text(
            config.name.isEmpty ? '?' : config.name.substring(0, 1).toUpperCase(),
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(config.name)),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Chip(
                  avatar: Icon(Icons.check_circle,
                      size: 14, color: Color(0xFF3E6B4F)),
                  label: Text('当前使用', style: TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  backgroundColor: Color(0xFFD7E8D0),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${config.model}\n${_keyHints[config.id] ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: () => _edit(config),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'default':
                _setDefault(config);
                break;
              case 'edit':
                _edit(config);
                break;
              case 'test':
                _test(config);
                break;
              case 'delete':
                _deleteKey(config);
                break;
            }
          },
          itemBuilder: (context) => [
            if (!selected)
              const PopupMenuItem(
                  value: 'default', child: Text('设为当前使用')),
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            const PopupMenuItem(value: 'test', child: Text('测试连接')),
            const PopupMenuItem(value: 'delete', child: Text('删除 Key')),
          ],
        ),
      ),
    );
  }
}
