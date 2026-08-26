import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api/api_service.dart';
import '../../services/chat/chat_action_handler.dart';
import '../../utils/sanitizer.dart';

/// Chat screen with voice input (STT), voice output (TTS),
/// and AI function calling (creates tasks, alarms, habits, etc.).
class ChatScreen extends StatefulWidget {
  final VoidCallback? onMenuPressed;
  const ChatScreen({super.key, this.onMenuPressed});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _loading = false;

  // Voice
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _isListening = false;
  bool _ttsEnabled = false;
  bool _speechAvailable = false;
  bool _speechInitialized = false;
  bool _ttsInitialized = false;
  bool _cooldown = false; // prevents spamming during rate limits

  @override
  void initState() {
    super.initState();
  }

  Future<void> _ensureSpeechInit() async {
    if (_speechInitialized) return;
    _speechInitialized = true;
    _speechAvailable = await _speech.initialize(
      onError: (e) {
        if (mounted && _isListening) {
          setState(() => _isListening = false);
        }
      },
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          if (mounted && _isListening) {
            setState(() => _isListening = false);
          }
        }
      },
    );
  }

  Future<void> _ensureTtsInit() async {
    if (_ttsInitialized) return;
    _ttsInitialized = true;
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Voice input ---

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    await _ensureSpeechInit();
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    HapticFeedback.mediumImpact();

    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          setState(() => _controller.text = result.recognizedWords);
        }
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _send();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
    );
  }

  // --- TTS ---

  Future<void> _speak(String text) async {
    if (!_ttsEnabled) return;
    await _ensureTtsInit();
    final cleanText = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), 'code block omitted')
        .replaceAll(RegExp(r'`[^`]*`'), '')
        .replaceAll(RegExp(r'\*\*([^*]*)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*([^*]*)\*'), r'$1')
        .replaceAll(RegExp(r'#{1,6}\s'), '');
    await _tts.speak(cleanText);
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
  }

  // --- Chat ---

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    final cleanText = Sanitizer.sanitize(text);

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: cleanText));
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final history = _messages
        .where((m) => m.role != 'system')
        .map((m) => {
              'role': m.role,
              'parts': [m.text],
            })
        .toList();
    if (history.isNotEmpty) history.removeLast();

    // Round 1: send message to backend
    String? errorMsg;
    Map<String, dynamic>? result;
    String debugInfo = '';
    setState(() {
      _messages.add(_ChatMessage(role: 'action', text: 'Connecting to AI...'));
    });
    _scrollToBottom();
    try {
      result = await ApiService.chatFull(cleanText, history: history);
      debugInfo = 'backend=ok';
    } catch (e) {
      errorMsg = e.toString();
      debugInfo = 'backend=err:${e.toString().substring(0, 80.clamp(0, e.toString().length))}';
      // Real detail goes to the debug console only — the user-facing
      // message stays friendly and error-category-specific (see below).
      debugPrint('Chat request failed: $debugInfo');
    }
    // Remove the connecting message
    if (_messages.isNotEmpty && _messages.last.text == 'Connecting to AI...') {
      _messages.removeLast();
    }

    if (!mounted) return;

    if (result == null) {
      final detail = errorMsg ?? 'No response from API';
      final isRateLimit = detail.contains('429') || detail.contains('RESOURCE_EXHAUSTED') || detail.contains('rate');
      String userMessage;
      if (isRateLimit) {
        final match = RegExp(r'retry in (\d+\.?\d*)s').firstMatch(detail);
        final waitSec = match != null ? double.parse(match.group(1)!).ceil() : 60;
        userMessage = '⚠️ Rate limited — too many requests.\nWait ${waitSec}s then try again.';
        _cooldown = true;
        setState(() {});
        Future.delayed(Duration(seconds: waitSec), () {
          if (mounted) { _cooldown = false; setState(() {}); }
        });
      } else {
        // Distinguish the common causes instead of dumping the raw
        // exception text into the chat — a sleeping free-tier backend
        // (timeout) needs a different message than no internet at all.
        final lower = detail.toLowerCase();
        if (lower.contains('timeoutexception') || lower.contains('timeout')) {
          userMessage =
              "⚠️ The AI backend is waking up — it goes to sleep after "
              "sitting idle, and the first reply after that can take up "
              "to a minute. Please try sending your message again.";
        } else if (lower.contains('socketexception') ||
            lower.contains('failed host lookup') ||
            lower.contains('network is unreachable') ||
            lower.contains('connection refused')) {
          userMessage =
              "⚠️ Could not reach the AI — check your internet connection "
              "and try again.";
        } else {
          userMessage =
              "⚠️ Something went wrong reaching the AI. Please try again "
              "in a moment.";
        }
      }
      setState(() {
        _loading = false;
        _messages.add(_ChatMessage(role: 'model', text: userMessage));
      });
      _scrollToBottom();
      return;
    }

    // Check for function calls
    final functionCalls = result['functionCalls'] as List<dynamic>?;
    final reply = result['reply'] as String?;

    if (functionCalls != null && functionCalls.isNotEmpty) {
      // Show a "thinking" action message
      setState(() {
        _messages.add(_ChatMessage(
          role: 'action',
          text: _describeActions(functionCalls),
        ));
      });
      _scrollToBottom();

      // Execute function calls locally in Firestore
      try {
        final callResults = await ChatActionHandler.executeAll(
          functionCalls.cast<Map<String, dynamic>>(),
        );

        // Show success feedback
        final successMessages = callResults
            .where((r) => (r['result'] as Map<String, dynamic>)['success'] == true)
            .map((r) => _describeResult(r))
            .toList();

        if (successMessages.isNotEmpty) {
          setState(() {
            _messages.add(_ChatMessage(
              role: 'action',
              text: '✅ ${successMessages.join(", ")}',
            ));
          });
          _scrollToBottom();
        }

        // Round 2: send results back to Gemini for natural language response
        final followUp = await ApiService.chatWithFunctionResults(
          cleanText,
          functionCalls.cast<Map<String, dynamic>>(),
          callResults,
          history: history,
        );

        final finalReply = followUp?['reply'] as String? ?? 'Done!';

        if (mounted) {
          setState(() {
            _loading = false;
            _messages.add(_ChatMessage(role: 'model', text: finalReply));
          });
          _scrollToBottom();
          _speak(finalReply);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _messages.add(_ChatMessage(
              role: 'model',
              text: '⚠️ Something went wrong executing that action: $e',
            ));
          });
          _scrollToBottom();
        }
      }
    } else {
      // Simple text reply — no function calls
      setState(() {
        _loading = false;
        _messages.add(_ChatMessage(role: 'model', text: reply ?? 'Done!'));
      });
      _scrollToBottom();
      if (reply != null) _speak(reply);
    }
  }

  /// Human-readable description of what functions will be called.
  String _describeActions(List<dynamic> calls) {
    final descriptions = <String>[];
    for (final call in calls) {
      final name = call['name'] as String;
      final args = (call['args'] as Map<String, dynamic>?) ?? {};
      switch (name) {
        case 'create_task':
          descriptions.add('Creating task: "${args['title'] ?? ''}"');
          break;
        case 'complete_task':
          descriptions.add('Updating task status');
          break;
        case 'create_alarm':
          final h = args['hour'] ?? 0;
          final m = args['minute'] ?? 0;
          descriptions.add(
              'Setting alarm: ${args['label'] ?? 'Alarm'} at ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
          break;
        case 'create_habit':
          descriptions.add('Adding habit: "${args['name'] ?? ''}"');
          break;
        case 'add_note':
          descriptions.add('Saving note: "${args['title'] ?? ''}"');
          break;
        case 'add_braindump':
          descriptions.add('Saving brain dump entry');
          break;
        case 'add_dsa_problem':
          descriptions.add(
              'Adding DSA problem: "${args['name'] ?? ''}"');
          break;
        case 'list_tasks':
          descriptions.add('Looking up your tasks');
          break;
        case 'list_habits':
          descriptions.add('Looking up your habits');
          break;
        case 'list_alarms':
          descriptions.add('Looking up your alarms');
          break;
        case 'list_notes':
          descriptions.add('Looking up your notes');
          break;
        case 'list_braindump':
          descriptions.add('Looking up your brain dumps');
          break;
        case 'list_dsa_problems':
          descriptions.add('Looking up your DSA problems');
          break;
        default:
          descriptions.add('Running: $name');
      }
    }
    return descriptions.join('\n');
  }

  /// Human-readable result of a function call.
  String _describeResult(Map<String, dynamic> result) {
    final name = result['name'] as String;
    final res = result['result'] as Map<String, dynamic>;
    switch (name) {
      case 'create_task':
        return 'Created task "${res['title']}"';
      case 'complete_task':
        return res['completed'] == true
            ? 'Marked task as done'
            : 'Unmarked task';
      case 'create_alarm':
        final h = res['hour'] ?? 0;
        final m = res['minute'] ?? 0;
        return 'Set alarm "${res['label']}" at ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      case 'create_habit':
        return 'Started tracking "${res['name']}"';
      case 'add_note':
        return 'Saved note "${res['title']}"';
      case 'add_braindump':
        return 'Saved brain dump';
      case 'add_dsa_problem':
        return 'Added "${res['name']}" to DSA review';
      case 'list_tasks':
        return '${res['count']} tasks found';
      case 'list_habits':
        return '${res['count']} habits found';
      case 'list_alarms':
        return '${res['count']} alarms found';
      case 'list_notes':
        return '${res['count']} notes found';
      case 'list_braindump':
        return '${res['count']} brain dump entries found';
      case 'list_dsa_problems':
        return '${res['count']} DSA problems found';
      default:
        return 'Done';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onMenuPressed != null
            ? IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu',
                onPressed: widget.onMenuPressed,
              )
            : null,
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: Icon(
              _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _ttsEnabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _ttsEnabled ? 'Voice replies on' : 'Voice replies off',
            onPressed: () {
              setState(() => _ttsEnabled = !_ttsEnabled);
              if (!_ttsEnabled) _stopSpeaking();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(
                        message: _messages[index],
                        onSpeak: _speak,
                        ttsEnabled: _ttsEnabled,
                      );
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'Personal OS Assistant',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me to create tasks, set alarms, add habits, write notes, and more.\n\nTry: "Create a task to buy groceries tomorrow"\nOr: "Set an alarm for 7:30 AM"\nOr: "Add a habit to exercise every day"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: _speechAvailable ? _toggleListening : null,
              icon: Icon(
                _isListening ? Icons.stop_circle : Icons.mic,
                color: _isListening ? cs.error : cs.onSurfaceVariant,
                size: 28,
              ),
              tooltip: _isListening ? 'Stop listening' : 'Speak',
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: _isListening
                      ? 'Listening...'
                      : 'Create a task, set alarm, add habit...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: (_loading || _cooldown) ? null : _send,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String role; // 'user', 'model', 'action'
  final String text;
  _ChatMessage({required this.role, required this.text});
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onSpeak,
    required this.ttsEnabled,
  });

  final _ChatMessage message;
  final Future<void> Function(String) onSpeak;
  final bool ttsEnabled;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isAction = message.role == 'action';
    final scheme = Theme.of(context).colorScheme;

    // Action messages — small, centered, muted
    if (isAction) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isUser
                ? Text(
                    message.text,
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  )
                : MarkdownBody(
                    data: message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: scheme.onSurfaceVariant),
                      code: TextStyle(
                        backgroundColor: scheme.surface,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
            if (!isUser && ttsEnabled)
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => onSpeak(message.text),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.volume_up,
                      size: 18,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Thinking...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}