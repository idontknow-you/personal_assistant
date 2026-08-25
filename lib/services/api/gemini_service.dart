import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Direct client for the Gemini REST API.
///
/// Bypasses the Flask backend entirely — the phone talks straight to Google.
/// Falls back gracefully if no API key is configured.
class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const _model = 'gemini-2.0-flash';
  static const _prefsKey = 'gemini_api_key';

  static String? _cachedKey;

  // -----------------------------------------------------------------------
  // API key management
  // -----------------------------------------------------------------------

  /// Returns the stored Gemini API key, or null if not configured.
  static Future<String?> getApiKey() async {
    if (_cachedKey != null) return _cachedKey;
    final prefs = await SharedPreferences.getInstance();
    _cachedKey = prefs.getString(_prefsKey);
    return _cachedKey;
  }

  /// Save the Gemini API key to local storage.
  static Future<void> setApiKey(String key) async {
    _cachedKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, key);
  }

  /// Clear the stored API key.
  static Future<void> clearApiKey() async {
    _cachedKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Whether a key has been configured.
  static Future<bool> isConfigured() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  // -----------------------------------------------------------------------
  // Function tool definitions (matches the backend's gemini_client.py)
  // -----------------------------------------------------------------------

  static const List<Map<String, dynamic>> _functionDefs = [
    {
      'name': 'create_task',
      'description': 'Create a new task in the user\'s task list.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'Task title'},
          'priority': {
            'type': 'STRING',
            'enum': ['low', 'medium', 'high'],
            'description': 'Task priority (default: low)',
          },
          'due_date': {
            'type': 'STRING',
            'description': 'Due date in ISO format (YYYY-MM-DD). Use today if not specified.',
          },
          'notes': {'type': 'STRING', 'description': 'Optional notes for the task'},
          'repeat': {
            'type': 'STRING',
            'enum': ['none', 'daily', 'weekly'],
            'description': 'Repeat type (default: none)',
          },
        },
        'required': ['title'],
      },
    },
    {
      'name': 'complete_task',
      'description': 'Mark a task as complete or incomplete. Use this when the user says they finished a task.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'task_id': {'type': 'STRING', 'description': 'The Firestore document ID of the task'},
          'completed': {'type': 'BOOLEAN', 'description': 'true to mark complete, false to uncomplete'},
        },
        'required': ['task_id', 'completed'],
      },
    },
    {
      'name': 'create_alarm',
      'description': 'Create a new alarm. Use this when the user asks to set an alarm or reminder.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'label': {'type': 'STRING', 'description': 'Alarm label/name'},
          'hour': {'type': 'INTEGER', 'description': 'Hour in 24h format (0-23)'},
          'minute': {'type': 'INTEGER', 'description': 'Minute (0-59)'},
          'repeat_days': {
            'type': 'ARRAY',
            'items': {'type': 'INTEGER'},
            'description': 'Days to repeat (1=Mon..7=Sun). Empty array for one-time.',
          },
          'one_time_date': {
            'type': 'STRING',
            'description': 'For one-time alarms: date in ISO format (YYYY-MM-DD)',
          },
        },
        'required': ['label', 'hour', 'minute'],
      },
    },
    {
      'name': 'create_habit',
      'description': 'Create a new habit the user wants to track.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING', 'description': "Habit name (e.g. 'Exercise', 'Read 30 mins')"},
          'frequency': {
            'type': 'ARRAY',
            'items': {'type': 'INTEGER'},
            'description': 'Days to track (1=Mon..7=Sun). Empty for every day.',
          },
        },
        'required': ['name'],
      },
    },
    {
      'name': 'add_note',
      'description': 'Add a note or diary entry. Use this when the user wants to write something down, journal, or save a thought.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'Note title'},
          'content': {'type': 'STRING', 'description': 'Note content/body'},
        },
        'required': ['title', 'content'],
      },
    },
    {
      'name': 'add_braindump',
      'description': 'Add a raw brain dump entry. Use this when the user wants to quickly jot something down without categorizing it.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'text': {'type': 'STRING', 'description': 'The raw text to save'},
        },
        'required': ['text'],
      },
    },
    {
      'name': 'add_dsa_problem',
      'description': 'Add a DSA problem to track for spaced repetition review.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING', 'description': "Problem name (e.g. 'Two Sum', 'Merge Intervals')"},
          'link': {'type': 'STRING', 'description': 'Optional URL to the problem (LeetCode, etc.)'},
        },
        'required': ['name'],
      },
    },
    {
      'name': 'list_tasks',
      'description': "List the user's current tasks. Use when they ask what tasks they have, what's due, how many tasks, etc.",
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
    {
      'name': 'list_habits',
      'description': "List the user's current habits and their streaks. Use when they ask about habits.",
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
    {
      'name': 'list_alarms',
      'description': "List the user's current alarms. Use when they ask about alarms.",
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
    {
      'name': 'list_notes',
      'description': 'List the user\'s recent notes and diary entries. Use when they ask about their notes, journal entries, or what they wrote recently.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'limit': {'type': 'INTEGER', 'description': 'Max notes to return (default 10)'},
        },
      },
    },
    {
      'name': 'list_braindump',
      'description': 'List the user\'s brain dump entries. Use when they ask about their brain dumps or quick notes.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'limit': {'type': 'INTEGER', 'description': 'Max entries to return (default 10)'},
        },
      },
    },
    {
      'name': 'list_dsa_problems',
      'description': 'List the user\'s DSA problems and their review status. Use when they ask about their DSA practice.',
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
  ];

  static const _systemPrompt = '''You are Personal OS, a calm, concise personal assistant living inside a productivity app. You help with tasks, alarms, habits, notes, brain dumps, DSA problems, and general productivity.

CRITICAL RULES:
- When the user asks you to CREATE, ADD, or SET something, you MUST call the appropriate function. Do NOT just say "Done!" without calling a function.
- When the user asks what they have (tasks, habits, alarms, notes), call the list function to get the actual data, then summarize it.
- Parse natural language into the right parameters: "tomorrow" → tomorrow's ISO date, "every day" → empty frequency array, "Mon Wed Fri" → [1, 3, 5], "8:30 AM" → hour=8, minute=30, "high priority" → priority="high".
- After a function executes successfully, confirm what was created briefly.
- When you receive function results (data about tasks, habits, etc.), summarize them clearly for the user.
- Be direct and brief. No fluff, no "Great question!" preamble.
- If the user asks something outside your scope, say so honestly.

Brain dump auto-sort format — when the user asks you to sort/categorize brain dump entries, reply with ONLY a JSON array (no markdown fences, no explanation before or after). Each element:
{
  "text": "the original text",
  "category": "task" | "note" | "diary" | "dsa" | "people" | "braindump",
  "title": "short summary title (<= 60 chars)"
}''';

  // -----------------------------------------------------------------------
  // Chat (with function calling support)
  // -----------------------------------------------------------------------

  /// Send a chat message. Returns:
  ///   `{"reply": "..."}` for a text response,
  ///   `{"functionCalls": [...]}` if Gemini wants to call functions,
  ///   `{"reply": "...", "functionCalls": [...]}` if both.
  /// Send a POST request with auto-retry for rate limits (429 / 4029).
  static Future<http.Response> _postWithRetry(
    Uri uri,
    Map<String, dynamic> body, {
    int maxRetries = 3,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      // Rate limited — extract wait time and retry
      if (response.statusCode == 429 || response.statusCode == 4029) {
        if (attempt < maxRetries) {
          // Parse retry delay from error message, default to 30s
          final waitSeconds = _parseRetryDelay(response.body) ?? (30 * (attempt + 1));
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }
      }

      return response;
    }
    // Shouldn't reach here, but just in case
    throw GeminiException('Max retries exceeded');
  }

  /// Extract retry delay from Gemini error response.
  static int? _parseRetryDelay(String body) {
    try {
      final data = jsonDecode(body);
      final details = data['error']?['details'] as List?;
      if (details != null) {
        for (final d in details) {
          final msg = d['message'] as String? ?? '';
          // "Please retry in 42.38s"
          final match = RegExp(r'retry in (\d+\.?\d*)s').firstMatch(msg);
          if (match != null) {
            return (double.parse(match.group(1)!)).ceil();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> chat(
    String message, {
    List<Map<String, dynamic>>? history,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiException('No Gemini API key configured');
    }

    final contents = _buildContents(message, history);
    final body = _buildRequestBody(contents, includeTools: true);

    try {
      final response = await _postWithRetry(
        Uri.parse('$_baseUrl/models/$_model:generateContent?key=$apiKey'),
        body,
      );

      if (response.statusCode != 200) {
        throw GeminiException(
          'Gemini API error ${response.statusCode}: ${response.body}',
        );
      }

      return _parseResponse(jsonDecode(response.body));
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException('Network error: $e');
    }
  }

  /// Continue a chat after function execution, passing results back to Gemini.
  static Future<Map<String, dynamic>> continueChat(
    String message, {
    List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? functionCalls,
    List<Map<String, dynamic>>? functionResults,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiException('No Gemini API key configured');
    }

    final contents = _buildContentsWithFunctionResults(
      message, history, functionCalls, functionResults,
    );
    final body = _buildRequestBody(contents, includeTools: false);

    final response = await _postWithRetry(
      Uri.parse('$_baseUrl/models/$_model:generateContent?key=$apiKey'),
      body,
    );

    if (response.statusCode != 200) {
      throw GeminiException(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    return _parseResponse(jsonDecode(response.body));
  }

  // -----------------------------------------------------------------------
  // Single-prompt generation (for auto-sort, analyze, review, search)
  // -----------------------------------------------------------------------

  /// Send a single prompt and return the raw text response.
  static Future<String> generate(String prompt) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiException('No Gemini API key configured');
    }

    final body = {
      'contents': [
        {'role': 'user', 'parts': [{'text': prompt}]},
      ],
    };

    final response = await _postWithRetry(
      Uri.parse('$_baseUrl/models/$_model:generateContent?key=$apiKey'),
      body,
    );

    if (response.statusCode != 200) {
      throw GeminiException(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return '';
    }

    final content = candidates[0]['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return '';

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part['text'] != null) {
        buffer.write(part['text']);
      }
    }
    return buffer.toString();
  }

  /// Auto-sort brain dump entries.
  static Future<List<Map<String, dynamic>>> autoSort(List<String> entries) async {
    final joined = entries.map((t) => '- $t').join('\n');
    final prompt =
        'Sort these brain dump entries into categories. '
        'Reply with ONLY a JSON array, no markdown fences:\n\n$joined';

    final raw = (await generate(prompt)).trim();
    final cleaned = _stripMarkdownFences(raw);

    try {
      final parsed = jsonDecode(cleaned);
      if (parsed is List) {
        return parsed.cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // Fall through to default
    }

    return entries
        .map((t) => {'text': t, 'category': 'braindump', 'title': t.substring(0, t.length.clamp(0, 60))})
        .toList();
  }

  /// Analyze entries about a person.
  static Future<Map<String, String>> analyzePerson(
    List<Map<String, String>> entries,
  ) async {
    const analysisPrompt = '''You are analyzing text entries someone wrote about a person in their life.
Provide analysis in these sections. Write in second person ("you"). Be honest and direct.

## Patterns
What behavioral patterns do you notice?

## Red Flags
Any concerning behaviors? If none, say so clearly.

## Emotional Reflection
How is this person likely making the user feel?

## Communication Style
How does this person communicate?

---
Entries to analyze:
''';

    final entryTexts = entries
        .take(30)
        .map((e) => '[${e['sourceType'] ?? 'unknown'}] ${e['text'] ?? ''}')
        .join('\n');

    final response = await generate('$analysisPrompt\n$entryTexts');
    return _parseAnalysisSections(response);
  }

  /// Get weekly review summary.
  static Future<String> getWeeklyReview({
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> notes,
    required int streak,
  }) async {
    final taskSummary =
        '${tasks.length} tasks total, ${tasks.where((t) => t['completed'] == true).length} completed';

    final habitLines = habits
        .map((h) => '  - ${h['name']}: streak ${h['currentStreak'] ?? 0} days')
        .join('\n');
    final habitSummary = habitLines.isNotEmpty ? habitLines : '  No habits tracked';

    final moodCounts = <String, int>{};
    for (final n in notes) {
      final m = n['mood'] as String? ?? 'unknown';
      moodCounts[m] = (moodCounts[m] ?? 0) + 1;
    }
    final moodSummary = moodCounts.isNotEmpty
        ? moodCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')
        : 'No mood data';

    final prompt = '''You are a personal productivity coach. Write a brief weekly review:

TASKS: $taskSummary
STREAK: $streak days
HABITS:
$habitSummary
MOODS THIS WEEK: $moodSummary
NOTES WRITTEN: ${notes.length}

Write a concise, encouraging weekly review (4-6 sentences max):
1. Highlight what went well
2. Note any patterns
3. Suggest one concrete improvement for next week
4. End with a motivational note

Be direct and personal. Use "you" language. No fluff.''';

    return await generate(prompt);
  }

  /// Semantic search across user's entries.
  static Future<List<Map<String, dynamic>>> semanticSearch(
    String query, {
    required List<Map<String, dynamic>> entries,
  }) async {
    if (entries.isEmpty) return [];

    final entriesText = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final type = e['type'] ?? 'unknown';
      final title = e['title'] ?? '';
      final text = (e['text'] ?? '').toString().substring(0, (e['text'] ?? '').toString().length.clamp(0, 200));
      final mood = e['mood'] ?? '';
      final date = e['date'] ?? '';
      var meta = '[$type]';
      if (title.isNotEmpty) meta += ' $title';
      if (mood.isNotEmpty) meta += ' (mood: $mood)';
      if (date.isNotEmpty) meta += ' $date';
      entriesText.writeln('$i: $meta — $text');
    }

    final prompt = '''You are a semantic search engine for a personal productivity app.

The user searched for: "$query"

Here are their entries:
$entriesText

Find the entries most relevant to the search query. Rank by relevance.

Reply with ONLY a JSON array (no markdown fences). Each result:
{
  "index": 0,
  "relevance": "high" | "medium" | "low",
  "summary": "1-2 sentence explanation of why this matches"
}

Include ALL entries with "medium" or "high" relevance. Exclude "low" relevance.
If nothing is relevant, return an empty array [].
Max 8 results.''';

    final raw = (await generate(prompt)).trim();
    final cleaned = _stripMarkdownFences(raw);

    List<dynamic> ranked;
    try {
      ranked = jsonDecode(cleaned) as List;
    } catch (_) {
      return [];
    }

    final results = <Map<String, dynamic>>[];
    for (final r in ranked) {
      if (r is! Map) continue;
      final idx = r['index'] as int? ?? -1;
      if (idx >= 0 && idx < entries.length) {
        final e = entries[idx];
        results.add({
          'id': e['id'] ?? '',
          'type': e['type'] ?? '',
          'title': e['title'] ?? '',
          'text': (e['text'] ?? '').toString().substring(0, ((e['text'] ?? '').toString().length).clamp(0, 200)),
          'mood': e['mood'] ?? '',
          'date': e['date'] ?? '',
          'relevance': r['relevance'] ?? 'medium',
          'summary': r['summary'] ?? '',
        });
      }
    }
    return results;
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  static Map<String, dynamic> _buildRequestBody(
    List<Map<String, dynamic>> contents, {
    required bool includeTools,
  }) {
    final body = <String, dynamic>{
      'contents': contents,
      'systemInstruction': {
        'parts': [{'text': _systemPrompt}],
      },
    };

    if (includeTools) {
      body['tools'] = [
        {
          'functionDeclarations': _functionDefs,
        },
      ];
    }

    return body;
  }

  static List<Map<String, dynamic>> _buildContents(
    String message,
    List<Map<String, dynamic>>? history,
  ) {
    final contents = <Map<String, dynamic>>[];

    if (history != null) {
      for (final entry in history) {
        final role = entry['role'] as String?;
        final parts = entry['parts'] as List?;
        if (role != null && parts != null && parts.isNotEmpty) {
          contents.add({
            'role': role,
            'parts': [{'text': parts[0]}],
          });
        }
      }
    }

    contents.add({
      'role': 'user',
      'parts': [{'text': message}],
    });

    return contents;
  }

  static List<Map<String, dynamic>> _buildContentsWithFunctionResults(
    String message,
    List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? functionCalls,
    List<Map<String, dynamic>>? functionResults,
  ) {
    final contents = <Map<String, dynamic>>[];

    // Add history
    if (history != null) {
      for (final entry in history) {
        final role = entry['role'] as String?;
        final parts = entry['parts'] as List?;
        if (role != null && parts != null && parts.isNotEmpty) {
          contents.add({
            'role': role,
            'parts': [{'text': parts[0]}],
          });
        }
      }
    }

    // Add the model's function call turn
    if (functionCalls != null && functionCalls.isNotEmpty) {
      final fcParts = functionCalls
          .map((fc) => {
                'functionCall': {
                  'name': fc['name'],
                  'args': fc['args'] ?? {},
                },
              })
          .toList();
      contents.add({'role': 'model', 'parts': fcParts});
    }

    // Add the function response turn
    if (functionResults != null && functionResults.isNotEmpty) {
      final frParts = functionResults
          .map((fr) => {
                'functionResponse': {
                  'name': fr['name'],
                  'response': fr['result'] ?? {},
                },
              })
          .toList();
      contents.add({'role': 'function', 'parts': frParts});
    }

    // Add the follow-up user message
    contents.add({
      'role': 'user',
      'parts': [
        {'text': message.isNotEmpty ? message : 'Please summarize the results for the user.'},
      ],
    });

    return contents;
  }

  static Map<String, dynamic> _parseResponse(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      result['reply'] = "I'm not sure what to do with that. Could you rephrase?";
      return result;
    }

    final content = candidates[0]['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      result['reply'] = "I'm not sure what to do with that. Could you rephrase?";
      return result;
    }

    final functionCalls = <Map<String, dynamic>>[];
    final textBuffer = StringBuffer();

    for (final part in parts) {
      if (part['functionCall'] != null) {
        final fc = part['functionCall'];
        functionCalls.add({
          'name': fc['name'],
          'args': Map<String, dynamic>.from(fc['args'] ?? {}),
        });
      } else if (part['text'] != null) {
        textBuffer.write(part['text']);
      }
    }

    if (functionCalls.isNotEmpty) {
      result['functionCalls'] = functionCalls;
    }

    final text = textBuffer.toString();
    if (text.isNotEmpty) {
      result['reply'] = text;
    }

    if (result.isEmpty) {
      result['reply'] = "I'm not sure what to do with that. Could you rephrase?";
    }

    return result;
  }

  static String _stripMarkdownFences(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.split('\n').skip(1).join('\n');
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();
    }
    return cleaned;
  }

  static Map<String, String> _parseAnalysisSections(String text) {
    final sections = <String, String>{
      'patterns': '',
      'redFlags': '',
      'emotionalReflection': '',
      'communicationStyle': '',
    };

    final keyMap = {
      'Patterns': 'patterns',
      'Red Flags': 'redFlags',
      'Red Flag': 'redFlags',
      'Emotional Reflection': 'emotionalReflection',
      'Communication Style': 'communicationStyle',
    };

    // Split by ## headers
    final parts = text.split(RegExp(r'##\s*(Patterns|Red Flags?|Emotional Reflection|Communication Style)'));

    var i = 1;
    while (i < parts.length - 1) {
      final header = parts[i].trim();
      final body = parts[i + 1].trim();
      final key = keyMap[header];
      if (key != null) {
        sections[key] = body;
      }
      i += 2;
    }

    return sections;
  }
}

/// Exception thrown by GeminiService.
class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => 'GeminiException: $message';
}
