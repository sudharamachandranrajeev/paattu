// The app's own settings (settings.json beside library.json) and themes: the
// desktop Paattu's palettes, led by Chembarathi (the default since 0.5).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'device.dart';
import 'links.dart';
import 'sound.dart';
import 'ui/glass.dart';
import 'util.dart';

class PaattuTheme {
  const PaattuTheme(
    this.id,
    this.name,
    this.description, {
    required this.dark,
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.highlight,
  });

  final String id;
  final String name;
  final String description;
  final bool dark;
  final Color background;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color highlight;

  ThemeData get data {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
      primary: accent,
      onPrimary: dark ? background : Colors.white,
      secondary: highlight,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainerLowest: background,
      surfaceContainerLow: Color.lerp(background, surface, 0.5),
      surfaceContainer: surface,
      surfaceContainerHigh: Color.lerp(surface, foreground, 0.05),
      surfaceContainerHighest: Color.lerp(surface, foreground, 0.09),
      outline: muted.withValues(alpha: 0.6),
      outlineVariant: muted.withValues(alpha: 0.25),
    );
    final edge = BorderSide(color: scheme.glassEdge);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Poppins',
      // Pages are see-through: the backdrop is painted under each one (glass.dart).
      scaffoldBackgroundColor: Colors.transparent,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {for (final platform in TargetPlatform.values) platform: const BackdropTransitions()},
      ),
      cardTheme: CardThemeData(
        color: scheme.glass,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: edge),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.glass,
        selectedColor: accent.withValues(alpha: 0.28),
        side: edge,
        shape: const StadiumBorder(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w600, color: foreground),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: accent,
        labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        dragHandleColor: muted.withValues(alpha: 0.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: edge),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: edge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.glass,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: edge),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: edge),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: foreground,
        inactiveTrackColor: muted.withValues(alpha: 0.25),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

const themes = [
  PaattuTheme(
    'chembarathi',
    'Chembarathi',
    'Hibiscus red and marigold on a night sky',
    dark: true,
    background: Color(0xFF0D0608),
    surface: Color(0xFF1C0D11),
    foreground: Color(0xFFFFF1F2),
    muted: Color(0xFFBC979D),
    accent: Color(0xFFF0405A),
    highlight: Color(0xFFF7942E),
  ),
  PaattuTheme(
    'paattu',
    'Paattu',
    'Teal, the app icon\'s colours',
    dark: true,
    background: Color(0xFF0B1514),
    surface: Color(0xFF13211F),
    foreground: Color(0xFFE6F4F1),
    muted: Color(0xFF86A7A1),
    accent: Color(0xFF2DD4BF),
    highlight: Color(0xFF99F6E4),
  ),
  PaattuTheme(
    'filter-coffee',
    'Filter Coffee',
    'Degree coffee in a davara-tumbler',
    dark: true,
    background: Color(0xFF1B1410),
    surface: Color(0xFF261C16),
    foreground: Color(0xFFF3E9DF),
    muted: Color(0xFFA68E7B),
    accent: Color(0xFFD49A5A),
    highlight: Color(0xFFE8C8A0),
  ),
  PaattuTheme(
    'kanjeevaram',
    'Kanjeevaram',
    'Kanchipuram silk: deep magenta with gold zari',
    dark: true,
    background: Color(0xFF1E0A14),
    surface: Color(0xFF2E1220),
    foreground: Color(0xFFF6E7D8),
    muted: Color(0xFFB89A8A),
    accent: Color(0xFFE0B44A),
    highlight: Color(0xFFD81B60),
  ),
  PaattuTheme(
    'kasavu',
    'Kasavu',
    'Kerala kasavu: cream silk with a gold border',
    dark: false,
    background: Color(0xFFF6F0E1),
    surface: Color(0xFFEDE3CB),
    foreground: Color(0xFF2B2416),
    muted: Color(0xFF7A6A4A),
    accent: Color(0xFFB8901F),
    highlight: Color(0xFF8C6A12),
  ),
  PaattuTheme(
    'monsoon',
    'Monsoon',
    'Kerala backwaters in the rain',
    dark: true,
    background: Color(0xFF0F1A17),
    surface: Color(0xFF16241F),
    foreground: Color(0xFFE3F2EC),
    muted: Color(0xFF7FA597),
    accent: Color(0xFF4FC3A1),
    highlight: Color(0xFF8BD3E6),
  ),
  PaattuTheme(
    'neelakurinji',
    'Neelakurinji',
    'Munnar hills in kurinji bloom',
    dark: true,
    background: Color(0xFF14122A),
    surface: Color(0xFF1E1B3A),
    foreground: Color(0xFFECEAFF),
    muted: Color(0xFF9A95C6),
    accent: Color(0xFF8E7CFF),
    highlight: Color(0xFFC7A8FF),
  ),
  PaattuTheme(
    'theyyam',
    'Theyyam',
    'Theyyam: fire red, turmeric and black',
    dark: true,
    background: Color(0xFF120A08),
    surface: Color(0xFF1F110D),
    foreground: Color(0xFFFBEDE6),
    muted: Color(0xFFB98C7E),
    accent: Color(0xFFFF5A1F),
    highlight: Color(0xFFFFC400),
  ),
];

PaattuTheme themeById(String id) => themes.firstWhere((t) => t.id == id, orElse: () => themes.first);

/// How Now Playing shows the song. The names are what settings.json and the
/// desktop Paattu's config keep.
enum NowPlayingStyle {
  cover('Cover', "The cover with round corners on a blurred copy of itself; the song's video plays blurred behind it"),
  video('Video first', "The cover makes way for the song's video when there is one"),
  full('Full picture', 'The picture fills the top of the screen, sharp, with the video over it'),
  record('Record', 'The cover on a record that turns while the song plays');

  const NowPlayingStyle(this.label, this.description);
  final String label;
  final String description;
}

/// How each line of a song's words comes in over its cover. The names are
/// what the desktop Paattu's config keeps (lyrics.effect).
enum LyricEffect {
  pop('3d', 'Pop out in 3D', 'Each line turns towards you out of the cover and settles'),
  comic('comic', 'Comic pop', 'Each line bursts in on a starburst, comic-book style, and pops away'),
  karaoke('karaoke', 'Karaoke', 'Each line fills with colour as it is sung'),
  glow('glow', 'Glow', 'Each line glows into focus and drifts up as it goes'),
  fade('fade', 'Fade', 'Each line fades in as the last fades out'),
  plain('plain', 'Plain', 'Each line simply takes the place of the last');

  const LyricEffect(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;
}

class Settings extends ChangeNotifier {
  Settings(this.file);

  final File file;
  Json _data = {};
  Timer? _saveTimer;

  Future<void> load() async {
    try {
      if (await file.exists()) _data = asJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      _data = {};
    }
    notifyListeners();
  }

  void _set(String key, Object? value) {
    _data[key] = value;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), save);
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(_data));
    await tmp.rename(file.path);
  }

  PaattuTheme get theme => themeById(asString(_data['theme']));
  set themeId(String id) => _set('theme', id);

  /// Where songs come from: one site (YouTube unless chosen otherwise) or
  /// 'all' of them. A song that won't play is still looked for on the others.
  String get musicFrom {
    final chosen = asString(_data['musicFrom']);
    return chosen == 'all' || searchSites.contains(chosen) ? chosen : 'youtube';
  }

  set musicFrom(String source) => _set('musicFrom', source);

  /// The sites a search asks, in order.
  List<String> get musicSites => musicFrom == 'all' ? List.of(searchSites) : [musicFrom];

  /// JioSaavn at 320 kbps, or 128 to save data.
  bool get saveData => _data['saveData'] == true;
  set saveData(bool on) => _set('saveData', on);

  /// Android: the screen stays on while Paattu is in front (on unless turned off).
  bool get screenAwake => _data['screenAwake'] != false;
  set screenAwake(bool on) => _set('screenAwake', on);

  /// Soft sounds when you tap, go to another page or change the song (on
  /// unless turned off; ui_sounds.dart).
  bool get uiSounds => _data['uiSounds'] != false;
  set uiSounds(bool on) => _set('uiSounds', on);

  /// The song's video, blurred, behind Now Playing (on unless turned off).
  bool get videoBackground => _data['videoBackground'] != false;
  set videoBackground(bool on) => _set('videoBackground', on);

  /// Video mode: Now Playing shows the song's video, playing with its own
  /// sound (off unless turned on; the Audio | Video switch on Now Playing).
  bool get videoMode => _data['videoMode'] == true;
  set videoMode(bool on) => _set('videoMode', on);

  /// How Now Playing looks (the cover, the video first, the full picture or a record).
  NowPlayingStyle get nowPlayingStyle =>
      NowPlayingStyle.values.firstWhere((s) => s.name == _data['nowPlayingStyle'], orElse: () => NowPlayingStyle.cover);
  set nowPlayingStyle(NowPlayingStyle style) => _set('nowPlayingStyle', style.name);

  /// How blurred the video behind Now Playing is, 0 (sharp) to 100.
  int get videoBlur => (toInt(_data['videoBlur']) ?? 30).clamp(0, 100);
  set videoBlur(int level) => _set('videoBlur', level.clamp(0, 100));

  /// Now Playing and the mini player take their colours from the song's cover.
  bool get coverColors => _data['coverColors'] == true;
  set coverColors(bool on) => _set('coverColors', on);

  /// The cover's subject lifted out of the picture, tilting in 3D (on unless turned off).
  bool get coverDepth => _data['coverDepth'] != false;
  set coverDepth(bool on) => _set('coverDepth', on);

  /// The song's words over its cover on Now Playing (on unless turned off).
  bool get lyricsShown => _data['lyricsShown'] != false;
  set lyricsShown(bool on) => _set('lyricsShown', on);

  /// How each line of the words comes in.
  LyricEffect get lyricEffect =>
      LyricEffect.values.firstWhere((e) => e.key == _data['lyricEffect'], orElse: () => LyricEffect.pop);
  set lyricEffect(LyricEffect effect) => _set('lyricEffect', effect.key);

  /// The cover's colours moving through the letters of the words (on unless turned off).
  bool get lyricGradient => _data['lyricGradient'] != false;
  set lyricGradient(bool on) => _set('lyricGradient', on);

  /// The words in English letters under a line in an Indian script (on unless turned off).
  bool get lyricsTransliterated => _data['lyricsTransliterated'] != false;
  set lyricsTransliterated(bool on) => _set('lyricsTransliterated', on);

  /// The bar of what the song is (film, year, singers...) above Up next.
  bool get songInfo => _data['songInfo'] != false;
  set songInfo(bool on) => _set('songInfo', on);

  /// Seconds one song fades into the next (0 for none).
  int get crossfade => (toInt(_data['crossfade']) ?? 3).clamp(0, 12);
  set crossfade(int seconds) => _set('crossfade', seconds.clamp(0, 12));

  /// Keep the songs listened to on this device, so they play with no internet.
  /// Off unless asked on a TV, which has little storage.
  bool get offlineAutoSave => _data['offlineAutoSave'] as bool? ?? !onTv;
  set offlineAutoSave(bool on) => _set('offlineAutoSave', on);

  /// Where the kept songs go: empty for the app's own folder. Only the desktop
  /// can write to a folder the person picked (Android keeps its apps' folders
  /// to themselves).
  String get offlineDir => asString(_data['offlineDir']);
  set offlineDir(String path) => _set('offlineDir', path);

  /// Space allowed for kept songs, in MB (0 for no limit): 2 GB, or 512 MB
  /// on a TV.
  int get offlineLimitMb => (toInt(_data['offlineLimitMb']) ?? (onTv ? 512 : 2048)).clamp(0, 1 << 20);
  set offlineLimitMb(int mb) => _set('offlineLimitMb', mb.clamp(0, 1 << 20));

  /// Whether Android has been asked once to leave Paattu out of battery
  /// optimisation (main.dart); Settings can ask again.
  bool get batteryAsked => _data['batteryAsked'] == true;
  set batteryAsked(bool asked) => _set('batteryAsked', asked);

  /// When the app last looked for a newer version, and what it found, so it
  /// doesn't ask GitHub on every start and can say "up to date" at once.
  String get updateChecked => asString(_data['updateChecked']);
  set updateChecked(String stamp) => _set('updateChecked', stamp);

  /// A newer version found and not installed yet (update.dart's Release.json).
  Json? get updateOffered {
    final value = _data['updateOffered'];
    return value is Map ? asJson(value) : null;
  }

  set updateOffered(Json? release) => _set('updateOffered', release);

  /// The languages Home shows charts for (charts.dart).
  List<String> get chartLanguages =>
      _data['chartLanguages'] is List ? asStrings(_data['chartLanguages']) : const ['Malayalam', 'Tamil'];
  set chartLanguages(List<String> languages) => _set('chartLanguages', languages);

  /// When the queue runs out, carry on with songs like the last one.
  bool get autoRadio => _data['autoRadio'] != false;
  set autoRadio(bool on) => _set('autoRadio', on);

  /// The ListenBrainz account plays are scrobbled to (listenbrainz.dart):
  /// empty when not connected.
  String get listenBrainzToken => asString(_data['listenBrainzToken']);
  String get listenBrainzUser => asString(_data['listenBrainzUser']);
  set listenBrainz(({String token, String user})? account) {
    _data['listenBrainzUser'] = account?.user;
    _set('listenBrainzToken', account?.token);
  }

  /// What was searched lately, newest first.
  List<String> get recentSearches => asStrings(_data['recentSearches']);

  void rememberSearch(String query) {
    final q = query.trim();
    if (q.isEmpty || isLink(q)) return;
    final recent = [q, ...recentSearches.where((r) => r.toLowerCase() != q.toLowerCase())].take(12).toList();
    _set('recentSearches', recent);
  }

  void forgetSearch(String query) => _set('recentSearches', recentSearches.where((r) => r != query).toList());

  double get volume => (_data['volume'] is num) ? (_data['volume'] as num).toDouble().clamp(0.0, 1.0) : 1.0;
  set volume(double v) => _set('volume', v);

  /// The equaliser, tone, balance and speed (the desktop Paattu's "sound").
  Sound get sound => Sound.fromJson(_data['sound']);
  set sound(Sound s) => _set('sound', s.toJson());
}
