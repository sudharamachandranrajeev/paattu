// Sound: the equaliser, preamp, bass, treble, balance and speed, as the
// desktop Paattu has them (paattu/sound.py; tests/sound_cases.json holds the
// numbers both must give).
//
// Windows and Linux play through libmpv, so they get the same graph of
// FFmpeg `equalizer` (peaking) filters: the only audio filter in the libmpv
// media_kit ships for Windows. A peaking filter with a tiny Q is a flat gain,
// which makes the preamp and the left / right levels. Each filter is named
// (equalizer@b3), so a slider can move it while it plays. Android has no
// libmpv: the phone's own equaliser gets this curve at its bands instead.
//
// The equaliser has fifteen bands, the ISO 2/3-octave centres. Peaking
// filters overlap, so the sliders are the levels wanted at the centres and
// the filters' own gains are worked out to give them (bandGains): least
// squares over the centres and the points between, twice, the second time
// with the interaction measured at the first gains (Valimaki and Liski,
// "Accurate cascade graphic equalizer", 2017).

import 'dart:math';

import 'util.dart';

/// The bands (Hz): the ISO 2/3-octave centres.
const soundBands = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

/// Each band filter's width (octaves): a little wider than the 2/3 octave
/// between bands, which measured the closest fit to the sliders.
const soundWidth = 0.8;

/// Settings from before 0.14: ten bands, one octave wide, uncompensated.
const oldSoundBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// dB either way: bands, preamp, bass, treble.
const soundLimit = 12.0;
const speedMin = 0.5;
const speedMax = 2.0;
const _label = 'paattu';

/// For drawing the curve and finding its peak.
const _rate = 48000;

class SoundPreset {
  const SoundPreset(this.id, this.name, this.bands, {this.saved = false});
  final String id;
  final String name;
  final List<double> bands;

  /// One of yours (it can be deleted), not a built-in.
  final bool saved;
}

/// The levels the ten-band presets gave at these centres, so they sound as before.
const builtInPresets = [
  SoundPreset('flat', 'Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  SoundPreset('melody', 'Melody', [-1.5, -2, -2, -1, -0.5, 1, 2, 3, 4.5, 4, 3.5, 3, 1, 0.5, -0.5]),
  SoundPreset('kuthu', 'Kuthu', [5, 6, 6.5, 4.5, 3, 2, 0.5, 0.5, 0.5, 1, 1.5, 2.5, 2.5, 2, 1]),
  SoundPreset('bass', 'Bass boost', [5, 6, 7, 5.5, 4.5, 3.5, 1.5, 0.5, 0, 0, 0, 0, 0, 0, 0]),
  SoundPreset('treble', 'Treble boost', [0, 0, 0, 0, 0, 0, 0, 0.5, 1, 2, 3.5, 5.5, 6, 7, 6.5]),
  SoundPreset('classical', 'Classical', [0, 0, 0, 0, 0, 0, 0, 0, -0.5, -2.5, -3.5, -4.5, -4, -4.5, -5]),
  SoundPreset('rock', 'Rock', [4, 4, 3.5, -0.5, -2.5, -4, -2, -0.5, 2, 3.5, 4.5, 6.5, 6, 6, 5]),
  SoundPreset('pop', 'Pop', [-0.5, 0.5, 3.5, 4, 4.5, 6, 4, 2.5, 0.5, -1, -1.5, -2, -1.5, -1.5, -1]),
  SoundPreset('dance', 'Dance', [5, 5.5, 6, 3, 1.5, 0.5, -0.5, -1.5, -4, -4.5, -4.5, -5, -1.5, -0.5, 0]),
  SoundPreset('jazz', 'Jazz', [2.5, 3, 3, 1.5, 1.5, 2, -0.5, -1.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3, 3]),
  SoundPreset('acoustic', 'Acoustic', [3.5, 4.5, 5.5, 4, 3, 2, 2, 2, 2.5, 3, 4, 5, 4, 3.5, 2.5]),
  SoundPreset('loudness', 'Loudness', [4, 5, 5.5, 3, 2, 0.5, -0.5, -1, -1, 0, 1, 3, 4.5, 5.5, 5.5]),
  SoundPreset('headphones', 'Headphones', [2.5, 3, 2.5, 1.5, 1, 0, 0, 0, 0, 1, 1.5, 3, 3, 3.5, 3.5]),
  SoundPreset('night', 'Late night', [-1, -1, -1, -0.5, 0.5, 1.5, 1.5, 1.5, 1, 0, -0.5, -1.5, -2.5, -3, -3]),
];

/// Whether [name] is a built-in preset's id or name (any case).
bool isBuiltInPreset(String name) {
  final n = name.trim().toLowerCase();
  return builtInPresets.any((p) => n == p.id || n == p.name.toLowerCase());
}

/// A peaking filter in the graph: its centre (Hz), width (octaves, or Q),
/// and the channel it touches (all of them when null).
class SoundFilter {
  const SoundFilter(this.name, this.f, this.w, {this.octaves = true, this.channel});
  final String name;
  final int f;
  final num w;
  final bool octaves;
  final String? channel;

  String get options => 'f=$f:t=${octaves ? 'o' : 'q'}:w=$w${channel == null ? '' : ':c=$channel'}';
}

/// The graph's filters, in order.
final soundFilters = [
  const SoundFilter('pre', 1000, 0.001, octaves: false),
  for (var i = 0; i < soundBands.length; i++) SoundFilter('b$i', soundBands[i], soundWidth),
  const SoundFilter('bass', 60, 3),
  const SoundFilter('treble', 10000, 2),
  const SoundFilter('left', 1000, 0.001, octaves: false, channel: 'FL'),
  const SoundFilter('right', 1000, 0.001, octaves: false, channel: 'FR'),
];

/// x to 0.1 dB, rounding halves up (as Python's floor(x * 10 + 0.5) / 10).
double tenth(num x) => (x * 10 + 0.5).floorToDouble() / 10;

/// x to 0.01, halves up.
double hundredth(num x) => (x * 100 + 0.5).floorToDouble() / 100;

/// 2.5 → "2.5", 3.0 → "3", -0.0 → "0".
String soundFmt(num x) {
  final t = tenth(x);
  if (t == 0) return '0';
  final text = t.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// "+2.5", "-3", "0".
String soundDb(num x) {
  final t = soundFmt(x);
  return x > 0 && t != '0' ? '+$t' : t;
}

/// "25", "1k", "1.6k", "16k".
String bandLabel(int f) => f < 1000 ? '$f' : f % 1000 == 0 ? '${f ~/ 1000}k' : '${f / 1000}k';

double _number(Object? value, double low, double high, [double fallback = 0]) {
  final x = switch (value) {
    final num n => n.toDouble(),
    final bool b => b ? 1.0 : 0.0,
    final String s => double.tryParse(s.trim()),
    _ => null,
  };
  if (x == null || x.isNaN) return fallback;
  return x.clamp(low, high).toDouble();
}

/// Fifteen band levels in range. Ten (settings from before 0.14) become the
/// levels their old filters gave at the new centres.
List<double> _bandsOf(Object? value) {
  List<Object?> values = asList(value);
  if (values.length == oldSoundBands.length) {
    final old = [
      for (var i = 0; i < oldSoundBands.length; i++)
        (SoundFilter('', oldSoundBands[i], 1), _number(values[i], -soundLimit, soundLimit)),
    ];
    values = [for (final f in soundBands) soundResponse(old, f.toDouble())];
  }
  final out = values.take(soundBands.length).map((v) => tenth(_number(v, -soundLimit, soundLimit))).toList();
  return List.unmodifiable([...out, for (var i = out.length; i < soundBands.length; i++) 0.0]);
}

/// Where the curve is matched to the sliders: each centre, and halfway
/// between two (their average there), which counts half: (Hz, band, band, weight).
final _fit = [
  for (var i = 0; i < soundBands.length; i++) (soundBands[i].toDouble(), i, i, 1.0),
  for (var i = 0; i + 1 < soundBands.length; i++) (sqrt(soundBands[i] * soundBands[i + 1]), i, i + 1, 0.5),
];

/// x with a·x = y (Gaussian elimination with partial pivoting).
List<double> _solve(List<List<double>> a, List<double> y) {
  final n = y.length;
  final m = [for (var i = 0; i < n; i++) [...a[i], y[i]]];
  for (var c = 0; c < n; c++) {
    var p = c;
    for (var r = c + 1; r < n; r++) {
      if (m[r][c].abs() > m[p][c].abs()) p = r;
    }
    final swap = m[c];
    m[c] = m[p];
    m[p] = swap;
    for (var r = 0; r < n; r++) {
      if (r == c || m[r][c] == 0) continue;
      final k = m[r][c] / m[c][c];
      for (var j = c; j <= n; j++) {
        m[r][j] -= k * m[c][j];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n] / m[i][i]];
}

final _bandGainsSeen = <String, List<double>>{};

/// The band filters' gains (dB) that put the curve at [bands]' levels.
List<double> bandGains(List<double> bands) {
  final key = bands.join(',');
  final seen = _bandGainsSeen[key];
  if (seen != null) return seen;
  final n = soundBands.length;
  var g = List<double>.filled(n, 0);
  if (bands.any((b) => b != 0)) {
    final want = [for (final (_, i, j, _) in _fit) (bands[i] + bands[j]) / 2];
    g = List<double>.filled(n, 12);
    for (var pass = 0; pass < 2; pass++) {
      final at = [for (final x in g) x.abs() >= 0.5 ? x : 12.0];
      // a[k][m]: filter m's level at fit point k, per dB of its gain.
      final a = [
        for (final (f, _, _, _) in _fit)
          [for (var m = 0; m < n; m++) soundResponse([(soundFilters[1 + m], at[m])], f) / at[m]],
      ];
      final normal = [
        for (var i = 0; i < n; i++)
          [
            for (var j = 0; j < n; j++)
              [for (var k = 0; k < a.length; k++) _fit[k].$4 * a[k][i] * a[k][j]].fold(0.0, (x, y) => x + y),
          ],
      ];
      final right = [
        for (var i = 0; i < n; i++) [for (var k = 0; k < a.length; k++) _fit[k].$4 * a[k][i] * want[k]].fold(0.0, (x, y) => x + y),
      ];
      g = _solve(normal, right);
    }
    g = [for (final x in g) x.clamp(-30.0, 30.0)];
  }
  if (_bandGainsSeen.length > 32) _bandGainsSeen.remove(_bandGainsSeen.keys.first);
  return _bandGainsSeen[key] = List.unmodifiable(g);
}

bool _sameBands(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The level (dB) at [freq] through peaking filters [(filter, gain)].
double soundResponse(Iterable<(SoundFilter, double)> filters, double freq) {
  final w = 2 * pi * freq / _rate;
  final c1 = cos(w), s1 = -sin(w), c2 = cos(2 * w), s2 = -sin(2 * w);
  var total = 0.0;
  for (final (filter, gain) in filters) {
    if (gain == 0) continue;
    final w0 = 2 * pi * filter.f / _rate;
    final sn = sin(w0), cs = cos(w0);
    // FFmpeg's octave width (af_biquads.c).
    final alpha = filter.octaves ? sn * _sinh(ln2 / 2 * filter.w * w0 / sn) : sn / (2 * filter.w);
    final a = pow(10, gain / 40).toDouble();
    final nr = 1 + alpha * a - 2 * cs * c1 + (1 - alpha * a) * c2;
    final ni = -2 * cs * s1 + (1 - alpha * a) * s2;
    final dr = 1 + alpha / a - 2 * cs * c1 + (1 - alpha / a) * c2;
    final di = -2 * cs * s1 + (1 - alpha / a) * s2;
    total += 10 * log((nr * nr + ni * ni) / (dr * dr + di * di)) / ln10;
  }
  return total;
}

double _sinh(double x) => (exp(x) - exp(-x)) / 2;

/// Where the peak is looked for: 20 Hz … 20 kHz, 24 steps an octave, and the bands.
final _grid = [for (var i = 0; i < 240; i++) 20 * pow(2, i / 24).toDouble(), for (final f in soundBands) f.toDouble()];

class Sound {
  const Sound({
    this.on = false,
    this.preset = 'flat',
    this.bands = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.preamp = 0,
    this.bass = 0,
    this.treble = 0,
    this.balance = 0,
    this.noclip = true,
    this.speed = 1,
    this.saved = const {},
  });

  /// [json] with every key, each in range.
  factory Sound.fromJson(Object? json) {
    final s = asJson(json);
    const d = Sound();
    final saved = <String, List<double>>{};
    for (final MapEntry(:key, :value) in asJson(s['presets']).entries) {
      if (key.trim().isNotEmpty && value is List) saved[key.trim()] = _bandsOf(value);
    }
    final preset = s.containsKey('preset') ? (s['preset'] is String ? s['preset'] as String : '') : d.preset;
    var bands = _bandsOf(s['bands']);
    // A built-in preset from before 0.14 is that preset in fifteen bands
    // (which are its old levels to the half dB).
    final builtIn = builtInPresets.where((p) => p.id == preset).firstOrNull;
    if (builtIn != null &&
        asList(s['bands']).length == oldSoundBands.length &&
        _sameBands([for (final b in bands) (b * 2 + 0.5).floorToDouble() / 2], builtIn.bands)) {
      bands = List.unmodifiable(builtIn.bands);
    }
    return Sound(
      on: s['on'] == true,
      preset: preset,
      bands: bands,
      preamp: tenth(_number(s['preamp'], -soundLimit, soundLimit)),
      bass: tenth(_number(s['bass'], -soundLimit, soundLimit)),
      treble: tenth(_number(s['treble'], -soundLimit, soundLimit)),
      balance: hundredth(_number(s['balance'], -1, 1)),
      noclip: s['noclip'] != false,
      speed: hundredth(_number(s['speed'], speedMin, speedMax, 1)),
      saved: Map.unmodifiable(saved),
    );
  }

  final bool on;

  /// A preset's id, a saved preset's name, or "" once the bands are moved.
  final String preset;
  final List<double> bands;
  final double preamp;
  final double bass;
  final double treble;

  /// -1 (left only) … 1 (right only).
  final double balance;

  /// Lower the preamp by the curve's highest boost, so loud songs don't clip.
  final bool noclip;

  /// Faster or slower, at the same pitch. Not part of [on].
  final double speed;

  /// Your own presets: {name: [fifteen bands]}.
  final Map<String, List<double>> saved;

  Json toJson() => {
        'on': on,
        'preset': preset,
        'bands': bands,
        'preamp': preamp,
        'bass': bass,
        'treble': treble,
        'balance': balance,
        'noclip': noclip,
        'speed': speed,
        'presets': saved,
      };

  /// These settings with some changed (and put in range).
  Sound copyWith({
    bool? on,
    String? preset,
    List<double>? bands,
    double? preamp,
    double? bass,
    double? treble,
    double? balance,
    bool? noclip,
    double? speed,
    Map<String, List<double>>? saved,
  }) =>
      Sound.fromJson({
        ...toJson(),
        'on': ?on,
        'preset': ?preset,
        'bands': ?bands,
        'preamp': ?preamp,
        'bass': ?bass,
        'treble': ?treble,
        'balance': ?balance,
        'noclip': ?noclip,
        'speed': ?speed,
        'presets': ?saved,
      });

  /// Built-in presets, then yours.
  List<SoundPreset> get presets => [
        ...builtInPresets,
        for (final MapEntry(:key, :value) in saved.entries) SoundPreset(key, key, value, saved: true),
      ];

  /// The preset these bands are ("" for none).
  String get matchingPreset => presets.where((p) => _sameBands(_bandsOf(p.bands), bands)).firstOrNull?.id ?? '';

  /// A built-in preset's id from its id or name (any case), or a saved
  /// preset's name; null if there's none.
  String? findPreset(String name) {
    final wanted = name.trim().toLowerCase();
    for (final p in presets) {
      if (p.saved ? p.id.toLowerCase() == wanted : (p.id == wanted || p.name.toLowerCase() == wanted)) return p.id;
    }
    return null;
  }

  /// Bands moved: the preset follows them.
  Sound withBands(List<double> next) {
    final moved = copyWith(bands: next);
    return moved.copyWith(preset: moved.matchingPreset);
  }

  /// A preset picked: its bands, and the sound on.
  Sound withPreset(String id) {
    final p = presets.where((p) => p.id == id).firstOrNull;
    return p == null ? this : copyWith(on: true, preset: p.id, bands: p.bands);
  }

  /// The bands kept as one of your presets ([name] can't be a built-in's).
  Sound savedAs(String name) {
    final n = name.trim();
    if (n.isEmpty || isBuiltInPreset(n)) throw ArgumentError.value(name, 'name', "can't name a preset that");
    return copyWith(saved: {...saved, n: bands}, preset: n);
  }

  Sound withoutPreset(String name) {
    final next = {...saved}..remove(name);
    return copyWith(saved: next, preset: preset == name ? '' : preset);
  }

  /// Back to flat, keeping on / off and your presets.
  Sound reset() => Sound.fromJson({'on': on, 'presets': saved});

  /// [(filter, gain)] for the bands, bass and treble: the shape of the sound.
  List<(SoundFilter, double)> get curve => [
        for (var i = 0; i < soundBands.length; i++) (soundFilters[i + 1], bandGains(bands)[i]),
        (soundFilters[soundFilters.length - 4], bass),
        (soundFilters[soundFilters.length - 3], treble),
      ];

  /// The curve's highest boost (dB), 0 if it only cuts.
  double get peak {
    final shape = curve.where((g) => g.$2 != 0).toList();
    if (shape.isEmpty) return 0;
    return _grid.fold(0.0, (top, f) => max(top, soundResponse(shape, f)));
  }

  /// {filter name: dB} as the graph gets them.
  Map<String, double> get gains {
    final pre = preamp - (noclip ? peak : 0);
    final b = balance;
    return {
      'pre': tenth(max(-30.0, pre)),
      for (var i = 0; i < bands.length; i++) 'b$i': tenth(bandGains(bands)[i]),
      'bass': bass,
      'treble': treble,
      'left': b > 0 ? tenth(20 * log(max(0.01, 1 - b)) / ln10) : 0.0,
      'right': b < 0 ? tenth(20 * log(max(0.01, 1 + b)) / ln10) : 0.0,
    };
  }

  /// mpv's `af` entry ("" when the sound effects are off).
  String get graph {
    if (!on) return '';
    final levels = gains;
    final filters = [for (final f in soundFilters) 'equalizer@${f.name}=${f.options}:g=${soundFmt(levels[f.name]!)}'];
    return '@$_label:lavfi=[${filters.join(',')}]';
  }

  /// mpv commands moving the filters whose gains differ from [before]'s,
  /// without rebuilding the graph (for a control being dragged).
  List<List<String>> movesFrom(Sound before) {
    final was = before.gains;
    return [
      for (final MapEntry(:key, :value) in gains.entries)
        if (was[key] != value) ['af-command', _label, 'g', soundFmt(value), 'equalizer@$key'],
    ];
  }

  /// The curve on a phone's equaliser with bands at [centres] (Hz) that go
  /// from [low] to [high] dB: each band gets the curve's level there, plus
  /// the preamp when that is a cut. A preamp boost goes to the loudness
  /// enhancer instead. Returns (band gains, loudness gain) in dB.
  (List<double>, double) phone(List<double> centres, double low, double high) {
    if (!on) return ([for (final _ in centres) 0.0], 0.0);
    final pre = gains['pre']!;
    final shape = curve.where((g) => g.$2 != 0).toList();
    return (
      [for (final f in centres) tenth((soundResponse(shape, f) + min(0.0, pre)).clamp(low, high))],
      max(0.0, pre),
    );
  }

  /// One line: "On · Melody · preamp -3.5 dB · bass +2 dB · 1.25×".
  String get summary {
    final name = builtInPresets.where((p) => p.id == preset).firstOrNull?.name ?? (preset.isEmpty ? 'Custom' : preset);
    final parts = [on ? 'On' : 'Off', name];
    for (final (label, value) in [('preamp', preamp), ('bass', bass), ('treble', treble)]) {
      if (value != 0) parts.add('$label ${soundDb(value)} dB');
    }
    if (balance != 0) parts.add('balance ${(balance.abs() * 100).round()}% ${balance > 0 ? 'right' : 'left'}');
    if (speed != 1) parts.add('${speedText(speed)}×');
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) => other is Sound && _key == other._key;

  @override
  int get hashCode => _key.hashCode;

  String get _key => '${toJson()}';
}

/// 1.25 → "1.25", 0.5 → "0.5", 2.0 → "2".
String speedText(double speed) {
  var text = speed.toStringAsFixed(2);
  while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
