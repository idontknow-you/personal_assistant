import 'package:flutter/material.dart';
import '../../services/doom_scroll/doom_scroll_service.dart';

/// Configure which apps to monitor and daily time limits.
class DoomScrollSettingsScreen extends StatefulWidget {
  const DoomScrollSettingsScreen({super.key});

  @override
  State<DoomScrollSettingsScreen> createState() =>
      _DoomScrollSettingsScreenState();
}

class _DoomScrollSettingsScreenState extends State<DoomScrollSettingsScreen> {
  bool _enabled = false;
  int _globalLimitMinutes = 60;
  List<MonitoredApp> _monitoredApps = [];
  List<Map<String, dynamic>> _installedApps = [];
  bool _loading = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _hasPermission = await DoomScrollService.hasUsagePermission();
    _enabled = await DoomScrollService.isEnabled();
    _globalLimitMinutes = await DoomScrollService.getGlobalLimitMinutes();
    _monitoredApps = await DoomScrollService.getMonitoredApps();

    if (_hasPermission) {
      _installedApps = await DoomScrollService.getInstalledApps();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value && !_hasPermission) {
      await DoomScrollService.requestUsagePermission();
      // Re-check after returning from settings
      _hasPermission = await DoomScrollService.hasUsagePermission();
      if (!_hasPermission && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usage access permission is required')),
        );
        return;
      }
    }
    await DoomScrollService.setEnabled(value);
    setState(() => _enabled = value);
  }

  Future<void> _addApp(Map<String, dynamic> appInfo) async {
    final packageName = appInfo['packageName'] as String;
    final appName = appInfo['appName'] as String;

    // Check not already added
    if (_monitoredApps.any((a) => a.packageName == packageName)) return;

    // Ask for limit
    final limit = await _showLimitDialog(appName);
    if (limit == null) return;

    final app = MonitoredApp(
      packageName: packageName,
      appName: appName,
      limitMinutes: limit,
    );
    _monitoredApps.add(app);
    await DoomScrollService.setMonitoredApps(_monitoredApps);
    setState(() {});
  }

  Future<int?> _showLimitDialog(String appName) async {
    final controller = TextEditingController(text: '30');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Limit for $appName'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Daily limit (minutes)',
            suffixText: 'min',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val > 0) Navigator.pop(ctx, val);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Future<void> _editLimit(MonitoredApp app) async {
    final limit = await _showLimitDialog(app.appName);
    if (limit == null) return;

    final idx = _monitoredApps.indexWhere((a) => a.packageName == app.packageName);
    if (idx == -1) return;
    _monitoredApps[idx] = MonitoredApp(
      packageName: app.packageName,
      appName: app.appName,
      limitMinutes: limit,
    );
    await DoomScrollService.setMonitoredApps(_monitoredApps);
    setState(() {});
  }

  Future<void> _removeApp(MonitoredApp app) async {
    _monitoredApps.removeWhere((a) => a.packageName == app.packageName);
    await DoomScrollService.setMonitoredApps(_monitoredApps);
    setState(() {});
  }

  void _showAddAppSheet() async {
    // Re-fetch installed apps every time (permission may have been granted after initial load)
    _hasPermission = await DoomScrollService.hasUsagePermission();
    if (!_hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usage access permission required. Grant it in Android settings.')),
        );
      }
      return;
    }
    _installedApps = await DoomScrollService.getInstalledApps();
    if (mounted) setState(() {});

    // Filter out already-monitored apps
    final available = _installedApps
        .where((a) => !_monitoredApps
            .any((m) => m.packageName == a['packageName']))
        .toList()
      ..sort((a, b) =>
          (a['appName'] as String).compareTo(b['appName'] as String));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add App to Monitor',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: available.length,
                itemBuilder: (_, i) {
                  final app = available[i];
                  return ListTile(
                    leading: const Icon(Icons.apps),
                    title: Text(app['appName'] as String),
                    subtitle: Text(
                      app['packageName'] as String,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _addApp(app);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Anti-Doom-Scroll')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Anti-Doom-Scroll')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Permission banner
          if (!_hasPermission)
            Card(
              color: cs.errorContainer,
              child: ListTile(
                leading: Icon(Icons.warning, color: cs.onErrorContainer),
                title: Text(
                  'Usage access permission required',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
                subtitle: Text(
                  'Tap to open Android settings and enable "Usage access" for Personal OS.',
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                ),
                trailing: FilledButton(
                  onPressed: () async {
                    await DoomScrollService.requestUsagePermission();
                  },
                  child: const Text('Grant'),
                ),
              ),
            ),

          // Master toggle
          SwitchListTile(
            title: const Text('Enable Anti-Doom-Scroll'),
            subtitle: const Text(
              'Monitor app usage and interrupt when limits are exceeded',
              style: TextStyle(fontSize: 12),
            ),
            value: _enabled,
            onChanged: _toggleEnabled,
          ),

          const SizedBox(height: 8),

          // Global limit
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Global daily limit'),
            subtitle: Text(
              '$_globalLimitMinutes minutes across all monitored apps',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final controller = TextEditingController(
                text: _globalLimitMinutes.toString(),
              );
              final result = await showDialog<int>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Global limit'),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total minutes per day',
                      suffixText: 'min',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final val = int.tryParse(controller.text);
                        if (val != null && val > 0) Navigator.pop(ctx, val);
                      },
                      child: const Text('Set'),
                    ),
                  ],
                ),
              );
              if (result != null) {
                await DoomScrollService.setGlobalLimitMinutes(result);
                setState(() => _globalLimitMinutes = result);
              }
            },
          ),

          const Divider(height: 32),

          // Monitored apps header
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Monitored Apps',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              if (_hasPermission)
                FilledButton.tonalIcon(
                  onPressed: _showAddAppSheet,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),

          const SizedBox(height: 8),

          if (_monitoredApps.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.phone_android,
                          size: 48, color: cs.outline),
                      const SizedBox(height: 8),
                      Text(
                        'No apps monitored yet.\nTap "Add" to pick apps and set limits.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.outline),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._monitoredApps.map((app) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.apps),
                    title: Text(app.appName),
                    subtitle: Text(
                      'Limit: ${app.limitMinutes} min/day',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _editLimit(app),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 20, color: cs.error),
                          onPressed: () => _removeApp(app),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
