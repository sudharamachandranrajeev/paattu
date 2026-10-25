// The charts: what's played most this week, by language, across the sites
// that say so in the open. JioSaavn's editors keep a weekly Top 50 by
// streams, a most searched list and a most streamed love songs list for each
// language (content.getCharts, asked in that language); YouTube Music's
// charts have the week's most watched videos for some (Tamil, Telugu, Hindi,
// Punjabi, not Malayalam). The top chart is both, taken in turn and once each.
//
// Songs you turned down (history.dart's turnedDown) are left out. Each chart
// is kept in charts.json in the app's cache for 12 hours. paattu/charts.py
// makes the same ones on the desktop.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'history.dart';
import 'log.dart';
import 'radio.dart' show interleaveSongs;
import 'sources/jiosaavn.dart';
import 'sources/sources.dart' show youtubeSongs;
import 'sources/youtube.dart' show playlistDetails;
import 'sources/youtube_music.dart';
import 'track.dart';
import 'util.dart';

const chartLanguages = ['Malayalam', 'Tamil', 'Hindi', 'Telugu', 'Kannada', 'Punjabi'];
const chartKinds = ['top', 'searched', 'love'];

/// Songs in a chart, at most.
const chartSize = 50;

/// How long a chart fetched is kept.
const chartKeep = Duration(hours: 12);

String chartTitle(String kind) => switch (kind) {
      'top' => 'Top of the week',
      'searched' => 'Most searched',
      _ => 'Love songs',
    };

String chartBlurb(String kind, String language) => switch (kind) {
      'top' => 'The $language songs played most this week on JioSaavn and YouTube',
      'searched' => 'The $language songs looked for most on JioSaavn',
      _ => 'The $language love songs streamed most on JioSaavn',
    };

String saavnChartTitle(String kind, String language) => switch (kind) {
      'top' => '$language: India Superhits Top 50',
      'searched' => 'Most Searched Songs - $language',
      _ => 'Most Streamed Love Songs: $language',
    };

String? youtubeChartTitle(String kind, String language) => kind == 'top' ? 'Top Weekly Videos $language' : null;

/// Where a chart's songs are: the JioSaavn playlist page, the YouTube
/// playlist id (either can be null) and a picture, given JioSaavn's charts
/// for the language and YouTube Music's (charts.py's sources_of).
Json chartSources(String kind, String language, List<Json> saavn, Map<String, String> youtube) {
  final wanted = saavnChartTitle(kind, language).toLowerCase();
  final found = saavn.where((c) => asString(c['title']).trim().toLowerCase() == wanted).firstOrNull ?? const {};
  final title = youtubeChartTitle(kind, language);
  final url = asString(found['perma_url']);
  return {
    'kind': kind,
    'language': language,
    'saavn': url.isEmpty ? null : url,
    'youtube': title == null ? null : youtube[title],
    'art': asString(found['image']),
  };
}

/// The songs of a chart's lists taken in turn by rank, once each, leaving out
/// [avoid], up to [chartSize].
List<Json> mergeChart(List<List<Json>> lists, Set<String> avoid) =>
    interleaveSongs(lists, avoid: {...avoid}, limit: chartSize);

/// The languages to show charts for: the ones picked that have charts.
List<String> pickedChartLanguages(List<String> picked) {
  final out = [for (final l in picked) if (chartLanguages.contains(l)) l];
  return out.isEmpty ? const ['Malayalam', 'Tamil'] : out;
}

class Charts extends ChangeNotifier {
  Charts(this.history, this.file);

  final History history;
  final File file;
  Json _data = {};
  bool _read = false;

  static String key(String kind, String language) => '$kind:${language.toLowerCase()}';

  Future<void> _load() async {
    if (_read) return;
    _read = true;
    try {
      if (await file.exists()) _data = asJson(jsonDecode(await file.readAsString()));
    } catch (error) {
      problemLog.warn('charts: ${errorText(error)}');
    }
    notifyListeners();
  }

  /// Read what was kept, for the Home tiles.
  Future<void> load() => _load();

  /// The chart as last fetched: when, its picture and songs. Null when there
  /// isn't one.
  ({DateTime fetched, String art, List<Json> tracks})? kept(String kind, String language) {
    final entry = asJson(_data[key(kind, language)]);
    final tracks = asList(entry['tracks']).map(asJson).toList();
    if (tracks.isEmpty) return null;
    return (
      fetched: DateTime.fromMillisecondsSinceEpoch((toInt(entry['fetched']) ?? 0) * 1000),
      art: asString(entry['art']),
      tracks: tracks,
    );
  }

  /// A chart's songs, fetched when the copy kept is older than 12 hours (or
  /// [refresh]), less the songs you turned down.
  Future<List<Json>> chart(String kind, String language, {bool refresh = false}) async {
    await _load();
    final now = DateTime.now();
    final old = kept(kind, language);
    if (!refresh && old != null && now.difference(old.fetched) < chartKeep) return _withoutTurnedDown(old.tracks);
    final saavn = await jiosaavnCharts(language).catchError((Object _) => <Json>[]);
    final youtube = youtubeChartTitle(kind, language) == null
        ? const <String, String>{}
        : await musicCharts().catchError((Object _) => <String, String>{});
    final where = chartSources(kind, language, saavn, youtube);
    final saavnUrl = where['saavn'] as String?;
    final youtubeId = where['youtube'] as String?;
    final lists = await Future.wait([
      if (saavnUrl != null) resolveJioSaavn(saavnUrl).catchError((Object _) => <Json>[]),
      if (youtubeId != null)
        playlistDetails(youtubeId).then(youtubeSongs).catchError((Object _) => <Json>[]),
    ]);
    final songs = mergeChart(lists.where((l) => l.isNotEmpty).toList(), const {});
    if (songs.isEmpty) {
      if (old != null) return _withoutTurnedDown(old.tracks);
      throw SourceException("couldn't get the $language chart. Check the internet connection");
    }
    final art = asString(where['art']);
    _data[key(kind, language)] = <String, dynamic>{
      'fetched': epochSeconds(now),
      'art': art.isNotEmpty ? art : songs.map(trackArt).nonNulls.firstOrNull ?? '',
      'tracks': [for (final s in songs) storedTrack(s)],
    };
    notifyListeners();
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_data), flush: true);
      await tmp.rename(file.path);
    } catch (error) {
      problemLog.warn('charts: ${errorText(error)}');
    }
    return _withoutTurnedDown(songs);
  }

  List<Json> _withoutTurnedDown(List<Json> songs) {
    final down = turnedDown(history.plays, keyOf: (id) => songIdentity(history.track(id) ?? {'id': id}));
    return [for (final s in songs) if (!down.contains(trackId(s)) && !down.contains(songIdentity(s))) s];
  }
}
