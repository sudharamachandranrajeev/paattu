// The library model: your playlists, favourites and mixes, in the desktop
// Paattu's library.json format.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/library.dart';

void main() {
  late Directory dir;
  late Library library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('paattu-test');
    library = Library(File('${dir.path}/library.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  final song = <String, dynamic>{'id': 'hvqnG6VjqV0', 'title': 'Malare', 'movie': 'Premam', '_media': 'x'};

  test('a new library has the Malayalam and Tamil mixes', () {
    expect(library.mixList().map((m) => m['title']), ['Malayalam mix', 'Tamil mix']);
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
    final malayalam = library.getMix('malayalam');
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
}
