import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/toast.dart';
import '../../core/format_time.dart';
import '../../core/models.dart';
import '../../core/session.dart';

class AdminDevicesPage extends ConsumerStatefulWidget {
  const AdminDevicesPage({super.key});

  @override
  ConsumerState<AdminDevicesPage> createState() => _AdminDevicesPageState();
}

class _AdminDevicesPageState extends ConsumerState<AdminDevicesPage> {
  List<AdminDevice>? _devices;
  String? _error;
  bool _loading = true;

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
      final devices = await ref.read(apiClientProvider).listAllDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
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

  Future<void> _revoke(AdminDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('吊销设备'),
        content: Text('吊销「${device.username} · ${device.name}」后，该设备需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('吊销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).adminRevokeDevice(device.id);
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
      appBar: AppBar(
        title: const Text('全部设备'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                          onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: _devices!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final device = _devices![index];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            Icons.smartphone_outlined,
                            color:
                                device.active ? Colors.black87 : Colors.black26,
                          ),
                          title: Text(
                            '${device.username} · ${device.name.isEmpty ? 'Android' : device.name}',
                          ),
                          subtitle: Text(
                            device.active
                                ? (device.lastSeenAt.isEmpty
                                    ? '尚未上报在线时间'
                                    : '最后在线 ${formatLocalTime(device.lastSeenAt)}')
                                : '已吊销 ${formatLocalTime(device.revokedAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: device.active
                              ? TextButton(
                                  onPressed: () => _revoke(device),
                                  child: const Text('吊销'),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
