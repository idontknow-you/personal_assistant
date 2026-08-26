import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'pinned_http_client.dart';

/// Talks to the Personal OS Flask backend.
///
/// Configure [baseUrl] to point to your deployed backend (e.g. Render URL)
/// or http://localhost:5000 for local development.
///
/// API keys stay server-side only — the app never holds a Gemini key.
class ApiService {
  /// Set this to your deployed backend URL.
  /// For local dev: http://10.0.2.2:5000 (Android emulator) or
  /// http://localhost:5000 (desktop/device).
  static String baseUrl = 'https://personal-os-prg4.onrender.com';

  /// Returns a Firebase ID token for the current user, or null if signed out.
  static Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// POST request with Firebase auth header.
  static Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _getIdToken();
    if (token == null) return null;

    // 55s timeout — a little under Render's documented ~60s worst-case
    // cold start, so a sleeping free-tier backend gets a real chance to
    // wake up and answer instead of timing out just before it responds.
    final response = await PinnedHttpClient.client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 55));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Send a chat message and get the full response (may include functionCalls).
  static Future<Map<String, dynamic>?> chatFull(
    String message, {
    List<Map<String, dynamic>>? history,
  }) async {
    final result = await _post('/api/chat', {
      'message': message,
      'history': history ?? [],
    });
    if (result == null) throw Exception('Backend returned empty response');
    return result;
  }

  /// Send function results back to get a natural language reply.
  static Future<Map<String, dynamic>?> chatWithFunctionResults(
    String originalMessage,
    List<Map<String, dynamic>> functionCalls,
    List<Map<String, dynamic>> functionResults, {
    List<Map<String, dynamic>>? history,
  }) async {
    return await _post('/api/chat', {
      'message': originalMessage,
      'history': history ?? [],
      'functionCalls': functionCalls,
      'functionResults': functionResults,
    });
  }

  /// Send a chat message and get a text reply (convenience wrapper).
  static Future<String?> chat(
    String message, {
    List<Map<String, dynamic>>? history,
  }) async {
    final result = await chatFull(message, history: history);
    return result?['reply'] as String?;
  }

  /// Auto-sort brain dump entries via Gemini.
  static Future<List<Map<String, dynamic>>?> autoSort(
    List<String> entries,
  ) async {
    final result = await _post('/api/auto-sort', {
      'entries': entries,
    });
    if (result == null) return null;
    final results = result['results'];
    if (results is List) {
      return results.cast<Map<String, dynamic>>();
    }
    return null;
  }

  /// Analyze entries about a person via Gemini.
  static Future<Map<String, String>?> analyzePerson(
    List<Map<String, String>> entries,
  ) async {
    final result = await _post('/api/analyze-person', {
      'entries': entries,
    });
    if (result == null) return null;
    return result.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  /// Get weekly review summary from Gemini.
  static Future<String?> getWeeklyReview({
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> notes,
    required int streak,
  }) async {
    final result = await _post('/api/weekly-review', {
      'tasks': tasks,
      'habits': habits,
      'notes': notes,
      'streak': streak,
      'period': 'last 7 days',
    });
    return result?['review'] as String?;
  }

  /// Semantic search across user's entries.
  static Future<List<Map<String, dynamic>>?> semanticSearch(
    String query, {
    required List<Map<String, dynamic>> entries,
  }) async {
    final result = await _post('/api/semantic-search', {
      'query': query,
      'entries': entries,
    });
    if (result == null) return null;
    final results = result['results'];
    if (results is List) {
      return results.cast<Map<String, dynamic>>();
    }
    return null;
  }
}