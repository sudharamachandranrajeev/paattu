// Renders the main pages with the real fonts to PNG files, for checking the
// look and for the README. Runs only when PAATTU_SHOTS names an output folder:
//
//     cd app && PAATTU_SHOTS=/tmp/shots flutter test test/screenshots_test.dart
//
// The library is made up (songs, films, singers and labels that don't exist),
// and the covers are pictures drawn here: nothing goes to the network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/app_state.dart';
import 'package:paattu/src/charts.dart';
import 'package:paattu/src/history.dart';
import 'package:paattu/src/library.dart';
import 'package:paattu/src/listenbrainz.dart';
import 'package:paattu/src/lyrics.dart';
import 'package:paattu/src/made.dart';
import 'package:paattu/src/offline.dart';
import 'package:paattu/src/player/paattu_audio_handler.dart';
import 'package:paattu/src/settings.dart';
import 'package:paattu/src/ui/now_playing.dart';
import 'package:paattu/src/ui/shell.dart';
import 'package:paattu/src/ui/sound_page.dart';
import 'package:paattu/src/ui/stats_page.dart';
import 'package:paattu/src/update.dart';
import 'package:paattu/src/util.dart';

/// Where the drawn covers are served from (only inside this test).
const _coverHost = 'covers.paattu.test';

void main() {
  final out = Platform.environment['PAATTU_SHOTS'];

  testWidgets('screenshots', skip: out == null, (tester) async {
    await tester.runAsync(_loadFonts);
    final covers = (await tester.runAsync(_drawCovers))!;
    final httpBefore = HttpOverrides.current;
    HttpOverrides.global = _CoverOverrides(covers);
    debugDisableShadows = false;
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('paattu-shots')))!;
    final key = GlobalKey();
    var n = 0;

    Future<void> settle() async {
      // Pictures decode outside the fake clock; give them a few real moments.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/${(++n).toString().padLeft(2, '0')}-$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.first, warnIfMissed: false);
      await settle();
    }

    for (final (theme, mode) in [('chembarathi', 'dark'), ('kasavu', 'light')]) {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      final app = (await tester.runAsync(() => _openApp(dir, theme)))!;
      await tester.pumpWidget(RepaintBoundary(key: key, child: PaattuApp(state: app)));
      await shot('home-$mode');
      app.navigator.currentState!.push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const NowPlayingPage()));
      await shot('now-playing-$mode');
      app.navigator.currentState!.pop();
      await settle();
      if (mode == 'dark') {
        // Video mode: the song has no video here, so its card shows the cover.
        app.settings.videoMode = true;
        app.navigator.currentState!.push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const NowPlayingPage()));
        await shot('now-playing-video-$mode');
        app.navigator.currentState!.pop();
        await settle();
        // The phone on its side: the picture beside the controls, no scrolling.
        tester.view.physicalSize = const Size(2532, 1170);
        app.navigator.currentState!.push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const NowPlayingPage()));
        await shot('now-playing-landscape-video-$mode');
        app.settings.videoMode = false;
        await shot('now-playing-landscape-$mode');
        app.navigator.currentState!.pop();
        tester.view.physicalSize = const Size(1170, 2532);
        await settle();
        await tap(find.byTooltip('Library'));
        await shot('library-$mode');
        await tap(find.text('Night drive'));
        await shot('playlist-$mode');
        app.navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SoundPage()));
        await shot('sound-$mode');
        app.navigator.currentState!.pop();
        await settle();
        app.navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const StatsPage()));
        await shot('stats-$mode');
        app.navigator.currentState!.pop();
        await settle();
        await tap(find.byTooltip('Settings'));
        await shot('settings-$mode');
      }
      await _close(tester, app);
    }

    // A desktop window (Windows, the Linux app).
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    final app = (await tester.runAsync(() => _openApp(dir, 'chembarathi')))!;
    await tester.pumpWidget(RepaintBoundary(key: key, child: PaattuApp(state: app)));
    await shot('home-desktop');
    app.navigator.currentState!.push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const NowPlayingPage()));
    await shot('now-playing-desktop');
    await _close(tester, app);

    tester.view.reset();
    debugDisableShadows = true;
    HttpOverrides.global = httpBefore;
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}

Future<void> _close(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  // Let the settings and library files finish writing.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Poppins', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Poppins-$w.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

// ------------------------------------------------------------------ the app

/// A player that is part way through a song, without playing anything.
class _ShotPlayer extends PaattuAudioHandler {
  @override
  Stream<Duration> get positionStream => Stream.value(const Duration(minutes: 1, seconds: 47));
  @override
  Stream<Duration> get bufferedStream => Stream.value(const Duration(minutes: 3, seconds: 10));
  @override
  Stream<Duration?> get durationStream => Stream.value(const Duration(minutes: 4, seconds: 21));
  @override
  Stream<bool> get playingStream => Stream.value(true);
  @override
  bool get playing => true;
  @override
  int get index => 0;
}

Future<AppState> _openApp(Directory root, String theme) async {
  final dir = await Directory('${root.path}/$theme').create(recursive: true);
  final library = _library();
  await File('${dir.path}/library.json').writeAsString(jsonEncode(library));
  await File('${dir.path}/history.json').writeAsString(jsonEncode(_history(library)));
  await File('${dir.path}/settings.json').writeAsString(jsonEncode({
    'theme': theme,
    // Neither needs a song's video or a model in a test.
    'videoBackground': false,
    'coverDepth': false,
    'volume': 0.8,
    'sound': {
      'on': true,
      'preset': 'melody',
      'bands': [-2, -1.5, -1, 0.5, 2, 3.5, 3.5, 2, 0.5, -0.5],
      'bass': 2,
      'treble': 1,
    },
  }));
  final lib = Library(File('${dir.path}/library.json'));
  final settings = Settings(File('${dir.path}/settings.json'));
  final history = History(File('${dir.path}/history.json'));
  await Future.wait([lib.load(), settings.load(), history.load()]);
  final offline = OfflineLibrary(Directory('${dir.path}/offline'));
  await offline.load();
  final player = _ShotPlayer();
  final tracks = asJson(library['tracks']);
  final queue = [for (final id in asStrings(asJson(asJson(library['playlists'])['demo-night'])['tracks'])) asJson(tracks[id])];
  player.current.add(queue.first);
  player.queueTracks.add(queue);
  player.quality.add('AAC · 320 kbps');
  final updates = UpdateManager(currentVersion: sourceVersion, dir: Directory('${dir.path}/updates'));
  // Words for every song, the line at 1:47 sung (the player stands there).
  final lyrics = Lyrics(Directory('${dir.path}/lyrics'), find: (track, language, {level}) async => {
        'synced': '[01:40.00]പുഴയോരം തഴുകുന്നീ തണു ഈറൻ കാറ്റും\n[01:45.00]തെളിമാനം മഴവില്ലിൻ നിറമണിയും നേരം\n'
            '[01:52.00]നിറമാർന്നൊരു കനവെന്നിൽ തെളിയുന്ന പോലെ',
        'plain': '',
        'source': 'LRCLIB',
      });
  return AppState(lib, settings, player, history, offline, updates, ListenBrainz(history, lib, settings),
      Charts(history, File('${dir.path}/charts.json')), lyrics);
}

// ------------------------------------------------------------- made-up music

/// (title, film, singer, composer, language)
const _songs = [
  ('Kaayal Kaattil', 'Kaayalkara', 'Anjana Menon', 'Hari Prasad', 'Malayalam'),
  ('Nilaavin Theeram', 'Neelaraavu', 'Rahul Nair', 'Sreeram Varma', 'Malayalam'),
  ('Mazhamegham Pole', 'Kaayalkara', 'Devika Pillai', 'Hari Prasad', 'Malayalam'),
  ('Ponnolam', 'Ponnambalam Days', 'Arjun Menon', 'Nikhil Das', 'Malayalam'),
  ('Thira Paadum', 'Neelaraavu', 'Kavya Raghav', 'Sreeram Varma', 'Malayalam'),
  ('Vaaka Pookkum Neram', 'Mazhavillu Express', 'Anjana Menon', 'Nikhil Das', 'Malayalam'),
  ('Chandana Kaatte', 'Ponnambalam Days', 'Vineeth Kumar', 'Nikhil Das', 'Malayalam'),
  ('Akale Oru Theeram', 'Mazhavillu Express', 'Devika Pillai', 'Hari Prasad', 'Malayalam'),
  ('Ilam Thennal Vazhi', 'Kaayalkara', 'Rahul Nair', 'Hari Prasad', 'Malayalam'),
  ('Minnaminni', 'Neelaraavu', 'Meera Krishnan', 'Sreeram Varma', 'Malayalam'),
  ('Varnachirakukal', 'Mazhavillu Express', 'Arjun Menon', 'Nikhil Das', 'Malayalam'),
  ('Kuyil Paadum Raavil', 'Ponnambalam Days', 'Kavya Raghav', 'Nikhil Das', 'Malayalam'),
  ('Nila Kaigal', 'Thendral Theru', 'Arun Selvam', 'Vikram Sundar', 'Tamil'),
  ('Mazhai Saaral Neram', 'Nilaa Nagaram', 'Priya Ganesh', 'Karthik Raja Mohan', 'Tamil'),
  ('Kaatril Oru Varisai', 'Thendral Theru', 'Meera Krishnan', 'Vikram Sundar', 'Tamil'),
  ('Vaanam Thodum', 'Iravu Express', 'Surya Narayan', 'Karthik Raja Mohan', 'Tamil'),
  ('Pon Maalai', 'Nilaa Nagaram', 'Priya Ganesh', 'Karthik Raja Mohan', 'Tamil'),
  ('Thendral Varum Vazhi', 'Thendral Theru', 'Arun Selvam', 'Vikram Sundar', 'Tamil'),
  ('Kadal Alai Osai', 'Iravu Express', 'Lakshmi Bala', 'Anand Ravi', 'Tamil'),
  ('Oru Naal Kanavil', 'Nilaa Nagaram', 'Surya Narayan', 'Karthik Raja Mohan', 'Tamil'),
  ('Megam Koodum', 'Iravu Express', 'Lakshmi Bala', 'Anand Ravi', 'Tamil'),
  ('Iravin Nizhal Pol', 'Thendral Theru', 'Priya Ganesh', 'Vikram Sundar', 'Tamil'),
  ('Pookkal Pesum Mozhi', 'Iravu Express', 'Arun Selvam', 'Anand Ravi', 'Tamil'),
  ('Vizhiyil Kavithai', 'Nilaa Nagaram', 'Meera Krishnan', 'Karthik Raja Mohan', 'Tamil'),
];

String _id(int i) => 'demo-${(i + 1).toString().padLeft(2, '0')}';
String _art(int i) => 'https://$_coverHost/${i + 1}.png';

Json _library() {
  final tracks = <String, dynamic>{
    for (var i = 0; i < _songs.length; i++)
      _id(i): {
        'id': _id(i),
        'title': _songs[i].$1,
        'movie': _songs[i].$2,
        'credits': [_songs[i].$3, _songs[i].$4],
        'kind': 'song',
        'channel': _songs[i].$5 == 'Malayalam' ? 'Kaayal Records' : 'Thendral Audio',
        'language': _songs[i].$5,
        'duration': 200 + (i * 37) % 140,
        'site': 'jiosaavn',
        'art': _art(i),
      },
  };
  final malayalam = [for (var i = 0; i < 12; i++) i];
  final tamil = [for (var i = 12; i < 24; i++) i];
  Json playlist(String id, String title, List<int> songs, {String owner = '', String language = '', bool local = false}) => {
        'id': id,
        'title': title,
        'rawTitle': title,
        'owner': owner,
        'ownerName': local ? 'You' : (language == 'Malayalam' ? 'Kaayal Records' : 'Thendral Audio'),
        'language': language,
        'saved': true,
        if (local) 'local': true,
        'thumbnail': _art(songs.first),
        'tracks': [for (final i in songs) _id(i)],
        'count': songs.length,
        'created': '2026-10-0${songs.first % 9 + 1}T10:00:00Z',
      };
  final playlists = <String, dynamic>{
    for (final p in [
      playlist('demo-monsoon', 'Monsoon Melodies', [2, 7, 0, 9, 4, 11, 5], owner: 'demo-kaayal', language: 'Malayalam'),
      playlist('demo-kaayalkara', 'Kaayalkara (Full Album)', [0, 2, 8], owner: 'demo-kaayal', language: 'Malayalam'),
      playlist('demo-ml-hits', 'Malayalam Hits 2026', malayalam.reversed.toList(), owner: 'demo-kaayal', language: 'Malayalam'),
      playlist('demo-theru', 'Thendral Theru Jukebox', [12, 14, 17, 21], owner: 'demo-thendral', language: 'Tamil'),
      playlist('demo-ta-melodies', 'Tamil Melodies', tamil, owner: 'demo-thendral', language: 'Tamil'),
      playlist('demo-ta-night', 'Late Night Tamil', [18, 20, 15, 23], owner: 'demo-thendral', language: 'Tamil'),
      playlist(favouritesId, 'Favourites', [1, 13, 4, 16, 9, 22], local: true),
      playlist(savedId, 'Saved songs', [6, 19, 3], local: true),
      playlist('demo-night', 'Night drive', [1, 15, 9, 20, 4, 23, 10, 18], local: true),
      playlist('demo-rain', 'Rain songs', [2, 13, 7, 21, 5], local: true),
    ])
      asString(p['id']): p,
  };
  return {
    'version': libraryVersion,
    'updated': '2026-10-25T09:00:00Z',
    'users': {
      'demo-kaayal': {
        'id': 'demo-kaayal',
        'handle': '@KaayalRecords',
        'name': 'Kaayal Records',
        'language': 'Malayalam',
        'playlists': ['demo-monsoon', 'demo-kaayalkara', 'demo-ml-hits'],
      },
      'demo-thendral': {
        'id': 'demo-thendral',
        'handle': '@ThendralAudio',
        'name': 'Thendral Audio',
        'language': 'Tamil',
        'playlists': ['demo-theru', 'demo-ta-melodies', 'demo-ta-night'],
      },
    },
    'playlists': playlists,
    'tracks': tracks,
    'removed': <String, dynamic>{},
    'mixes': [
      {'id': 'mix-malayalam', 'title': 'Malayalam mix', 'sources': [{'type': 'language', 'id': 'Malayalam'}]},
      {'id': 'mix-tamil', 'title': 'Tamil mix', 'sources': [{'type': 'language', 'id': 'Tamil'}]},
      {
        'id': 'mix-rainy',
        'title': 'Rainy evenings',
        'sources': [
          {'type': 'playlist', 'id': 'demo-rain'},
          {'type': 'playlist', 'id': 'demo-monsoon'},
        ],
      },
    ],
  };
}

/// Made-for-you playlists already made for today, this week and this month.
Json _history(Json library) {
  final now = DateTime.now();
  final random = Random(7);
  final ids = [for (var i = 0; i < _songs.length; i++) _id(i)];
  Json made(String kind) => {
        'key': periodKey(kind, now),
        'made': '2026-10-25T08:00:00Z',
        'tracks': (List.of(ids)..shuffle(random)).take(20).toList(),
      };
  return {
    'version': 1,
    // A week of listening for Your music in numbers, the first songs most.
    'plays': [
      for (var i = 0; i < 90; i++)
        {
          'id': ids[(random.nextInt(ids.length) * random.nextInt(ids.length)) ~/ ids.length],
          'at': now.millisecondsSinceEpoch ~/ 1000 - (89 - i) * 6700,
          'heard': i % 6 == 0 ? 12 : 240,
          'length': 240,
        },
    ],
    'tracks': library['tracks'],
    'made': {for (final kind in madeKinds) kind: made(kind)},
  };
}

// ------------------------------------------------------------------ covers

/// Album covers drawn here: a gradient, a sun or moon and hills, in a hue of
/// their own. url -> PNG.
Future<Map<String, Uint8List>> _drawCovers() async {
  final out = <String, Uint8List>{};
  const side = 360.0;
  for (var i = 0; i < _songs.length; i++) {
    final hue = (i * 47.0 + 330) % 360;
    final top = HSLColor.fromAHSL(1, hue, 0.65, 0.55).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.7, 0.22).toColor();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, side, side);
    canvas.drawRect(
      rect,
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(side * 0.3, side), [top, bottom]),
    );
    final glow = HSLColor.fromAHSL(1, (hue + 200) % 360, 0.9, 0.75).toColor();
    final sun = Offset(side * (0.25 + (i % 5) * 0.12), side * (0.3 + (i % 3) * 0.06));
    canvas.drawCircle(sun, side * 0.2, Paint()..shader = ui.Gradient.radial(sun, side * 0.2, [glow, glow.withValues(alpha: 0)]));
    canvas.drawCircle(sun, side * 0.09, Paint()..color = glow);
    for (var layer = 0; layer < 3; layer++) {
      final y = side * (0.62 + layer * 0.12);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= side; x += 12) {
        path.lineTo(x, y - sin(x / side * pi * (2 + layer) + i) * side * 0.06);
      }
      path
        ..lineTo(side, side)
        ..lineTo(0, side)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.18 + layer * 0.12));
    }
    final image = await recorder.endRecording().toImage(side.toInt(), side.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    out[_art(i)] = png!.buffer.asUint8List();
  }
  return out;
}

/// An HttpClient that only knows the drawn covers; everything else is a 404.
class _CoverOverrides extends HttpOverrides {
  _CoverOverrides(this.covers);
  final Map<String, Uint8List> covers;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _CoverClient(covers);
}

class _CoverClient implements HttpClient {
  _CoverClient(this.covers);
  final Map<String, Uint8List> covers;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _CoverRequest(covers[url.toString()]);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => getUrl(url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => getUrl(Uri.https(host, path));

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoverRequest implements HttpClientRequest {
  _CoverRequest(this.body);
  final Uint8List? body;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _CoverResponse(body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoverResponse extends Stream<List<int>> implements HttpClientResponse {
  _CoverResponse(this.body);
  final Uint8List? body;

  @override
  int get statusCode => body == null ? 404 : 200;

  @override
  int get contentLength => body?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([?body])
          .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
