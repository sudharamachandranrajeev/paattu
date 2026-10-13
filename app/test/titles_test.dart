// The same cases as tests/test_titles.py: the app and the desktop Paattu
// must read titles alike.

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/titles.dart';

Map<String, dynamic> asMap(CleanTitle t) =>
    {'title': t.title, 'movie': t.movie, 'credits': t.credits, 'kind': t.kind};

void main() {
  // Real uploads from Saregama, Think Music, Divo, Manorama, Sony and others.
  const cases = [
    ('Thalatherichavar - Video | Romancham | Sushin Shyam | Johnpaul George Productions | Jithu Madhavan | Saregama Malayalam',
        'Saregama Malayalam', 'Thalatherichavar', 'Romancham', 'video'),
    ('Pakaliravukal - Video Song | Kurup | Dulquer Salmaan | Sobhita Dhulipala | Sushin Shyam | Anwar Ali | Saregama Malayalam',
        'Saregama Malayalam', 'Pakaliravukal', 'Kurup', 'video'),
    ('Athmave Poo - Lyrical | Romancham | Sushin Shyam | Johnpaul George Productions | Jithu Madhavan | Saregama Malayalam',
        '', 'Athmave Poo', 'Romancham', 'lyrical'),
    ('Kumki - Onnum Puriyala 8K 60 FPS Video Song | Vikram Prabhu, Lakshmi Menon | D. Imman', '', 'Onnum Puriyala', 'Kumki', 'video'),
    ('Dorothy - Kanagamani Lyric Video | Karthik Subbaraj | Keerthy Suresh | Ilaiyaraaja', '', 'Kanagamani', 'Dorothy', 'lyrical'),
    ('Wi Wi Wi Wi Wifi Video Song (4K) | S3 | Suriya | Anushka Shetty | Shruti Haasan | Harris Jayaraj',
        '', 'Wi Wi Wi Wi Wifi', 'S3', 'video'),
    ('Naetru Aval Irundhal 8K 60FPS Video Song | Maryan | Dhanush, Parvathy | A.R. Rahman | Chinmayi',
        '', 'Naetru Aval Irundhal', 'Maryan', 'video'),
    ('Mayilaadum Song | Paandi Nattu Thangam | Ilaiyaraaja | Karthik | Nirosha | Hi-Res Audio',
        '', 'Mayilaadum', 'Paandi Nattu Thangam', 'audio'),
    ('Bhajare | Mr Brahmachari | Video | Mohanlal | K S Chithra | Gireesh Puthenchery | Mohan Sithara',
        '', 'Bhajare', 'Mr Brahmachari', 'video'),
    ('Theliva Lyrical | #Love | Arjun Das, Aishwarya Lekshmi | Sean Roldan | Balaji Mohan | Netflix India',
        '', 'Theliva', 'Love', 'lyrical'),
    ('Baasha Da - Video | Anbil Avan | Ashok Selvan | Preity Mukhundhan | Govind Vasantha | R.Kaarthikeyan',
        '', 'Baasha Da', 'Anbil Avan', 'video'),
    ('Yeman Yaaru - Video Song | Indra | Vasanth Ravi | Mehreen Pirzada | ADK | Ajmal Tahseen', '', 'Yeman Yaaru', 'Indra', 'video'),
    ('Exclusive – Unnande Kadhalena 8K Video Song | Vandha Mala | Sam D. Raj | Igore, Lakshmi',
        '', 'Unnande Kadhalena', 'Vandha Mala', 'video'),
    ('Kanmani Anbodu Kadhalan (Lyric Video) | Guna | Kamal Haasan | Ilaiyaraaja', '', 'Kanmani Anbodu Kadhalan', 'Guna', 'lyrical'),
    ('96 Songs| Kaathalae Kaathalae Song | Vijay Sethupathi, Trisha | Govind Vasantha | C. Prem Kumar',
        'Think Music India', 'Kaathalae Kaathalae', '96', 'video'),
    ('96 | Kaathalae Kaathalae Video Song | Vijay Sethupathi, Trisha | Govind Vasantha | C. Prem Kumar',
        'Think Music India', 'Kaathalae Kaathalae', '96', 'video'),
    ('Malare | Premam Song | Nivin Pauly', '', 'Malare', 'Premam', 'video'),
    ('Malare - Premam Song | Nivin Pauly | Sai Pallavi', '', 'Malare', 'Premam', 'video'),
    ('Hukum - Thalaivar Alappara (From "Jailer") | Anirudh Ravichander | Rajinikanth', '', 'Hukum', 'Jailer', 'video'),
    ('Ullam Uruguthadi - Audio Jukebox | Ilaiyaraaja | Suresh, Viji | Erode N Murugesh', '', 'Ullam Uruguthadi', 'Ilaiyaraaja', 'jukebox'),
    ('Vaathi Coming Video Song | Master | Thalapathy Vijay | Anirudh Ravichander | Lokesh Kanagaraj', '', 'Vaathi Coming', 'Master', 'video'),
    ('The Third Murder | Official Movie Trailer | Saiju Kurup | Indrans', '', 'The Third Murder', 'Official Movie Trailer', 'trailer'),
  ];

  group('cleanTitle', () {
    for (final (raw, channel, title, movie, kind) in cases) {
      test(raw, () {
        final got = cleanTitle(raw, channel);
        expect((got.title, got.movie, got.kind), (title, movie, kind));
      });
    }

    test("artist first on the artist's channel", () {
      expect(cleanTitle('Sushin Shyam - Ray (Official Video)', 'Sushin Shyam').title, 'Ray');
    });

    test('label and channel are not credits', () {
      final got = cleanTitle(cases.first.$1, 'Saregama Malayalam');
      expect(got.credits, isNot(contains('Saregama Malayalam')));
      expect(got.credits.first, 'Sushin Shyam');
    });

    test('a plain title passes through', () {
      expect(asMap(cleanTitle('Nenjukkul Peidhidum')),
          {'title': 'Nenjukkul Peidhidum', 'movie': '', 'credits': <String>[], 'kind': 'video'});
    });

    test('songKey matches the video and the lyrical upload', () {
      final video = asMap(cleanTitle('Athmave Poo - Video Song | Romancham | Sushin Shyam'));
      final lyrical = asMap(cleanTitle('Athmave Poo - Lyrical | Romancham | Sushin Shyam'));
      expect(songKey(video), songKey(lyrical));
      expect(songKey(video), isNot(songKey(asMap(cleanTitle('Aadharanjali - Promo Song | Romancham')))));
    });
  });

  group('playlistTitle', () {
    test('drops the label', () {
      expect(playlistTitle('Hits of Sushin Shyam | Saregama Malayalam'), 'Hits of Sushin Shyam');
      expect(playlistTitle('Jukebox Mania | Non-Stop Malayalam Hits | Saregama Malayalam'), 'Jukebox Mania');
    });

    test('drops "Official Playlist"', () {
      expect(playlistTitle('Karam - Official Playlist | Vineeth Sreenivasan | Shaan Rahman'), 'Karam');
    });
  });

  test('guessLanguage reads words and scripts', () {
    expect(guessLanguage(['Non-Stop Malayalam Hits']), 'Malayalam');
    expect(guessLanguage(['Evergreen Tamil Melodies']), 'Tamil');
    expect(guessLanguage(['തിരുവാതിരകളി വീഡിയോ']), 'Malayalam');
    expect(guessLanguage(['பாட்டு']), 'Tamil');
    expect(guessLanguage(['Hits of Sushin Shyam'], fallback: 'Malayalam'), 'Malayalam');
    expect(guessLanguage(['Lo-fi beats']), '');
  });
}
