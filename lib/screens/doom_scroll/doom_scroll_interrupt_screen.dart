import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/profile_service.dart';

/// Full-screen interrupt shown when doom-scrolling limits are exceeded.
/// Displays a motivational nudge and lets the user dismiss or take a break.
class DoomScrollInterruptScreen extends StatefulWidget {
  final String uid;
  final List<Map<String, dynamic>> exceededApps;
  final VoidCallback onDismiss;

  const DoomScrollInterruptScreen({
    super.key,
    required this.uid,
    required this.exceededApps,
    required this.onDismiss,
  });

  @override
  State<DoomScrollInterruptScreen> createState() =>
      _DoomScrollInterruptScreenState();
}

class _DoomScrollInterruptScreenState extends State<DoomScrollInterruptScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _name = '';
  String _message = '';

  static const _nudges = [
    "You've been scrolling for a while. Time to take a breath.",
    "Your future self will thank you for stopping now.",
    "Every minute you reclaim is a minute closer to your goals.",
    "The feed will still be there tomorrow. Your time won't.",
    "Deep work beats doom-scrolling. You've got this.",
    "Your streak is waiting — go knock out a task instead.",
    "Screens drain energy. Movement restores it.",
    "You set these limits for a reason. Honor them.",
    "The best version of you isn't on this screen right now.",
    "Close this app. Open your potential.",
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _message = _nudges[Random().nextInt(_nudges.length)];
    _loadName();
  }

  Future<void> _loadName() async {
    final name = await ProfileService(widget.uid).getName();
    if (mounted && name.isNotEmpty) {
      setState(() => _name = name);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;


    // Build exceeded summary
    final perApp = widget.exceededApps
        .where((a) => a['type'] == 'per_app')
        .toList();
    final global =
        widget.exceededApps.where((a) => a['type'] == 'global').firstOrNull;

    return PopScope(
      canPop: false, // prevent back button dismissing
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated icon
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.errorContainer,
                      ),
                      child: Icon(
                        Icons.self_improvement,
                        size: 64,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Greeting
                  Text(
                    'Hey${_name.isNotEmpty ? ', $_name' : ''}!',
                    style: ts.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Nudge message
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: ts.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Usage summary card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warning_amber, color: cs.error),
                              const SizedBox(width: 8),
                              Text(
                                'Daily limit exceeded',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: cs.error,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (perApp.isNotEmpty)
                            ...perApp.map((a) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          a['appName'] as String,
                                          style: ts.bodyMedium,
                                        ),
                                      ),
                                      Text(
                                        '${a['usedMinutes']} min / ${a['limitMinutes']} min',
                                        style: ts.bodyMedium?.copyWith(
                                          color: cs.error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          if (global != null) ...[
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total monitored',
                                  style: ts.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${global['usedMinutes']} min / ${global['limitMinutes']} min',
                                  style: ts.bodyMedium?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        // Move app to background
                        SystemNavigator.pop();
                        widget.onDismiss();
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Go do something productive'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Dismiss and snooze for 15 minutes
                        widget.onDismiss();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.snooze),
                      label: const Text('Snooze 15 min'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
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
