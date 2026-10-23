import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Copies chat attachments into the app's documents directory so history keeps
/// working after the image picker cache is cleared.
class ChatImages {
  ChatImages._();

  static Future<String> persist(String sourcePath) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/chat_images');
    await directory.create(recursive: true);
    final extension = _extension(sourcePath);
    final base = DateTime.now().microsecondsSinceEpoch;
    final target = File('${directory.path}/${base}_$base$extension');
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  static Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort; stale files are harmless.
    }
  }

  static String mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _extension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.gif')) return '.gif';
    if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) return '.jpg';
    return '.jpg';
  }
}
