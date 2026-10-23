import 'package:intl/intl.dart';

/// Formats a server RFC3339 timestamp in the device's local timezone.
String formatLocalTime(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  return DateFormat('yyyy-MM-dd HH:mm').format(date);
}
