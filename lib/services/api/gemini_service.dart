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
  static const _model = 'gemini-2.5-flash';
  static const _prefsKey = 'gemini_api_key';

  static String? _cachedKey;

  // -----------------------------------------------------------------------
  // API key management
  // -----------------------------------------------------------------------

  static Future<String?> getApiKey() async {
    if (_cachedKey != null) return _cachedKey;
    final prefs = await SharedPreferences.getInstance();
    _cachedKey = prefs.getString(_prefsKey);
    return _cachedKey;
  }

  static Future<void> setApiKey(String key) async {
    _cachedKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, key);
  }

  static Future<void> clearApiKey() async {
    _cachedKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<bool> isConfigured() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  // -----------------------------------------------------------------------
  // HTTP helper
  // -----------------------------------------------------------------------

  static Future<http.Response> _post(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    return await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
  }

  // -----------------------------------------------------------------------
  // Function tool definitions
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
            'description': 'Due date in ISO format (YYYY-MM-DD).',
          },
          'notes': {'type': 'STRING', 'description': 'Optional notes'},
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
      'description': 'Mark a task as complete or incomplete.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'task_id': {'type': 'STRING', 'description': 'Firestore document ID'},
          'completed': {'type': 'BOOLEAN', 'description': 'true to complete'},
        },
        'required': ['task_id', 'completed'],
      },
    },
    {
      'name': 'create_alarm',
      'description': 'Create a new alarm.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'label': {'type': 'STRING', 'description': 'Alarm label'},
          'hour': {'type': 'INTEGER', 'description': 'Hour 0-23'},
          'minute': {'type': 'INTEGER', 'description': 'Minute 0-59'},
          'repeat_days': {
            'type': 'ARRAY',
            'items': {'type': 'INTEGER'},
            'description': 'Days 1=Mon..7=Sun. Empty for one-time.',
          },
          'one_time_date': {'type': 'STRING', 'description': 'ISO date for one-time'},
        },
        'required': ['label', 'hour', 'minute'],
      },
    },
    {
      'name': 'create_habit',
      'description': 'Create a new habit to track.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING', 'description': 'Habit name'},
          'frequency': {
            'type': 'ARRAY',
            'items': {'type': 'INTEGER'},
            'description': 'Days 1=Mon..7=Sun. Empty for every day.',
          },
        },
        'required': ['name'],
      },
    },
    {
      'name': 'add_note',
      'description': 'Add a note or diary entry.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING', 'description': 'Note title'},
          'content': {'type': 'STRING', 'description': 'Note content'},
        },
        'required': ['title', 'content'],
      },
    },
    {
      'name': 'add_braindump',
      'description': 'Add a raw brain dump entry.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'text': {'type': 'STRING', 'description': 'Raw text to save'},
        },
        'required': ['text'],
      },
    },
    {
      'name': 'add_dsa_problem',
      'description': 'Add a DSA problem for spaced repetition.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING', 'description': 'Problem name'},
          'link': {'type': 'STRING', 'description': 'Optional URL'},
        },
        'required': ['name'],
      },
    },
    {
      'name': 'list_tasks',
      'description': 'List current tasks.',
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
    {
      'name': 'list_habits',
      'description': 'List current habits and streaks.',
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
    {
      'name': 'list_alarms',
      'description': 'List current alarms.',
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
    {
      'name': 'list_notes',
      'description': 'List recent notes and diary entries.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'limit': {'type': 'INTEGER', 'description': 'Max notes (default 10)'},
        },
      },
    },
    {
      'name': 'list_braindump',
      'description': 'List brain dump entries.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'limit': {'type': 'INTEGER', 'description': 'Max entries (default 10)'},
        },
      },
    },
    {
      'name': 'list_dsa_problems',
      'description': 'List DSA problems and review status.',
      'parameters': {'type': 'OBJECT', 'properties': {}},
    },
  ];

  static const _systemPrompt = '''You are Personal OS, a calm, concise personal assistant.

CRITICAL RULES:
- When the user asks to CREATE, ADD, or SET something, you MUST call the appropriate function.
- When the user asks what they have, call the list function to get the actual data.
- Parse natural language: "tomorrow" → ISO date, "every day" → empty array, "Mon Wed Fri" → [1,3,5], "8:30 AM" → hour=8, minute=30.
- Be direct and brief. No fluff.''';

  // -----------------------------------------------------------------------
  // Chat
  // -----------------------------------------------------------------------

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
      final response = await _post(
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

    final response = await _post(
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
  // Single-prompt generation
  // -----------------------------------------------------------------------

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

    final response = await _post(
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
    if (candidates == null || candidates.isEmpty) return '';

    final content = candidates[0]['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return '';

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part['text'] != null) buffer.write(part['text']);
    }
    return buffer.toString();
  }

  static Future<List<Map<String, dynamic>>> autoSort(List<String> entries) async {
    final joined = entries.map((t) => '- $t').join('\n');
    final prompt = 'Sort these brain dump entries into categories. Reply with ONLY a JSON array, no markdown fences:\n\n$joined';
    final raw = (await generate(prompt)).trim();
    final cleaned = _stripMarkdownFences(raw);
    try {
      final parsed = jsonDecode(cleaned);
      if (parsed is List) return parsed.cast<Map<String, dynamic>>();
    } catch (_) {}
    return entries.map((t) => {'text': t, 'category': 'braindump', 'title': t.substring(0, t.length.clamp(0, 60))}).toList();
  }

  static Future<Map<String, String>> analyzePerson(List<Map<String, String>> entries) async {
    const analysisPrompt = '''You are analyzing text entries about a person. Write in second person. Provide sections: Patterns, Red Flags, Emotional Reflection, Communication Style.

Entries to analyze:
''';
    final entryTexts = entries.take(30).map((e) => '[${e['sourceType'] ?? 'unknown'}] ${e['text'] ?? ''}').join('\n');
    final response = await generate('$analysisPrompt\n$entryTexts');
    return _parseAnalysisSections(response);
  }

  static Future<String> getWeeklyReview({
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> notes,
    required int streak,
  }) async {
    final taskSummary = '${tasks.length} tasks total, ${tasks.where((t) => t['completed'] == true).length} completed';
    final habitLines = habits.map((h) => '  - ${h['name']}: streak ${h['currentStreak'] ?? 0} days').join('\n');
    final moodCounts = <String, int>{};
    for (final n in notes) { final m = n['mood'] as String? ?? 'unknown'; moodCounts[m] = (moodCounts[m] ?? 0) + 1; }
    final moodSummary = moodCounts.isNotEmpty ? moodCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ') : 'No mood data';

    final prompt = '''Write a brief weekly review (4-6 sentences):
TASKS: $taskSummary | STREAK: $streak days | HABITS:\n${habitLines.isNotEmpty ? habitLines : 'None'} | MOODS: $moodSummary | NOTES: ${notes.length}
Be direct and personal. Highlight wins, note patterns, suggest one improvement.''';
    return await generate(prompt);
  }

  static Future<List<Map<String, dynamic>>> semanticSearch(String query, {required List<Map<String, dynamic>> entries}) async {
    if (entries.isEmpty) return [];
    final entriesText = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      entriesText.writeln('$i: [${e['type'] ?? 'unknown'}] ${e['title'] ?? ''} — ${(e['text'] ?? '').toString().substring(0, ((e['text'] ?? '').toString().length).clamp(0, 200))}');
    }
    final prompt = 'Search query: "$query"\n\nEntries:\n$entriesText\n\nReturn ONLY a JSON array of matching entries with index, relevance (high/medium/low), and summary. Exclude low relevance. Max 8 results.';
    final raw = (await generate(prompt)).trim();
    final cleaned = _stripMarkdownFences(raw);
    List<dynamic> ranked;
    try { ranked = jsonDecode(cleaned) as List; } catch (_) { return []; }

    final results = <Map<String, dynamic>>[];
    for (final r in ranked) {
      if (r is! Map) continue;
      final idx = r['index'] as int? ?? -1;
      if (idx >= 0 && idx < entries.length) {
        final e = entries[idx];
        results.add({
          'id': e['id'] ?? '', 'type': e['type'] ?? '', 'title': e['title'] ?? '',
          'text': (e['text'] ?? '').toString().substring(0, ((e['text'] ?? '').toString().length).clamp(0, 200)),
          'mood': e['mood'] ?? '', 'date': e['date'] ?? '',
          'relevance': r['relevance'] ?? 'medium', 'summary': r['summary'] ?? '',
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
      body['tools'] = [{'functionDeclarations': _functionDefs}];
    }
    return body;
  }

  static List<Map<String, dynamic>> _buildContents(String message, List<Map<String, dynamic>>? history) {
    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      for (final entry in history) {
        final role = entry['role'] as String?;
        final parts = entry['parts'] as List?;
        if (role != null && parts != null && parts.isNotEmpty) {
          contents.add({'role': role, 'parts': [{'text': parts[0]}]});
        }
      }
    }
    contents.add({'role': 'user', 'parts': [{'text': message}]});
    return contents;
  }

  static List<Map<String, dynamic>> _buildContentsWithFunctionResults(
    String message, List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? functionCalls, List<Map<String, dynamic>>? functionResults,
  ) {
    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      for (final entry in history) {
        final role = entry['role'] as String?;
        final parts = entry['parts'] as List?;
        if (role != null && parts != null && parts.isNotEmpty) {
          contents.add({'role': role, 'parts': [{'text': parts[0]}]});
        }
      }
    }
    if (functionCalls != null && functionCalls.isNotEmpty) {
      contents.add({
        'role': 'model',
        'parts': functionCalls.map((fc) => {'functionCall': {'name': fc['name'], 'args': fc['args'] ?? {}}}).toList(),
      });
    }
    if (functionResults != null && functionResults.isNotEmpty) {
      contents.add({
        'role': 'function',
        'parts': functionResults.map((fr) => {'functionResponse': {'name': fr['name'], 'response': fr['result'] ?? {}}}).toList(),
      });
    }
    contents.add({'role': 'user', 'parts': [{'text': message.isNotEmpty ? message : 'Summarize the results for the user.'}]});
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
        functionCalls.add({'name': fc['name'], 'args': Map<String, dynamic>.from(fc['args'] ?? {})});
      } else if (part['text'] != null) {
        textBuffer.write(part['text']);
      }
    }
    if (functionCalls.isNotEmpty) result['functionCalls'] = functionCalls;
    final text = textBuffer.toString();
    if (text.isNotEmpty) result['reply'] = text;
    if (result.isEmpty) result['reply'] = "I'm not sure what to do with that. Could you rephrase?";
    return result;
  }

  static String _stripMarkdownFences(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.split('\n').skip(1).join('\n');
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
      cleaned = cleaned.trim();
    }
    return cleaned;
  }

  static Map<String, String> _parseAnalysisSections(String text) {
    final sections = <String, String>{'patterns': '', 'redFlags': '', 'emotionalReflection': '', 'communicationStyle': ''};
    final keyMap = {'Patterns': 'patterns', 'Red Flags': 'redFlags', 'Red Flag': 'redFlags', 'Emotional Reflection': 'emotionalReflection', 'Communication Style': 'communicationStyle'};
    final parts = text.split(RegExp(r'##\s*(Patterns|Red Flags?|Emotional Reflection|Communication Style)'));
    var i = 1;
    while (i < parts.length - 1) {
      final key = keyMap[parts[i].trim()];
      if (key != null) sections[key] = parts[i + 1].trim();
      i += 2;
    }
    return sections;
  }
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => 'GeminiException: $message';
}
