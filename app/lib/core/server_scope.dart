import 'dart:convert';

/// Derives a short, stable prefix for data that belongs to one server.
///
/// The built-in server keeps the historical unprefixed keys, so existing
/// installs keep their saved accounts, token, cache, chat history and AI
/// configuration. Every user-configured server gets its own prefix, which
/// isolates its local data from the built-in server and from other servers.
class ServerScope {
  ServerScope._();

  static String _prefix = '';

  /// Prefix to prepend to every server-bound local storage key. Empty for the
  /// built-in server.
  static String get prefix => _prefix;

  static void setFor(String serverUrl, {required bool isCustom}) {
    _prefix = isCustom ? '${_hash(normalize(serverUrl))}_' : '';
  }

  /// Normalizes a server base URL for identity comparison.
  static String normalize(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme.isNotEmpty && uri.host.isNotEmpty) {
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      final defaultPort =
          (scheme == 'http' && uri.port == 80) ||
              (scheme == 'https' && uri.port == 443);
      final port = uri.hasPort && !defaultPort ? ':${uri.port}' : '';
      var path = uri.path;
      while (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      return '$scheme://$host$port$path';
    }
    var normalized = value;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  /// FNV-1a 32-bit hash rendered as 8 hex characters.
  static String _hash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
