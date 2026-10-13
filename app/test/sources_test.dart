// Links, track ids and JioSaavn results, as tests/test_sources.py and
// tests/model.test.mjs check them for the desktop Paattu.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/links.dart';
import 'package:paattu/src/sources/http.dart';
import 'package:paattu/src/sources/jiosaavn.dart';
import 'package:paattu/src/sources/sources.dart';

const saavnMalare = {
  'id': 'JWg0ED0Q', 'title': 'Malare', 'subtitle': 'Vijay Yesudas - Premam', 'type': 'song', //
  'perma_url': 'https://www.jiosaavn.com/song/malare/Oj8MATF0B2I',
  'image': 'https://c.saavncdn.com/665/Premam-Malayalam-2015-150x150.jpg',
  'language': 'malayalam', 'year': '2015', 'play_count': '9568589',
  'more_info': {
    'music': 'Rajesh Murugesan', 'album': 'Premam', 'label': 'Muzik 247', '320kbps': 'true', 'duration': '316',
    'encrypted_media_url': 'abc',
    'artistMap': {
      'primary_artists': [
        {'name': 'Vijay Yesudas', 'role': 'primary_artists'},
      ],
      'featured_artists': <Object>[],
      'artists': [
        {'name': 'Rajesh Murugesan', 'role': 'music'},
        {'name': 'Vijay Yesudas', 'role': 'singer'},
        {'name': 'Shabareesh Varma', 'role': 'lyricist'},
      ],
    },
  },
};

const saavnFrom = {
  'id': 'x1', 'title': 'Malare (From &quot;Premam&quot;)', 'type': 'song', //
  'perma_url': 'https://www.jiosaavn.com/song/malare-from-premam/AQ0dbjB1ZQI',
  'image': 'https://c.saavncdn.com/123/Hits-150x150.jpg', 'language': 'malayalam', 'year': '2020',
  'more_info': {
    'music': 'Rajesh Murugesan', 'album': 'Malayalam Love Hits', 'label': 'Muzik 247', '320kbps': 'false',
    'duration': '300',
    'artistMap': {
      'primary_artists': [
        {'name': 'Vijay Yesudas'},
      ],
      'featured_artists': <Object>[],
      'artists': <Object>[],
    },
  },
};

void main() {
  group('track ids', () {
    // Shared with the desktop Paattu's tests: every id must come out the same.
    final cases = (jsonDecode(File('../tests/track_ids.json').readAsStringSync()) as Map).cast<String, Object?>();
    for (final entry in cases.entries) {
      test(entry.key, () => expect(linkTrackId(entry.key), entry.value));
    }
  });

  test('siteOf', () {
    expect(siteOf('https://www.jiosaavn.com/song/x/y'), 'jiosaavn');
    expect(siteOf('https://soundcloud.com/a/b'), 'soundcloud');
    expect(siteOf('https://youtu.be/hvqnG6VjqV0'), 'youtube');
    expect(siteOf('https://example.bandcamp.com/track/x'), 'example.bandcamp.com');
  });

  test('YouTube links', () {
    expect(videoId('https://www.youtube.com/watch?v=hvqnG6VjqV0&list=PLx'), 'hvqnG6VjqV0');
    expect(videoId('https://youtube.com/shorts/hvqnG6VjqV0'), 'hvqnG6VjqV0');
    expect(playlistId('https://www.youtube.com/playlist?list=PLGSaQXigBvdM'), 'PLGSaQXigBvdM');
    expect(playlistId('VLPLGSaQXigBvdM'), 'PLGSaQXigBvdM');
    expect(channelRef('https://www.youtube.com/@saregamamalayalam/playlists'), ('handle', '@saregamamalayalam'));
    expect(channelRef('UCoRF8GByEjmM_yHwUGIDGyQ'), ('id', 'UCoRF8GByEjmM_yHwUGIDGyQ'));
    expect(channelRef('saregamamalayalam'), ('handle', '@saregamamalayalam'));
    expect(channelRef('two words'), isNull);
    expect(looksLikeSingleVideo('https://youtu.be/hvqnG6VjqV0'), isTrue);
  });

  test('quality labels', () {
    expect(qualityLabel({'quality': 320, 'codec': 'aac'}), '320 kbps');
    expect(qualityLabel({'quality': 900, 'codec': 'flac'}), 'Lossless');
    expect(qualityLabel({'id': 'hvqnG6VjqV0'}), '');
    expect(ResolvedStream(Uri.parse('https://x'), codec: 'opus', kbps: 160).label, 'Opus · 160 kbps');
    expect(ResolvedStream(Uri.parse('https://x'), codec: 'flac', kbps: 900).label, 'FLAC');
  });

  group('JioSaavn', () {
    test('a song', () {
      final t = jiosaavnTrack(saavnMalare)!;
      expect(t['id'], 'jiosaavn.com_song_malare_Oj8MATF0B2I');
      expect((t['title'], t['movie'], t['site']), ('Malare', 'Premam', 'jiosaavn'));
      expect(t['credits'], ['Rajesh Murugesan', 'Vijay Yesudas']);
      expect((t['quality'], t['codec'], t['duration'], t['year']), (320, 'aac', 316, '2015'));
      expect(t['language'], 'Malayalam');
      expect(t['art'], 'https://c.saavncdn.com/665/Premam-Malayalam-2015-500x500.jpg');
    });

    test('a film song on a hits album', () {
      final t = jiosaavnTrack(saavnFrom)!;
      expect((t['title'], t['movie'], t['album']), ('Malare', 'Premam', 'Malayalam Love Hits'));
      expect(t['rawTitle'], 'Malare (From "Premam")');
      expect(t['quality'], 128);
      expect(t['credits'], ['Vijay Yesudas']);
    });

    test('albums and playlists are skipped', () {
      expect(jiosaavnTrack({...saavnMalare, 'type': 'album'}), isNull);
    });

    test('filmAndTitle', () {
      expect(filmAndTitle('Kaathalae', '96 (Original Motion Picture Soundtrack)'), ('Kaathalae', '96'));
      expect(filmAndTitle('Chuttamalle', 'Devara Part 1 - Telugu (Original Motion Picture Soundtrack)'),
          ('Chuttamalle', 'Devara Part 1'));
      expect(filmAndTitle('Premam', 'Premam'), ('Premam', ''));
    });
  });

  test('a direct audio file plays as it is', () {
    final t = audioFileTrack('https://archive.org/download/x/Malare_Song.flac');
    expect(t['title'], 'Malare Song');
    expect(t['codec'], 'flac');
    expect(t['site'], 'archive.org');
  });
}
