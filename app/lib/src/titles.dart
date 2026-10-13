// Turn YouTube video titles from South Indian music labels into song metadata.
// A port of paattu/titles.py (keep the two in step; test/titles_test.dart
// runs the same cases as tests/test_titles.py).
//
//     Thalatherichavar - Video | Romancham | Sushin Shyam | Saregama Malayalam
//     Vaathi Coming Video Song | Master | Thalapathy Vijay | Anirudh Ravichander
//     Kanmani Anbodu Kadhalan (Lyric Video) | Guna | Kamal Haasan | Ilaiyaraaja
//     Malare - Premam Song | Nivin Pauly | Sai Pallavi
//
// cleanTitle() pulls out the song, the movie (or album), the remaining
// credits, and what kind of upload it is (video, lyrical, audio, jukebox, ...).

import 'util.dart';

// Upload-type words that decorate a song name; removed from the title.
const _decorations = [
  r'official\s+(?:full\s+)?(?:video|lyric(?:al)?\s+video|lyrics?|audio|music\s+video|song)(?:\s+song)?',
  r'full\s+video\s+songs?', r'full\s+songs?', r'full\s+video', r'video\s+songs?', r'song\s+video',
  r'lyric(?:al)?\s+(?:video\s+)?songs?', r'lyric(?:al)?\s+videos?', r'lyrics?', r'lyrical',
  r'audio\s+songs?', r'audio\s+jukebox', r'video\s+jukebox', r'jukebox', r'audio',
  r'promo\s+songs?', r'promo\s+video', r'music\s+video', r'video',
  r'lyrical\s*\+\s*karaoke(?:\s+video)?', r'karaoke\s+video',
  r'\d+k(?:\s*/\s*\d+k)?(?:\s+video)?', r'\d+\s*fps', r'hd', r'hq', r'hi-?res(?:\s+audio)?', r'\d+\s*-?bit',
  r'remastered', r'dolby\s+atmos', r'5\.1', r'exclusive',
  r'(?:malayalam|tamil)\s+(?:film\s+|movie\s+)?songs?', r'(?:malayalam|tamil)', r'(?:movie|film)\s+songs?',
  r'songs?',
];

final _decorationRe = RegExp('^(?:${_decorations.join('|')})\$', caseSensitive: false);
// The same words when they trail a song name: "Vaathi Coming Video Song".
final _trailingRe = RegExp('(?:[\\s\\-–—:|]+(?:${_decorations.join('|')}))+\\s*\$', caseSensitive: false);
final _bracketsRe = RegExp(r'\s*[\(\[\{]([^\)\]\}]*)[\)\]\}]');
final _separatorsRe = RegExp(r'\s*[|｜•]\s*|\s+//\s+');
final _dashRe = RegExp(r'\s+[-–—]\s+');
final _hashtagRe = RegExp(r'(?:^|\s)#([\p{L}\p{M}\p{N}_]+)', unicode: true);
// "Premam Song": a movie name followed by a bare "Song".
final _bareSongRe = RegExp(r'^(.+?)\s+songs?$', caseSensitive: false);
const _notAMovie = {
  'video', 'lyric', 'lyrical', 'audio', 'full', 'official', 'title', 'promo', 'movie', 'film', //
  'theme', '8k', '4k', 'hd', 'fps', 'malayalam', 'tamil',
};
final _leadingNoiseRe = RegExp(r'^(?:exclusive|new|latest|superhit|super hit)\s*[-–—:]\s*', caseSensitive: false);
// A segment that names itself as the song: "Kaathalae Kaathalae Video Song".
final _videoSongRe =
    RegExp(r'\b(?:video|lyric(?:al)?(?:\s+video)?|full(?:\s+video)?)\s+songs?\s*$', caseSensitive: false);
final _fromRe = RegExp('^from\\s+["\'“‘]?(.+?)["\'”’]?\$', caseSensitive: false);
final _movieSongsRe = RegExp(r'^(.+?)\s+songs$', caseSensitive: false);
final _officialPlaylistRe = RegExp(r'\s*[-–—]\s*official\s+(?:playlist|jukebox|album)\s*$', caseSensitive: false);
final _nonWordRe = RegExp(r'[^\p{L}\p{M}\p{N}_]+', unicode: true);

/// Labels and channels whose names show up as a credit segment.
const labels = {
  'saregama malayalam', 'saregama tamil', 'saregama south', 'saregama', 'saregama music', //
  'sony music south', 'sony music malayalam', 'sony music india', 'sony music',
  'think music', 'think music india', 'think music malayalam', 'muzik247', 'muzik 247',
  'divo', 'divo music', 'lahari music', 'lahari music tamil', 't-series', 't-series tamil',
  'tseries tamil', 'u1 records', 'manorama music', 'manorama music songs', 'millennium audios',
  'goodwill entertainments', 'satyam audios', 'east coast', 'zee music south', 'zee music company',
  'aditya music', 'aditya music tamil', 'magic frames', 'magic frames music', 'friday music company',
  'wonderwall media', 'mango music', 'mango music malayalam', 'sun music', 'sun tv',
};

class CleanTitle {
  const CleanTitle(this.title, this.movie, this.credits, this.kind);
  final String title;
  final String movie;
  final List<String> credits;
  final String kind;

  @override
  String toString() => 'CleanTitle($title, $movie, $credits, $kind)';
}

String _stripDecorations(String text) {
  text = squash(text);
  String? previous;
  while (previous != text) {
    previous = text;
    text = stripChars(text.replaceFirst(_trailingRe, '').trim(), ' -–—:|,');
  }
  return text;
}

bool _has(String pattern, String text) => RegExp(pattern).hasMatch(text);

/// What sort of upload a title describes.
String uploadKind(String raw) {
  final t = raw.toLowerCase();
  if (_has(r'\b(?:trailer|teaser|first look|glimpse|making|bts|behind the scenes)\b', t)) return 'trailer';
  if (_has(r'\b(?:jukebox|non[\s-]?stop|back\s+to\s+back|audio songs|all songs|full album|mashup|medley)\b', t)) {
    return 'jukebox';
  }
  if (t.contains('karaoke')) return 'karaoke';
  if (_has(r'\b(?:cover|unplugged|reprise|remix|recreated)\b', t)) return 'cover';
  if (_has(r'\blive\b(?!\s+(?:love|life))', t)) return 'live';
  if (_has(r'\blyric', t)) return 'lyrical';
  if (_has(r'\bpromo\b', t)) return 'promo';
  if (_has(r'\baudio\b', t)) return 'audio';
  return 'video';
}

List<String> _segments(String text) =>
    text.split(_separatorsRe).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// Split a label upload title into title, movie, credits and kind.
CleanTitle cleanTitle(String rawTitle, [String channel = '']) {
  final raw = squash(rawTitle);
  final kind = uploadKind(raw);
  final channelKey = squash(channel).toLowerCase();

  // Bracketed notes: "(Lyric Video)", "[4K]", "(From "Leo")".
  var movieHint = '';
  var text = raw.replaceAllMapped(_bracketsRe, (m) {
    final inner = m.group(1)!.trim();
    final found = _fromRe.firstMatch(inner);
    if (found != null) {
      movieHint = found.group(1)!.trim();
      return '';
    }
    return inner.isEmpty || _decorationRe.hasMatch(inner) ? '' : ' ($inner)';
  });
  text = text.replaceAllMapped(_hashtagRe, (m) => ' ${m.group(1)}').trim();

  final segments = _segments(text);
  if (segments.isEmpty) return CleanTitle(raw, movieHint, const [], kind);

  final head = segments.first.replaceFirst(_leadingNoiseRe, '');
  var rest = segments.sublist(1);
  var movie = movieHint;
  var title = head;

  // The part around " - " is either decoration, the movie, or the song:
  //   "Song - Video Song"                    decoration
  //   "Malare - Premam Song"                 song - movie
  //   "Kumki - Onnum Puriyala Video Song"    movie - song (decorated tail)
  //   "Song - Movie" / "Artist - Song"       ambiguous; read as song - movie
  final dash = _dashRe.firstMatch(head);
  final split = dash != null;
  if (dash != null) {
    final left = head.substring(0, dash.start).trim();
    final tail = head.substring(dash.end).trim();
    final tailClean = _stripDecorations(tail);
    final bare = _bareSongRe.firstMatch(tail);
    if (tailClean.isEmpty || _decorationRe.hasMatch(tail)) {
      title = left;
    } else if (channelKey.isNotEmpty && left.toLowerCase() == channelKey) {
      // "Sushin Shyam - Ray (Official Video)" on Sushin Shyam's channel
      title = tailClean;
      rest = [left, ...rest];
    } else if (bare != null && !_notAMovie.contains(bare.group(1)!.split(' ').last.toLowerCase())) {
      title = left;
      if (movie.isEmpty) movie = _stripDecorations(bare.group(1)!);
    } else if (tailClean.toLowerCase() != squash(tail).toLowerCase()) {
      title = tailClean;
      if (movie.isEmpty) movie = _stripDecorations(left);
    } else {
      title = left;
      if (movie.isEmpty && tailClean.split(' ').length <= 5) movie = tailClean;
    }
  }

  // Think Music style, the movie first and then the song named as one:
  //   "96 Songs | Kaathalae Kaathalae Song | Vijay Sethupathi, Trisha | …"
  //   "96 | Kaathalae Kaathalae Video Song | Vijay Sethupathi, Trisha | …"
  if (!split && rest.isNotEmpty && movieHint.isEmpty) {
    final second = _stripDecorations(rest.first);
    final named = second.isNotEmpty &&
        second.toLowerCase() != squash(rest.first).toLowerCase() &&
        !labels.contains(second.toLowerCase());
    final movieSongs = _movieSongsRe.firstMatch(head);
    if (named && (movieSongs != null || (_stripDecorations(head) == head && _videoSongRe.hasMatch(rest.first)))) {
      movie = movieSongs != null ? movieSongs.group(1)!.trim() : head;
      title = second;
      rest = rest.sublist(1);
    }
  }

  title = _stripDecorations(title);

  final credits = <String>[];
  for (final segment in rest) {
    final cleaned = _stripDecorations(segment);
    final key = cleaned.toLowerCase();
    if (cleaned.isEmpty || _decorationRe.hasMatch(segment) || labels.contains(key) || key == channelKey) continue;
    if (movie.isEmpty) {
      movie = cleaned;
      continue;
    }
    if (key != movie.toLowerCase()) credits.add(cleaned);
  }

  if (title.isEmpty) title = movie.isNotEmpty ? movie : raw;
  return CleanTitle(title, movie, credits, kind);
}

/// Shorten a playlist title: drop the trailing '| Label' and decorations.
String playlistTitle(String raw, [String channel = '']) {
  final text = squash(raw);
  final segments = _segments(text);
  final channelKey = squash(channel).toLowerCase();
  var keep = segments.where((s) => !labels.contains(s.toLowerCase()) && s.toLowerCase() != channelKey).toList();
  if (keep.isEmpty) keep = segments.isNotEmpty ? segments : [text];
  final head = keep.first.replaceFirst(_officialPlaylistRe, '').trim();
  return head.isNotEmpty ? head : text;
}

/// Identity of a song across its video / lyrical / audio uploads.
String songKey(Json track) {
  final title = asString(track['title']).toLowerCase().replaceAll(_nonWordRe, '');
  final movie = asString(track['movie']).toLowerCase().replaceAll(_nonWordRe, '');
  return '$title|$movie';
}

final _malayalamWords = RegExp('malayalam|mollywood');
final _tamilWords = RegExp('tamil|kollywood');
final _malayalamScript = RegExp('[ഀ-ൿ]+');
final _tamilScript = RegExp('[஀-௿]+');

/// Malayalam / Tamil from names and titles; [fallback] when neither shows.
String guessLanguage(Iterable<String?> texts, {String fallback = ''}) {
  final joined = texts.where((t) => t != null && t.isNotEmpty).join(' ');
  final lower = joined.toLowerCase();
  final malayalam = _malayalamWords.allMatches(lower).length + _malayalamScript.allMatches(joined).length;
  final tamil = _tamilWords.allMatches(lower).length + _tamilScript.allMatches(joined).length;
  if (malayalam > tamil) return 'Malayalam';
  if (tamil > malayalam) return 'Tamil';
  return fallback;
}
