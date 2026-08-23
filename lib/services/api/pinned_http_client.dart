import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP client with certificate pinning for the Personal OS backend.
///
/// Pins the SHA-256 hashes of expected TLS certificates.
/// If the backend cert changes, update the pins below. Get new pins with:
///   echo | openssl s_client -connect HOST:443 -showcerts 2>/dev/null | \
///     awk '/BEGIN CERTIFICATE/{n++} n==1{print}' | \
///     openssl x509 -outform der | openssl sha256 -binary | base64
class PinnedHttpClient {
  /// SHA-256 hashes of expected certificates (base64-encoded).
  static const Set<String> _pins = {
    'BB7Exp9mdxl7TvHAZ0IRZPSyadon8vUwKSyruwUfwbE=', // leaf
    'HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=', // intermediate
  };

  static http.Client? _cachedClient;

  /// Get a pinned HTTP client. Reuses the same client.
  static http.Client get client {
    if (_cachedClient != null) return _cachedClient!;

    final ioClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        final pin = base64Encode(
          crypto.sha256.convert(cert.der).bytes,
        );
        return _pins.contains(pin);
      };

    _cachedClient = IOClient(ioClient);
    return _cachedClient!;
  }
}
