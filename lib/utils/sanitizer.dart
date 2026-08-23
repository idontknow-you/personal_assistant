/// Input sanitizer for user-generated content.
/// Strips HTML, script tags, and dangerous characters before
/// storing in Firestore or sending to the AI backend.
class Sanitizer {
  /// Strip HTML tags, script blocks, and control characters.
  /// Returns clean text safe for storage and AI prompts.
  static String sanitize(String input) {
    var clean = input;

    // Remove script/style blocks
    clean = clean.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');

    // Remove all HTML tags
    clean = clean.replaceAll(RegExp(r'<[^>]*>'), '');

    // Decode common HTML entities
    clean = clean
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // Remove control characters (except newlines and tabs)
    clean = clean.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // Collapse multiple whitespace
    clean = clean.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    clean = clean.replaceAll(RegExp(r'[^\S\n]+'), ' ');

    return clean.trim();
  }

  /// Sanitize a title (single line, no newlines).
  static String sanitizeTitle(String input) {
    return sanitize(input).replaceAll('\n', ' ');
  }

  /// Validate that input is not empty after sanitization.
  static bool isEmpty(String input) => sanitize(input).isEmpty;

  /// Max safe length for Firestore string fields.
  static String truncate(String input, {int maxLength = 10000}) {
    final sanitized = sanitize(input);
    if (sanitized.length <= maxLength) return sanitized;
    return '${sanitized.substring(0, maxLength)}...';
  }
}
