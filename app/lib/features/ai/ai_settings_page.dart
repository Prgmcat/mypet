import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_client.dart';
import '../../core/toast.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_config_transfer.dart';
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
        hints[config.id] = key.length <= 8
            ? '已保存'
            : '已保存 · 末 4 位 ${key.substring(key.length - 4)}';
      }
    }
    final configured = configs.where((c) => hints.containsKey(c.id)).toList();
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
    var obscureKey = true;
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
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入 Base URL' : null,
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
                                  final models = await AiClient().fetchModels(
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
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        for (final m in models)
                                          ListTile(
                                            title: Text(m),
                                            onTap: () =>
                                                Navigator.pop(sheetContext, m),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                    obscureText: obscureKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      helperText: _keyHints[config.id]?.isNotEmpty == true
                          ? '${_keyHints[config.id]}；留空表示不修改'
                          : '仅保存在本机安全存储，填写后才会出现在列表中',
                      suffixIcon: IconButton(
                        tooltip: obscureKey ? '显示 Key' : '隐藏 Key',
                        icon: Icon(obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setDialogState(() => obscureKey = !obscureKey),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('支持图片输入（视觉）'),
                    subtitle: const Text('开启后可在对话中发送照片'),
                    value: supportsVision,
                    onChanged: (v) => setDialogState(() => supportsVision = v),
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
    final available =
        aiProviderPresets.where((p) => !_keyHints.containsKey(p.id)).toList();
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title:
                Text('添加 AI 服务', style: TextStyle(fontWeight: FontWeight.w700)),
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
    var obscureKey = true;
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
                      DropdownMenuItem(
                          value: 'openai', child: Text('OpenAI 兼容')),
                      DropdownMenuItem(
                          value: 'anthropic', child: Text('Anthropic')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => kind = v ?? 'openai'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Base URL'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入 Base URL' : null,
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
                                  final models = await AiClient().fetchModels(
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
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        for (final m in models)
                                          ListTile(
                                            title: Text(m),
                                            onTap: () =>
                                                Navigator.pop(sheetContext, m),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                    obscureText: obscureKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      helperText: '仅保存在本机安全存储',
                      suffixIcon: IconButton(
                        tooltip: obscureKey ? '显示 Key' : '隐藏 Key',
                        icon: Icon(obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setDialogState(() => obscureKey = !obscureKey),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('支持图片输入（视觉）'),
                    value: supportsVision,
                    onChanged: (v) => setDialogState(() => supportsVision = v),
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

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    showToast(context, message, error: error);
  }

  Future<String?> _askPassword({
    required String title,
    required bool confirmExport,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  confirmExport
                      ? '加密字符串会用这个密码加密。忘记密码将无法恢复，请妥善保存。'
                      : '输入导出时设置的密码，用于解密配置字符串。',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                  validator: (value) {
                    final text = value ?? '';
                    if (confirmExport && text.length < 8) return '至少 8 位';
                    if (!confirmExport && text.isEmpty) return '请输入密码';
                    return null;
                  },
                ),
                if (confirmExport) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: second,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '确认密码'),
                    validator: (value) =>
                        value != first.text ? '两次密码不一致' : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, first.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _exportConfigs() async {
    final configured = _configured;
    if (configured.isEmpty) {
      _snack('还没有可导出的 API Key 配置');
      return;
    }
    final password =
        await _askPassword(title: '导出 AI 配置', confirmExport: true);
    if (password == null || !mounted) return;
    final keys = <String, String>{};
    for (final config in configured) {
      final key = await AiConfigStore.apiKey(_userId, config.id);
      if (key != null && key.isNotEmpty) keys[config.id] = key;
    }
    if (keys.isEmpty) {
      _snack('还没有可导出的 API Key 配置');
      return;
    }
    try {
      final text = await AiConfigTransfer.exportString(
        configs: _configs,
        keys: keys,
        password: password,
        serverUrl: ref.read(sessionProvider).serverUrl,
      );
      if (!mounted) return;
      await _showExportedString(text);
    } catch (e) {
      _snack('导出失败：$e', error: true);
    }
  }

  Future<void> _showExportedString(String value) async {
    final controller = TextEditingController(text: value);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加密配置已生成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '复制下面整段字符串，在另一台设备选择「导入配置」后粘贴。',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              readOnly: true,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(hintText: '加密配置'),
            ),
            const SizedBox(height: 6),
            const Text(
              '字符串已加密，密码不会保存；请通过安全渠道传递。',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!mounted) return;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _snack('已复制加密配置');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<_ImportInput?> _askImportInput() async {
    final value = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<_ImportInput>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入 AI 配置'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '粘贴另一台设备导出的加密字符串，并输入导出时设置的密码。',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: value,
                  maxLines: 6,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: '加密配置',
                    hintText: 'MYPETAI:...',
                  ),
                  validator: (text) =>
                      (text ?? '').trim().isEmpty ? '请粘贴加密配置' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                  validator: (text) =>
                      (text ?? '').isEmpty ? '请输入密码' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(
                dialogContext,
                _ImportInput(value.text.trim(), password.text),
              );
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
    value.dispose();
    password.dispose();
    return result;
  }

  Future<void> _importConfigs() async {
    final input = await _askImportInput();
    if (input == null || !mounted) return;
    if (input.value.length > 300000) {
      _snack('配置字符串过长', error: true);
      return;
    }
    try {
      final imported = await AiConfigTransfer.importString(
        value: input.value,
        password: input.password,
      );
      if (!mounted) return;
      final currentServer = ref.read(sessionProvider).serverUrl;
      if (imported.serverUrl != null && imported.serverUrl != currentServer) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('配置来自其他服务器'),
            content: Text(
              '这份配置导出于 ${imported.serverUrl}\n'
              '当前服务器是 $currentServer\n\n'
              '仍要导入到当前账号吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('导入'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
      final byId = <String, AiProviderConfig>{
        for (final config in _configs) config.id: config,
      };
      for (final config in imported.configs) {
        byId[config.id] = config;
      }
      final merged = byId.values.toList();
      final importedDefault =
          imported.configs.where((config) => config.isDefault).toList();
      if (importedDefault.isNotEmpty) {
        final defaultId = importedDefault.first.id;
        for (var i = 0; i < merged.length; i++) {
          merged[i] = merged[i].copyWith(isDefault: merged[i].id == defaultId);
        }
      }
      await AiConfigStore.save(_userId, merged);
      for (final entry in imported.keys.entries) {
        await AiConfigStore.setApiKey(_userId, entry.key, entry.value);
      }
      await _load();
      if (!mounted) return;
      _snack('已导入 ${imported.configs.length} 个服务商配置');
    } on FormatException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('导入失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = _configured;
    final activeId = _active?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 服务设置'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '导入/导出配置',
            onSelected: (value) {
              if (value == 'import') {
                _importConfigs();
              } else if (value == 'export') {
                _exportConfigs();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('导入配置')),
              PopupMenuItem(value: 'export', child: Text('导出配置')),
            ],
          ),
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
                      '右上角菜单可加密导入/导出配置字符串；密码不保存，忘记后无法恢复。\n'
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
                            style:
                                TextStyle(color: Colors.black45, fontSize: 12),
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
            config.name.isEmpty
                ? '?'
                : config.name.substring(0, 1).toUpperCase(),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          color: Colors.white,
          elevation: 8,
          offset: const Offset(0, 6),
          constraints: const BoxConstraints(minWidth: 170),
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
              const PopupMenuItem(value: 'default', child: Text('设为当前使用')),
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            const PopupMenuItem(value: 'test', child: Text('测试连接')),
            const PopupMenuItem(value: 'delete', child: Text('删除 Key')),
          ],
        ),
      ),
    );
  }
}

class _ImportInput {
  const _ImportInput(this.value, this.password);

  final String value;
  final String password;
}
