// Scrobbling to ListenBrainz and reading other devices' plays back, the same
// as the desktop Paattu's (tests/listenbrainz_cases.json).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/history.dart';
import 'package:paattu/src/listenbrainz.dart';
import 'package:paattu/src/util.dart';

void main() {
  final cases = asJson(jsonDecode(File('../tests/listenbrainz_cases.json').readAsStringSync()));
  final device = asString(cases['device']);
  Json history() => asJson(jsonDecode(jsonEncode(cases['history'])));
  List<List<Object?>> pairs(Iterable<(Json, Json)> found) => [
    for (final (play, _) in found) [play['id'], play['at']],
  ];

  test('the listen sent for a play', () {
    for (final c in asList(cases['listens']).map(asJson)) {
      final want = jsonDecode(jsonEncode(c['listen']).replaceAll('"VERSION"', '"9.9.9"'));
      expect(listenOf(asJson(c['play']), asJson(c['song']), device, version: '9.9.9'), want);
    }
  });

  test('only plays heard properly, not sent yet, from this device', () {
    expect(pairs(pendingListens(history())), cases['pending']);
  });

  test("other devices' plays come in once, in time order", () {
    final data = history();
    final found = [for (final f in asList(cases['fetched']).map(asJson)) ?playOfListen(f, device)];
    expect(pairs(mergeListens(data, found)), cases['added']);
    expect([
      for (final p in asList(data['plays']).map(asJson)) [p['id'], p['at']],
    ], cases['merged']);
    expect(asJson(data['tracks'])['d'], {'id': 'd', 'title': 'D', 'language': 'Tamil'});
    expect(asList(data['plays']).map(asJson).firstWhere((p) => p['id'] == 'd'), {
      'id': 'd',
      'at': 4500,
      'heard': 200,
      'length': 260,
      'from': 'listenbrainz',
    });
    expect(mergeListens(data, found), isEmpty);
  });

  test('a device id is made once', () {
    final data = <String, dynamic>{};
    final id = asString(listenState(data)['device']);
    expect(id.length, 12);
    expect(listenState(data), {'device': id, 'sent': 0, 'fetched': 0});
  });

  test('forgetting the history keeps where the sync got to', () {
    final dir = Directory.systemTemp.createTempSync('paattu-lb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final h = History(File('${dir.path}/history.json'))..data = history();
    h.clear();
    expect(h.plays, isEmpty);
    expect(asJson(h.data['listenbrainz'])['sent'], 500);
  });
}
