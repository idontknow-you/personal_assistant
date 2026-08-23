import 'package:flutter/material.dart';
import '../../services/update/update_service.dart';

/// Shows when a new version is available. Downloads and triggers install.
class UpdateDialog extends StatefulWidget {
  final Map<String, dynamic> updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  /// Show the update dialog as a modal.
  static Future<void> show(BuildContext context, Map<String, dynamic> info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  String get _version => widget.updateInfo['version'] ?? 'unknown';
  String get _currentVersion => widget.updateInfo['currentVersion'] ?? 'unknown';
  String get _releaseNotes => widget.updateInfo['releaseNotes'] ?? '';
  String get _downloadUrl => widget.updateInfo['downloadUrl'] ?? '';

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    final apkPath = await UpdateService.downloadApk(_downloadUrl, (p) {
      if (mounted) setState(() => _progress = p);
    });

    if (!mounted) return;

    if (apkPath == null) {
      setState(() {
        _downloading = false;
        _error = 'Download failed. Check your internet connection.';
      });
      return;
    }

    // Trigger install
    final installed = await UpdateService.triggerInstall(apkPath);
    if (mounted) {
      setState(() => _downloading = false);
      if (!installed) {
        setState(() => _error = 'Could not open installer. Check app permissions.');
      } else {
        Navigator.of(context).pop(); // Close dialog
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.system_update, size: 48, color: cs.primary),
      title: Text('Update Available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('v$_currentVersion', style: Theme.of(context).textTheme.bodySmall),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('v$_version',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Release notes
          if (_releaseNotes.isNotEmpty) ...[
            Text(
              'What\'s new:',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _releaseNotes,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // Download progress
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(
              _progress > 0 ? '${(_progress * 100).round()}% downloaded' : 'Preparing download...',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],

          // Error
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: cs.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (!_downloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download),
            label: const Text('Update'),
          ),
        ],
      ],
    );
  }
}
