// The app's own settings (settings.json beside library.json) and themes: the
// desktop Paattu's six palettes plus the default teal.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'links.dart';
import 'util.dart';

class PaattuTheme {
  const PaattuTheme(this.id, this.name, this.description,
      {required this.dark,
      required this.background,
      required this.surface,
      required this.foreground,
      required this.muted,
      required this.accent,
      required this.highlight});

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
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      cardTheme: CardThemeData(color: surface, elevation: 0, margin: EdgeInsets.zero),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.22),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.22),
      ),
      appBarTheme: AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: muted.withValues(alpha: 0.25),
        trackHeight: 3,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

const themes = [
  PaattuTheme('paattu', 'Paattu', 'Teal, the app icon\'s colours',
      dark: true,
      background: Color(0xFF0B1514),
      surface: Color(0xFF13211F),
      foreground: Color(0xFFE6F4F1),
      muted: Color(0xFF86A7A1),
      accent: Color(0xFF2DD4BF),
      highlight: Color(0xFF99F6E4)),
  PaattuTheme('filter-coffee', 'Filter Coffee', 'Degree coffee in a davara-tumbler',
      dark: true,
      background: Color(0xFF1B1410),
      surface: Color(0xFF261C16),
      foreground: Color(0xFFF3E9DF),
      muted: Color(0xFFA68E7B),
      accent: Color(0xFFD49A5A),
      highlight: Color(0xFFE8C8A0)),
  PaattuTheme('kanjeevaram', 'Kanjeevaram', 'Kanchipuram silk: deep magenta with gold zari',
      dark: true,
      background: Color(0xFF1E0A14),
      surface: Color(0xFF2E1220),
      foreground: Color(0xFFF6E7D8),
      muted: Color(0xFFB89A8A),
      accent: Color(0xFFE0B44A),
      highlight: Color(0xFFD81B60)),
  PaattuTheme('kasavu', 'Kasavu', 'Kerala kasavu: cream silk with a gold border',
      dark: false,
      background: Color(0xFFF6F0E1),
      surface: Color(0xFFEDE3CB),
      foreground: Color(0xFF2B2416),
      muted: Color(0xFF7A6A4A),
      accent: Color(0xFFB8901F),
      highlight: Color(0xFF8C6A12)),
  PaattuTheme('monsoon', 'Monsoon', 'Kerala backwaters in the rain',
      dark: true,
      background: Color(0xFF0F1A17),
      surface: Color(0xFF16241F),
      foreground: Color(0xFFE3F2EC),
      muted: Color(0xFF7FA597),
      accent: Color(0xFF4FC3A1),
      highlight: Color(0xFF8BD3E6)),
  PaattuTheme('neelakurinji', 'Neelakurinji', 'Munnar hills in kurinji bloom',
      dark: true,
      background: Color(0xFF14122A),
      surface: Color(0xFF1E1B3A),
      foreground: Color(0xFFECEAFF),
      muted: Color(0xFF9A95C6),
      accent: Color(0xFF8E7CFF),
      highlight: Color(0xFFC7A8FF)),
  PaattuTheme('theyyam', 'Theyyam', 'Theyyam: fire red, turmeric and black',
      dark: true,
      background: Color(0xFF120A08),
      surface: Color(0xFF1F110D),
      foreground: Color(0xFFFBEDE6),
      muted: Color(0xFFB98C7E),
      accent: Color(0xFFFF5A1F),
      highlight: Color(0xFFFFC400)),
];

PaattuTheme themeById(String id) => themes.firstWhere((t) => t.id == id, orElse: () => themes.first);

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

  /// The sites a search asks, in order.
  List<String> get searchSites {
    final chosen = asStrings(_data['searchSites']).where(searchSitesAll.contains).toList();
    return chosen.isEmpty ? List.of(searchSitesAll) : chosen;
  }

  set searchSites(List<String> sites) => _set('searchSites', sites);

  /// JioSaavn at 320 kbps, or 128 to save data.
  bool get saveData => _data['saveData'] == true;
  set saveData(bool on) => _set('saveData', on);

  double get volume => (_data['volume'] is num) ? (_data['volume'] as num).toDouble().clamp(0.0, 1.0) : 1.0;
  set volume(double v) => _set('volume', v);
}

const searchSitesAll = searchSites;
