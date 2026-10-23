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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final configs = await AiConfigStore.load(_userId);
    final hints = <String, String>{};
    for (final config in configs) {
      final key = await AiConfigStore.apiKey(_userId, config.id);
      if (key != null && key.isNotEmpty) {
        hints[config.id] =
            key.length <= 8 ? '已保存' : '已保存 · 末 4 位 ${key.substring(key.length - 4)}';
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
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                  decoration: const InputDecoration(labelText: '模型名称'),
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
                        : '仅保存在本机安全存储，不会上传服务端',
                  ),
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
    );
    if (saved == true) {
      final updated = config.copyWith(
        name: name.text.trim(),
        baseUrl: baseUrl.text.trim(),
        model: model.text.trim(),
      );
      final list = _configs
          .map((c) => c.id == config.id ? updated : c)
          .toList(growable: false);
      await AiConfigStore.save(_userId, list);
      if (key.text.trim().isNotEmpty) {
        await AiConfigStore.setApiKey(_userId, config.id, key.text.trim());
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
    baseUrl.dispose();
    model.dispose();
    name.dispose();
    key.dispose();
  }

  Future<void> _test(AiProviderConfig config) async {
    final key = await AiConfigStore.apiKey(_userId, config.id);
    if (key == null || key.isEmpty) {
      _snack('请先配置 API Key');
      return;
    }
    _snack('正在测试连接…');
    try {
      final result = await AiClient()
          .testConnection(config: config, apiKey: key);
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
  }

  Future<void> _deleteKey(AiProviderConfig config) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 API Key'),
        content: Text('将从本机删除 ${config.name} 的 Key，模型费用不退还。'),
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
    var kind = 'openai';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加自定义服务商'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '显示名称'),
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
              TextField(
                controller: baseUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Base URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: model,
                decoration: const InputDecoration(labelText: '模型名称'),
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
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (ok == true &&
        name.text.trim().isNotEmpty &&
        baseUrl.text.trim().isNotEmpty &&
        model.text.trim().isNotEmpty) {
      final config = AiProviderConfig(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name.text.trim(),
        kind: kind,
        baseUrl: baseUrl.text.trim(),
        model: model.text.trim(),
      );
      await AiConfigStore.save(_userId, [..._configs, config]);
      await _load();
    }
    name.dispose();
    baseUrl.dispose();
    model.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 服务设置'),
        actions: [
          IconButton(
            onPressed: _addCustom,
            icon: const Icon(Icons.add),
            tooltip: '添加自定义服务商',
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
                for (final config in _configs)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: config.id == 'anthropic'
                            ? const Color(0xFFFDE8D7)
                            : const Color(0xFFE8F0E4),
                        child: Text(
                          config.name.isEmpty
                              ? '?'
                              : config.name.substring(0, 1).toUpperCase(),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(config.name)),
                          if (config.isDefault)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Chip(
                                label: Text('默认',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${config.model}\n'
                        '${_keyHints[config.id] ?? '未配置 Key'}',
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
                            case 'test':
                              _test(config);
                              break;
                            case 'delete':
                              _deleteKey(config);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'default', child: Text('设为默认')),
                          const PopupMenuItem(
                              value: 'test', child: Text('测试连接')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除 Key')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
