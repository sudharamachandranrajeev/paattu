// Saving the app's own files (the library, the history, the settings, the
// kept songs' index): whole or not at all, one write at a time for each, all
// of them before the app goes, and a damaged one set aside, never written
// over.

import 'dart:async';
import 'dart:io';

final _writing = <String, Future<void>>{};
final _flushes = <Future<void> Function()>[];

/// Put [text] in [file] whole: written to a file of its own beside it, then
/// moved over it, so neither a crash nor a save at the same moment (the
/// timer's and the one on closing, or a second window's) leaves half of it.
/// Saves of one file run one after another, the last one's text last.
Future<void> writeWhole(File file, String text) {
  final path = file.path;
  final done = (_writing[path] ?? Future<void>.value()).then((_) async {
    await file.parent.create(recursive: true);
    final tmp = File('$path.$pid.tmp');
    await tmp.writeAsString(text, flush: true);
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
