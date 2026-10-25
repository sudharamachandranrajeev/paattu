// The library model: your playlists, favourites and mixes, in the desktop
// Paattu's library.json format; songs played join their language's mix as
// on the desktop (tests/played_cases.json).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/library.dart';
import 'package:paattu/src/util.dart';

void main() {
  late Directory dir;
  late Library library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('paattu-test');
    library = Library(File('${dir.path}/library.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  final song = <String, dynamic>{'id': 'hvqnG6VjqV0', 'title': 'Malare', 'movie': 'Premam', '_media': 'x'};

  test('a new library has no mixes', () {
    expect(library.mixList(), isEmpty);
  });

  test('the mixes libraries used to start with go unless changed', () {
    Json first(String lang, [List<Json> extra = const []]) => {
          'id': 'mix-${lang.toLowerCase()}',
          'title': '$lang mix',
          'sources': [
            {'type': 'language', 'id': lang},
            ...extra,
          ],
        };
    final data = normaliseLibrary(<String, dynamic>{
      'mixes': [
        first('Malayalam', [
          {'type': 'playlist', 'id': 'paattu-played-malayalam'},
        ]),
        first('Tamil', [
          {'type': 'language', 'id': 'Kannada'},
        ]),
        {
          'id': 'mix-ab12',
          'title': 'Mine',
          'sources': [
            {'type': 'language', 'id': 'Malayalam'},
          ],
        },
      ],
    });
    expect(asList(data['mixes']).map((m) => asJson(m)['title']), ['Tamil mix', 'Mine']);
    expect(data['mixesVersion'], mixesVersion);
    // Made again by hand afterwards: it stays.
    (data['mixes'] as List).insert(0, first('Malayalam'));
    expect(asList(normaliseLibrary(data)['mixes']).length, 3);
    // Libraries from before mixes don't get any.
    expect(normaliseLibrary(<String, dynamic>{})['mixes'], isEmpty);
  });

  test('favourites and saved songs', () {
    expect(library.toggleFavourite(song), isTrue);
    expect(library.isFavourite('hvqnG6VjqV0'), isTrue);
    expect(library.track('hvqnG6VjqV0')!.containsKey('_media'), isFalse);
    expect(library.toggleFavourite(song), isFalse);
    expect(library.isFavourite('hvqnG6VjqV0'), isFalse);
    expect(library.saveSong(song), isTrue);
    expect(library.saveSong(song), isFalse);
  });

  test('own playlists', () {
    final p = library.createPlaylist('Drive');
    library.addTracks(p['id'] as String, [song]);
    expect(library.playlistTracks(p['id'] as String).single['title'], 'Malare');
    expect(() => library.createPlaylist('drive'), throwsA(isA<LibraryException>()));
    library.renamePlaylist(p['id'] as String, 'Long drive');
    expect(library.findOwnPlaylist('long drive')?['id'], p['id']);
    library.removePlaylist(p['id'] as String);
    expect(library.track('hvqnG6VjqV0'), isNull);
  });

  test('mixes', () {
    library.setPlaylistTracks({
      'id': 'PLGSaQXigBvdM',
      'title': 'Hits of Sushin Shyam | Saregama Malayalam',
      'channel': 'Saregama Malayalam',
      'tracks': [
        {'id': 'hvqnG6VjqV0', 'title': 'Thalatherichavar - Video | Romancham | Sushin Shyam'},
      ],
    });
    library.setSaved('PLGSaQXigBvdM', true);
    library.setPlaylistLanguage('PLGSaQXigBvdM', 'Malayalam');
    final malayalam = library.createMix('Malayalam mix', [
      {'type': 'language', 'id': 'Malayalam'},
    ]);
    expect(library.mixCounts(malayalam), (playlists: 1, songs: 1, waiting: 0));
    final mix = library.createMix('Sushin', [
      {'type': 'playlist', 'id': 'PLGSaQXigBvdM'},
    ]);
    expect(library.mixPlaylists(mix).single['title'], 'Hits of Sushin Shyam');
    library.removePlaylist('PLGSaQXigBvdM');
    library.pruneMixes();
    expect(library.getMix('Sushin')['sources'], isEmpty);
  });

  test('saves and loads', () async {
    library.toggleFavourite(song);
    await library.save();
    final again = Library(library.file);
    await again.load();
    expect(again.isFavourite('hvqnG6VjqV0'), isTrue);
  });

  group('played', () {
    final cases = asJson(jsonDecode(File('../tests/played_cases.json').readAsStringSync()));
    void fresh() => library.replaceWith(jsonDecode(jsonEncode(cases['library'])));

    test('the language of a song', () {
      fresh();
      for (final c in asList(cases['language']).map(asJson)) {
        expect(library.playedLanguage(asJson(c['track'])), c['language'], reason: '$c');
      }
    });

    test('songs played join their language\'s mix', () {
      fresh();
      for (final c in asList(cases['plays']).map(asJson)) {
        expect(library.notePlayed(asJson(c['track'])), c['language'], reason: '$c');
        for (final language in ['malayalam', 'tamil']) {
          expect(library.playlist('$playedPrefix$language')?['tracks'], c[language], reason: '$c');
        }
      }
      final sources = {for (final m in library.mixList()) m['id']: m['sources']};
      expect(sources['mix-malayalam'], anyElement(equals({'type': 'playlist', 'id': 'paattu-played-malayalam'})));
      expect(sources['mix-tamil'], anyElement(equals({'type': 'playlist', 'id': 'paattu-played-tamil'})));
      expect(library.playlist('paattu-played-tamil')!['title'], 'Played in Tamil');
      expect(library.track('s2'), isNotNull);
    });

    test('a deleted played playlist stays deleted', () {
      fresh();
      library.notePlayed({'id': 's1', 'title': 'Pularikalo', 'language': 'Malayalam'});
      library.removePlaylist('paattu-played-malayalam');
      expect(library.data['playedOff'], ['Malayalam']);
      expect(library.notePlayed({'id': 's3', 'title': 'x', 'language': 'Malayalam'}), '');
      expect(library.playlist('paattu-played-malayalam'), isNull);
    });
  });
}
