import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'pinned_http_client.dart';
import 'gemini_service.dart';

/// Hybrid API service — tries direct Gemini calls first (fast, no cold start),
/// falls back to the Flask backend on Render if direct fails.
class ApiService {
  /// Backend URL (fallback).
  static String baseUrl = 'https://personal-os-prg4.onrender.com';

  /// Whether to prefer direct Gemini (set to false to force backend).
  static bool preferDirect = true;

  // -----------------------------------------------------------------------
  // Firebase auth helper (only needed for backend fallback)
  // -----------------------------------------------------------------------

  static Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  static Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _getIdToken();
    if (token == null) return null;

    // 90s timeout — Render free tier cold starts can take 30-60s
    final response = await PinnedHttpClient.client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Chat — direct first, backend fallback
  // -----------------------------------------------------------------------

  static Future<Map<String, dynamic>?> chatFull(
    String message, {
    List<Map<String, dynamic>>? history,
  }) async {
    // Try direct Gemini first
    if (preferDirect && await GeminiService.isConfigured()) {
      try {
        return await GeminiService.chat(message, history: history);
      } catch (_) {
        // Fall through to backend
      }
    }

    // Fallback to backend
    return await _post('/api/chat', {
      'message': message,
      'history': history ?? [],
    });
  }

  static Future<Map<String, dynamic>?> chatWithFunctionResults(
    String originalMessage,
    List<Map<String, dynamic>> functionCalls,
    List<Map<String, dynamic>> functionResults, {
    List<Map<String, dynamic>>? history,
  }) async {
    // Try direct Gemini first
    if (preferDirect && await GeminiService.isConfigured()) {
      try {
        return await GeminiService.continueChat(
          originalMessage,
          history: history,
          functionCalls: functionCalls,
          functionResults: functionResults,
        );
      } catch (_) {
        // Fall through to backend
      }
    }

    // Fallback to backend
    return await _post('/api/chat', {
      'message': originalMessage,
      'history': history ?? [],
      'functionCalls': functionCalls,
      'functionResults': functionResults,
    });
  }

  static Future<String?> chat(
    String message, {
    List<Map<String, dynamic>>? history,
  }) async {
    final result = await chatFull(message, history: history);
    return result?['reply'] as String?;
  }

  // -----------------------------------------------------------------------
  // Auto-sort — direct first, backend fallback
  // -----------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>?> autoSort(
    List<String> entries,
  ) async {
    if (preferDirect && await GeminiService.isConfigured()) {
      try {
        return await GeminiService.autoSort(entries);
      } catch (e) {
        print('⚠️ Direct Gemini autoSort failed, falling back to backend: $e');
      }
    }

    final result = await _post('/api/auto-sort', {'entries': entries});
    if (result == null) return null;
    final results = result['results'];
    if (results is List) {
      return results.cast<Map<String, dynamic>>();
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Analyze person — direct first, backend fallback
  // -----------------------------------------------------------------------

  static Future<Map<String, String>?> analyzePerson(
    List<Map<String, String>> entries,
  ) async {
    if (preferDirect && await GeminiService.isConfigured()) {
      try {
        return await GeminiService.analyzePerson(entries);
      } catch (e) {
        print('⚠️ Direct Gemini analyzePerson failed, falling back to backend: $e');
      }
    }

    final result = await _post('/api/analyze-person', {'entries': entries});
    if (result == null) return null;
    return result.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  // -----------------------------------------------------------------------
  // Weekly review — direct first, backend fallback
  // -----------------------------------------------------------------------

  static Future<String?> getWeeklyReview({
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> notes,
    required int streak,
  }) async {
    if (preferDirect && await GeminiService.isConfigured()) {
      try {
        return await GeminiService.getWeeklyReview(
          tasks: tasks,
          habits: habits,
          notes: notes,
          streak: streak,
        );
      } catch (e) {
        print('⚠️ Direct Gemini weeklyReview failed, falling back to backend: $e');
      }
    }

    final result = await _post('/api/weekly-review', {
      'tasks': tasks,
      'habits': habits,
      'notes': notes,
      'streak': streak,
      'period': 'last 7 days',
    });
    return result?['review'] as String?;
  }

  // -----------------------------------------------------------------------
  // Semantic search — direct first, backend fallback
  // -----------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>?> semanticSearch(
    String query, {
    required List<Map<String, dynamic>> entries,
  }) async {
    if (preferDirect && await GeminiService.isConfigured()) {
      try {
        return await GeminiService.semanticSearch(query, entries: entries);
      } catch (e) {
        print('⚠️ Direct Gemini semanticSearch failed, falling back to backend: $e');
      }
    }

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
