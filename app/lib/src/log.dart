// The problem log: what Paattu tried and what went wrong (stream lookups,
// the player's errors, failed searches, uncaught exceptions), kept in
// paattu.log in the app's folder so it can be saved from Settings and sent
// with a bug report. Lines also go to the console (adb logcat on Android).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

final problemLog = ProblemLog();

class ProblemLog {
  /// Bigger than this at start, the file keeps only its newest [_keep] bytes.
  static const _limit = 512 * 1024;
  static const _keep = 256 * 1024;

  File? _file;
  final _pending = StringBuffer();
  Timer? _flushTimer;
  Future<void> _writing = Future.value();

  /// Where the log is written, once [start] has run.
  File? get file => _file;

  /// Start writing to [file], after the lines logged so far.
  Future<void> start(File file, {required String header}) async {
    try {
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() > _limit) {
        final bytes = await file.readAsBytes();
        var tail = bytes.sublist(bytes.length - _keep);
        final newline = tail.indexOf(10);
        if (newline >= 0) tail = tail.sublist(newline + 1);
        await file.writeAsBytes(tail, flush: true);
      }
      _file = file;
    } catch (error) {
      debugPrint('log: $error');
    }
    final before = _pending.toString();
    _pending
      ..clear()
      ..write('\n=== $header\n')
      ..write(before);
    _flushSoon();
  }

  void info(String what) => _add('  ', what);

  void warn(String what) => _add('! ', what);

  /// [what] went wrong: [error], with where it was thrown when there's a [stack].
  void error(String what, [Object? error, StackTrace? stack]) {
    final text = error == null ? what : '$what: ${_oneLine(error)}';
    _add('!!', stack == null ? text : '$text\n${_shortStack(stack)}');
  }

  void _add(String mark, String text) {
    final line = '${_time()} $mark $text';
    debugPrint('paattu $line');
    _pending.writeln(line);
    _flushSoon();
  }

  void _flushSoon() {
    if (_file == null) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), () => unawaited(flush()));
  }

  /// Write what's waiting to the file.
  Future<void> flush() {
    final file = _file;
    if (file == null || _pending.isEmpty) return _writing;
    final text = _pending.toString();
    _pending.clear();
    return _writing = _writing.then((_) => file.writeAsString(text, mode: FileMode.append, flush: true)).catchError((Object e) {
      debugPrint('log: $e');
      return file;
    });
  }

  /// Everything in the log, oldest first.
  Future<String> text() async {
    await flush();
    final file = _file;
    if (file == null || !await file.exists()) return _pending.toString();
    return file.readAsString();
  }

  Future<void> clear() async {
    await flush();
    final file = _file;
    if (file != null && await file.exists()) await file.writeAsString('');
  }

  static String _time() {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
  }

  static String _oneLine(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 600 ? '${text.substring(0, 597)}…' : text;
  }

  /// The first frames of a stack, which say where it went wrong.
  static String _shortStack(StackTrace stack) =>
      stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(8).map((l) => '      $l').join('\n');
}
