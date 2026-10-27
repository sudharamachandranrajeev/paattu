// Saving the app's own files (the library, the history, the settings, the
// kept songs' index): whole or not at all, one write at a time for each, all
// of them before the app goes, and a damaged one set aside, never written
// over.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _writing = <String, Future<void>>{};
final _flushes = <Future<void> Function()>[];

/// Put [text] in [file] whole: written to a file of its own beside it, then
/// moved over it, so neither a crash nor a save at the same moment (the
/// timer's and the one on closing, or a second window's) leaves half of it.
/// Saves of one file run one after another, the last one's text last.
Future<void> writeWhole(File file, String text) => _write(file, (tmp) => tmp.writeAsString(text, flush: true));

/// Put [value] in [file] as JSON, whole (as [writeWhole]), worked out a
/// piece at a time with the screen drawn in between: a big library takes a
/// tenth of a second or more to write out, a pause the app (and a fade
/// between songs) would show. Handing it to another isolate costs as long
/// again in copying it there. What changes while it's written may or may
/// not be in it; the change saves again after.
Future<void> writeJsonGently(File file, Object? value) => _write(file, (tmp) async {
      final sink = tmp.openWrite();
      try {
        await _encodeGently(value, sink);
        await sink.flush();
      } finally {
        await sink.close();
      }
    });

Future<void> _write(File file, Future<void> Function(File tmp) write) {
  final path = file.path;
  final done = (_writing[path] ?? Future<void>.value()).then((_) async {
    await file.parent.create(recursive: true);
    final tmp = File('$path.$pid.tmp');
    await write(tmp);
    await tmp.rename(path);
  });
  // The next save runs whether or not this one failed.
  final settled = done.then<void>((_) {}, onError: (Object _) {});
  _writing[path] = settled;
  unawaited(settled.then((_) {
    if (identical(_writing[path], settled)) _writing.remove(path);
  }));
  return done;
}

/// [value] as JSON into [sink]: the outer two levels and any big map or list
/// an entry at a time, the rest whole, letting the event loop (frames, the player) run every few
/// milliseconds. Keys are read first, so a map changed meanwhile can't throw.
Future<void> _encodeGently(Object? value, IOSink sink) async {
  final buffer = StringBuffer();
  final clock = Stopwatch()..start();
  Future<void> put(String text) async {
    buffer.write(text);
    if (buffer.length >= 1 << 16) {
      sink.add(utf8.encode(buffer.toString()));
      buffer.clear();
    }
    if (clock.elapsedMilliseconds >= 4) {
      await Future<void>.delayed(Duration.zero);
      clock.reset();
    }
  }

  Future<void> write(Object? v, int depth) async {
    if (v is Map && (depth < 2 || v.length > 64)) {
      buffer.write('{');
      var first = true;
      for (final key in v.keys.toList()) {
        if (!v.containsKey(key)) continue;
        if (!first) buffer.write(',');
        first = false;
        buffer
          ..write(jsonEncode('$key'))
          ..write(':');
        await write(v[key], depth + 1);
      }
      buffer.write('}');
    } else if (v is List && (depth < 2 || v.length > 64)) {
      buffer.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) buffer.write(',');
        await write(v[i], depth + 1);
      }
      buffer.write(']');
    } else {
      await put(jsonEncode(v));
    }
  }

  await write(value, 0);
  sink.add(utf8.encode(buffer.toString()));
}

/// [flush] saves what is waiting to be saved; [saveEverything] calls it.
void saveBeforeClosing(Future<void> Function() flush) => _flushes.add(flush);

/// Everything waiting to be saved, saved now: the app is closing, or going
/// to the background where the phone may end it.
Future<void> saveEverything() async {
  await Future.wait([for (final flush in _flushes) flush().catchError((Object _) {})]);
  await Future.wait(_writing.values.toList());
}

/// A copy of [file], which wouldn't read, beside it (the first one kept, so a
/// second failure doesn't write over it), before the app starts it afresh.
Future<void> setAside(File file) async {
  try {
    if (!await file.exists()) return;
    var copy = File('${file.path}.damaged');
    if (await copy.exists()) copy = File('${file.path}.damaged-${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    await file.copy(copy.path);
  } catch (_) {
    // Nowhere to put it: started afresh all the same.
  }
}
