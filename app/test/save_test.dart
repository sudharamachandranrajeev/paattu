import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/save.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('paattu_save_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, Object?> big() => {
        'version': 2,
        'songs': {
          for (var i = 0; i < 3000; i++)
            'id$i': {
              'title': 'പാട്ട് $i 🎵 "quoted" \\ back',
              'tags': ['தமிழ்', 'x' * (i % 50), null, true, 1.5],
              'plays': i,
            },
        },
        'queue': [for (var i = 0; i < 500; i++) 'id$i'],
        'small': {'a': 1},
        'empty': <String, Object?>{},
      };

  test('writes the same JSON as jsonEncode', () async {
    final data = big();
    final file = File('${dir.path}/library.json');
    await writeJsonGently(file, data);
    expect(file.readAsStringSync(), jsonEncode(data));
    expect(dir.listSync().map((e) => e.path.split('/').last), ['library.json']);
  });

  test('a change while it writes neither throws nor leaves bad JSON', () async {
    final data = big();
    final songs = data['songs']! as Map<String, Object?>;
    final queue = data['queue']! as List<Object?>;
    final file = File('${dir.path}/library.json');
    final saving = writeJsonGently(file, data);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      songs.remove('id${2999 - i}');
      songs['new$i'] = {'title': 'n'};
      queue.removeLast();
    }
    await saving;
    final back = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect((back['songs']! as Map).containsKey('id0'), isTrue);
  });

  test('saves of one file run in order, the last one last', () async {
    final file = File('${dir.path}/library.json');
    await Future.wait([
      writeJsonGently(file, big()),
      writeWhole(file, '{"last":1}'),
    ]);
    expect(file.readAsStringSync(), '{"last":1}');
  });
}
