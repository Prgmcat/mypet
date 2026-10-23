import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _invite = TextEditingController();
  final _username = TextEditingController();
  final _display = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _invite.dispose();
    _username.dispose();
    _display.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final error = await ref.read(sessionProvider.notifier).register(
          inviteCode: _invite.text.trim().toUpperCase(),
          username: _username.text.trim(),
          password: _password.text,
          displayName: _display.text.trim(),
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _invite,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '邀请码',
                      hintText: '向管理员获取',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入邀请码' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      helperText: '4–20 位字母、数字或下划线',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.length < 4 || value.length > 20) {
                        return '用户名需 4–20 位';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _display,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '昵称（可选）',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      helperText: '8–32 位，至少包含字母和数字',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      final value = v ?? '';
                      if (value.length < 8 || value.length > 32) {
                        return '密码需 8–32 位';
                      }
                      if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
                          !RegExp(r'\d').hasMatch(value)) {
                        return '密码需同时包含字母和数字';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('注册并登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
