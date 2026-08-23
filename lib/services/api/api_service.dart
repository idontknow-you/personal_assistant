import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Talks to the Personal OS Flask backend.
///
/// Configure [baseUrl] to point to your deployed backend (e.g. Render URL)
/// or http://localhost:5000 for local development.
class ApiService {
  /// Set this to your deployed backend URL.
  /// For local dev: http://10.0.2.2:5000 (Android emulator) or
  /// http://localhost:5000 (desktop/device).
  static String baseUrl = 'http://10.120.175.146:5000';

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

    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Send a chat message and get a reply.
  static Future<String?> chat(
    String message, {
    List<Map<String, dynamic>>? history,
  }) async {
    final result = await _post('/api/chat', {
      'message': message,
      'history': history ?? [],
    });
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
}
