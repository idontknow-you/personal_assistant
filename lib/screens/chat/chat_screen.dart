import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api/api_service.dart';

/// Chat screen with voice input (STT) and voice output (TTS).
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

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  Future<void> _initSpeech() async {
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

  Future<void> _initTts() async {
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

    if (!_speechAvailable) {
      final initialized = await _speech.initialize();
      if (!initialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }
    }

    setState(() => _isListening = true);
    HapticFeedback.mediumImpact();

    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          setState(() => _controller.text = result.recognizedWords);
        }
        // Auto-send on final result
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
    // Strip markdown formatting for cleaner speech
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

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
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

    final reply = await ApiService.chat(text, history: history);

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (reply != null) {
        _messages.add(_ChatMessage(role: 'model', text: reply));
      } else {
        _messages.add(_ChatMessage(
          role: 'model',
          text: '⚠️ Could not reach the backend. Make sure it\'s running.',
        ));
      }
    });
    _scrollToBottom();

    // Auto-speak the reply
    if (reply != null) _speak(reply);
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
          // TTS toggle
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
              'Ask me about your tasks, habits, mood patterns, or anything on your mind.\n\nTap the 🎤 to speak instead of type.',
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
            // Mic button
            IconButton(
              onPressed: _speechAvailable ? _toggleListening : null,
              icon: Icon(
                _isListening ? Icons.stop_circle : Icons.mic,
                color: _isListening ? cs.error : cs.onSurfaceVariant,
                size: 28,
              ),
              tooltip: _isListening ? 'Stop listening' : 'Speak',
            ),
            // Text field
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: _isListening ? 'Listening...' : 'Ask anything...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _loading ? null : _send,
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
  final String role;
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
    final scheme = Theme.of(context).colorScheme;

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
            // Speak button for AI replies
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
