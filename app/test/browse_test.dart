// Search results beyond songs (albums, artists, playlists), merging pages
// from several sites, and picking YouTube's audio stream.

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/sources/jiosaavn.dart';
import 'package:paattu/src/sources/soundcloud.dart';
import 'package:paattu/src/sources/sources.dart';
import 'package:paattu/src/sources/youtube.dart';
import 'package:paattu/src/util.dart';

Json _format(int itag, String mime, int bitrate, {int? average, bool drc = false, bool? original}) => {
      'itag': itag,
      'url': 'https://rr1---sn-x.googlevideo.com/videoplayback?itag=$itag',
      'mimeType': mime,
      'bitrate': bitrate,
      'averageBitrate': ?average,
      if (drc) 'isDrc': true,
      if (original != null) 'audioTrack': {'displayName': original ? 'English original' : 'Hindi', 'audioIsDefault': original},
    };

Json _player(List<Json> formats, {String status = 'OK', String reason = ''}) => {
      'playabilityStatus': {'status': status, 'reason': reason},
      'streamingData': {'expiresInSeconds': '21540', 'adaptiveFormats': formats},
    };

void main() {
  group('YouTube audio', () {
    test('the best plain audio: not video, not levelled, not dubbed', () {
      final stream = bestAudio(
        _player([
          _format(137, 'video/mp4; codecs="avc1.640028"', 4000000),
          _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000),
          _format(251, 'audio/webm; codecs="opus"', 140000, average: 135000),
          _format(251, 'audio/webm; codecs="opus"', 150000, drc: true),
        ]),
        android: false,
      );
      expect(stream.uri.queryParameters['itag'], '251');
      expect((stream.codec, stream.kbps), ('opus', 135));
      expect(stream.headers, {'User-Agent': isNotEmpty});
      final hours = stream.expires.difference(DateTime.now()).inMinutes / 60;
      expect(hours, closeTo(5.48, 0.05)); // 21540 s less half an hour
    });

    test('the original language over a louder dubbed copy', () {
      final stream = bestAudio(
        _player([
          _format(251, 'audio/webm; codecs="opus"', 160000, original: false),
          _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000, original: true),
        ]),
        android: false,
      );
      expect((stream.uri.queryParameters['itag'], stream.codec), ('140', 'aac'));
    });

    test("Android's player is asked to send a range, so it isn't throttled", () {
      final stream = bestAudio(_player([_format(140, 'audio/mp4', 130000)]), android: true);
      expect(stream.headers?['Range'], 'bytes=0-');
      expect(streamHeaders('x', android: false), {'User-Agent': 'x'});
    });

    test("YouTube's reason when it won't play", () {
      expect(
        () => bestAudio(_player([], status: 'LOGIN_REQUIRED', reason: 'Sign in to confirm  you’re not a bot')),
        throwsA(isA<SourceException>().having((e) => e.message, 'message', 'Sign in to confirm you’re not a bot')),
      );
      expect(() => bestAudio(_player([_format(137, 'video/mp4', 1)])), throwsA(isA<SourceException>()));
    });
  });

  group('merging pages', () {
    final saavn = {'id': 'jiosaavn.com_song_malare_x', 'site': 'jiosaavn', 'title': 'Malare', 'movie': 'Premam'};
    final tube = {'id': 'AAAAAAAAAAA', 'site': 'youtube', 'title': 'Malare', 'movie': 'Premam'};
    final other = {'id': 'BBBBBBBBBBB', 'site': 'youtube', 'title': 'Malare cover', 'movie': ''};
    final cloud = {'id': 'soundcloud.com_a_b', 'site': 'soundcloud', 'title': 'Malare lofi', 'movie': ''};

    test('a film song is one song on every site', () {
      expect(resultKey(saavn), resultKey(tube));
      expect(resultKey(other), isNot(resultKey(cloud)));
      expect(resultKey({'type': 'album', 'site': 'jiosaavn', 'id': '1'}), isNot(resultKey({'type': 'album', 'site': 'soundcloud', 'id': '1'})));
    });

    test('sites take turns, and nothing comes twice', () {
      final seen = <String>{};
      final first = interleave([
        [saavn],
        [tube, other],
        [cloud],
      ], seen);
      expect(first.map((t) => t['id']), [saavn['id'], cloud['id'], other['id']]);
      expect(interleave([[other, cloud]], seen), isEmpty);
    });
  });

  group('JioSaavn collections', () {
    test('an album', () {
      final album = jiosaavnCollection({
        'id': '1234', 'title': 'Premam', 'subtitle': 'Rajesh Murugesan', 'type': 'album', 'year': '2015', //
        'language': 'malayalam', 'perma_url': 'https://www.jiosaavn.com/album/premam/abc',
        'image': 'https://c.saavncdn.com/665/Premam-Malayalam-2015-150x150.jpg',
        'more_info': {'song_count': '9'},
      })!;
      expect((album['type'], album['site'], album['count'], album['language']), ('album', 'jiosaavn', 9, 'Malayalam'));
      expect(album['subtitle'], 'Rajesh Murugesan · 2015');
      expect(album['art'], 'https://c.saavncdn.com/665/Premam-Malayalam-2015-500x500.jpg');
    });

    test('an artist', () {
      final artist = jiosaavnCollection({
        'id': '455', 'name': 'K. S. Chithra', 'type': 'artist', 'role': 'Artist',
        'perma_url': 'https://www.jiosaavn.com/artist/k.-s.-chithra-songs/abc_',
        'image': 'https://c.saavncdn.com/artists/Chithra_50x50.jpg',
      })!;
      expect((artist['type'], artist['title'], artist['subtitle']), ('artist', 'K. S. Chithra', 'Singer'));
      expect(artist['art'], 'https://c.saavncdn.com/artists/Chithra_500x500.jpg');
    });

    test('nameless or unknown things are skipped', () {
      expect(jiosaavnCollection({'id': '1', 'type': 'album'}), isNull);
      expect(jiosaavnCollection({'id': '1', 'title': 'x', 'type': 'show'}), isNull);
    });
  });

  group('SoundCloud collections', () {
    test('a user is an artist; a set is an album or a playlist', () {
      final user = soundcloudCollection({
        'kind': 'user', 'id': 7, 'username': 'Masala Coffee', 'followers_count': 1200,
        'permalink_url': 'https://soundcloud.com/masalacoffee',
        'avatar_url': 'https://i1.sndcdn.com/avatars-x-large.jpg',
      })!;
      expect((user['type'], user['subtitle'], user['art']),
          ('artist', '1.2K followers', 'https://i1.sndcdn.com/avatars-x-t500x500.jpg'));
      final set = {
        'kind': 'playlist', 'id': 9, 'title': 'Live', 'track_count': 6, 'user': {'username': 'Masala Coffee'},
        'permalink_url': 'https://soundcloud.com/masalacoffee/sets/live',
      };
      expect(soundcloudCollection({...set, 'is_album': true})!['type'], 'album');
      expect(soundcloudCollection(set)!['type'], 'playlist');
      expect(soundcloudCollection(set)!['count'], 6);
      expect(soundcloudCollection({'kind': 'user'}), isNull);
    });
  });
}
