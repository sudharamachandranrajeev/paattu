// Small helpers shared by the sources, the library and the UI.

import 'dart:math';

typedef Json = Map<String, dynamic>;

/// A JSON object. Maps decoded from JSON (and the ones the app builds) are
/// returned as they are, so changes made through the result stick.
Json asJson(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return <String, dynamic>{};
}

List<dynamic> asList(Object? value) => value is List ? value : const [];

List<String> asStrings(Object? value) =>
    value is List ? value.where((e) => e != null).map((e) => '$e').toList() : <String>[];

String asString(Object? value) => value == null ? '' : '$value';

int? toInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.round() : null;
  if (value is String) {
    final number = double.tryParse(value.trim());
    return number != null && number.isFinite ? number.truncate() : null;
  }
  return null;
}

/// Python-style strip of the given characters from both ends.
String stripChars(String text, String chars) {
  var start = 0;
  var end = text.length;
  while (start < end && chars.contains(text[start])) {
    start++;
  }
  while (end > start && chars.contains(text[end - 1])) {
    end--;
  }
  return text.substring(start, end);
}

final _spaces = RegExp(r'\s+');

/// Whitespace collapsed to single spaces, trimmed.
String squash(String? text) => (text ?? '').replaceAll(_spaces, ' ').trim();

const _entities = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', '#39': "'"};
final _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

/// The HTML entities sites put in titles ("Malare (From &quot;Premam&quot;)").
String htmlUnescape(String? text) {
  if (text == null || !text.contains('&')) return text ?? '';
  return text.replaceAllMapped(_entityRe, (m) {
    final name = m.group(1)!;
    if (name.startsWith('#x') || name.startsWith('#X')) {
      final code = int.tryParse(name.substring(2), radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }
    if (name.startsWith('#')) {
      final code = int.tryParse(name.substring(1));
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }
    return _entities[name.toLowerCase()] ?? m.group(0)!;
  });
}

/// Names cleaned and without repeats, in order.
List<String> uniqueNames(Iterable<String?> names) {
  final out = <String>[];
  for (final raw in names) {
    final name = squash(htmlUnescape(raw));
    if (name.isNotEmpty && !out.contains(name)) out.add(name);
  }
  return out;
}

/// "3:07", "1:02:03".
String formatTime(num? seconds) {
  if (seconds == null || seconds.isNaN || seconds < 0) return '0:00';
  final s = seconds.floor();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final rest = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$rest' : '$m:$rest';
}

String formatDuration(Duration? d) => formatTime(d == null ? null : d.inMilliseconds / 1000);

/// "1 song", "12 songs".
String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// 12400 → 12K, 1250000 → 1.3M (as Model.js formatCount).
String shortCount(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1).replaceFirst(RegExp(r'\.0$'), '')}M'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceFirst(RegExp(r'\.0$'), '')}K'
        : '$n';

/// The time as library.json writes it: 2026-10-13T08:30:00Z.
String nowStamp() {
  final t = DateTime.now().toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

final _random = Random.secure();

/// Random hex, like Python's secrets.token_hex.
String tokenHex(int bytes) =>
    List.generate(bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// A short, human reason for an error.
String errorText(Object error) {
  var text = error.toString();
  for (final prefix in ['Exception: ', 'SourceException: ', 'HttpException: ', 'SocketException: ']) {
    if (text.startsWith(prefix)) text = text.substring(prefix.length);
  }
  final lower = text.toLowerCase();
  if (lower.contains('failed host lookup') || lower.contains('network is unreachable')) {
    return "can't reach the internet";
  }
  if (lower.contains('timed out') || lower.contains('timeoutexception')) return "didn't answer in time";
  return text.length > 160 ? '${text.substring(0, 157)}…' : text;
}

/// Thrown for problems worth showing as they are.
class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}
