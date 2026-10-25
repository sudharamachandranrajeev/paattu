// The words of a song in English letters, the way people type Malayalam,
// Tamil, Hindi, Telugu and Kannada film songs (thelimaanam, kaadhal, pyaar),
// not a scholar's transliteration with marks over the letters.
//
// The five scripts are laid out alike in Unicode (each letter sits at the same
// place in its block), so one table of sounds serves them all, and each
// script changes what it says differently: Malayalam's chillu letters and its
// final "u" (paattu); Tamil's k, ch, t and p sounding g, s, d/dh and b between
// vowels and after n or m (kaadhal, anbe, nenjam); Hindi leaving out the "a"
// no one says (dil, dhadkan, karna).
//
// paattu/transliterate.py does the same (tests/transliterate_cases.json).

const scriptBlocks = {'devanagari': 0x0900, 'tamil': 0x0B80, 'telugu': 0x0C00, 'kannada': 0x0C80, 'malayalam': 0x0D00};
const scriptLanguages = {
  'devanagari': 'Hindi',
  'tamil': 'Tamil',
  'telugu': 'Telugu',
  'kannada': 'Kannada',
  'malayalam': 'Malayalam',
};

// By the letter's place in its block.
const _vowels = {
  0x05: 'a', 0x06: 'aa', 0x07: 'i', 0x08: 'ee', 0x09: 'u', 0x0A: 'oo', 0x0B: 'ru', 0x0C: 'lu', 0x0D: 'e', //
  0x0E: 'e', 0x0F: 'e', 0x10: 'ai', 0x11: 'o', 0x12: 'o', 0x13: 'o', 0x14: 'au', 0x60: 'roo', 0x61: 'loo',
};
const _signs = {
  0x3E: 'aa', 0x3F: 'i', 0x40: 'ee', 0x41: 'u', 0x42: 'oo', 0x43: 'ru', 0x44: 'roo', 0x45: 'e', 0x46: 'e', //
  0x47: 'e', 0x48: 'ai', 0x49: 'o', 0x4A: 'o', 0x4B: 'o', 0x4C: 'au', 0x57: 'au', 0x62: 'lu', 0x63: 'loo',
};
const _consonants = {
  0x15: 'k', 0x16: 'kh', 0x17: 'g', 0x18: 'gh', 0x19: 'ng', 0x1A: 'ch', 0x1B: 'chh', 0x1C: 'j', //
  0x1D: 'jh', 0x1E: 'nj', 0x1F: 't', 0x20: 'th', 0x21: 'd', 0x22: 'dh', 0x23: 'n', 0x24: 'th',
  0x25: 'th', 0x26: 'd', 0x27: 'dh', 0x28: 'n', 0x29: 'n', 0x2A: 'p', 0x2B: 'ph', 0x2C: 'b', 0x2D: 'bh',
  0x2E: 'm', 0x2F: 'y', 0x30: 'r', 0x31: 'r', 0x32: 'l', 0x33: 'l', 0x34: 'zh', 0x35: 'v', 0x36: 'sh',
  0x37: 'sh', 0x38: 's', 0x39: 'h',
};
// What each script says differently.
const _ownConsonants = {
  'devanagari': {
    0x24: 't', 0x1E: 'n', 0x58: 'q', 0x59: 'kh', 0x5A: 'gh', 0x5B: 'z', 0x5C: 'd', 0x5D: 'dh', 0x5E: 'f', //
    0x5F: 'y',
  },
  'kannada': {0x5E: 'zh'},
  'malayalam': {0x2B: 'ph'},
};
const _ownVowels = {
  'devanagari': {0x0B: 'ri'},
};
const _ownSigns = {
  'devanagari': {0x43: 'ri'},
};
const _nukta = {'k': 'q', 'j': 'z', 'ph': 'f', 'g': 'gh'};
// Malayalam's chillu letters, a consonant with no vowel that ends a syllable.
const _chillu = {
  0x0D7A: 0x23, 0x0D7B: 0x28, 0x0D7C: 0x30, 0x0D7D: 0x32, 0x0D7E: 0x33, 0x0D7F: 0x15, 0x0D54: 0x2E, //
  0x0D55: 0x2F, 0x0D56: 0x34,
};
const _virama = 0x4D, _nuktaSign = 0x3C, _anusvara = 0x02, _visarga = 0x03, _candrabindu = 0x01;
const _zwj = 0x200D, _zwnj = 0x200C;
const _nasals = {0x19, 0x1E, 0x23, 0x28, 0x29, 0x2E};
const _labials = {0x2A, 0x2B, 0x2C, 0x2D, 0x2E};
// Tamil's stops: how each sounds at the start or doubled, after n or m, and between vowels.
const _tamilStops = {
  0x15: ('k', 'g', 'g'),
  0x1A: ('ch', 'j', 's'),
  0x1F: ('t', 'd', 'd'),
  0x24: ('th', 'dh', 'dh'),
  0x2A: ('p', 'b', 'b'),
};
const _digraphs = {'ch', 'chh', 'th', 'dh', 'sh', 'kh', 'gh', 'ph', 'bh', 'jh'};

final _asciiLetter = RegExp('[A-Za-z]');

/// Which of the five scripts [text] is in (most of its letters), or null
/// when more of them are English.
String? scriptOf(String? text) {
  final counts = <String, int>{};
  var latin = 0;
  for (final code in (text ?? '').runes) {
    if (code < 0x80) {
      if (_asciiLetter.hasMatch(String.fromCharCode(code))) latin++;
      continue;
    }
    for (final MapEntry(:key, :value) in scriptBlocks.entries) {
      if (code >= value && code < value + 0x80) {
        counts[key] = (counts[key] ?? 0) + 1;
        break;
      }
    }
  }
  if (counts.isEmpty) return null;
  String? name;
  for (final MapEntry(:key, :value) in counts.entries) {
    if (name == null || value > counts[name]!) name = key;
  }
  return counts[name]! > latin ? name : null;
}

enum _Kind { consonant, vowel, mark, other }

class _Token {
  _Token.consonant(this.place, this.sound, {this.vowel, this.chillu = false})
      : kind = _Kind.consonant,
        text = '';
  _Token.vowel(this.sound)
      : kind = _Kind.vowel,
        place = -1,
        text = '';
  _Token.mark(this.place)
      : kind = _Kind.mark,
        sound = '',
        text = '';
  _Token.other(this.text)
      : kind = _Kind.other,
        place = -1,
        sound = '';

  final _Kind kind;
  final int place;
  final String text;
  String sound;

  /// The vowel a consonant carries: null for the one it's born with, '' for none.
  String? vowel;
  bool chillu = false;

  bool get carries => kind == _Kind.vowel || (kind == _Kind.consonant && vowel != '');
  bool get bare => kind == _Kind.consonant && vowel == '';
}

List<_Token> _tokens(String word, String script) {
  final start = scriptBlocks[script]!;
  final consonants = {..._consonants, ...?_ownConsonants[script]};
  final vowels = {..._vowels, ...?_ownVowels[script]};
  final signs = {..._signs, ...?_ownSigns[script]};
  final out = <_Token>[];
  for (final code in word.runes) {
    if (script == 'malayalam' && _chillu.containsKey(code)) {
      final place = _chillu[code]!;
      out.add(_Token.consonant(place, consonants[place]!, vowel: '', chillu: true));
      continue;
    }
    final place = code - start;
    final last = out.isEmpty ? null : out.last;
    final lastConsonant = last != null && last.kind == _Kind.consonant;
    if (code == _zwj && last != null && last.bare) {
      last.chillu = true;
    } else if (code == _zwj || code == _zwnj) {
      continue;
    } else if (place < 0 || place >= 0x80) {
      out.add(_Token.other(String.fromCharCode(code)));
    } else if (consonants.containsKey(place)) {
      out.add(_Token.consonant(place, consonants[place]!));
    } else if (vowels.containsKey(place)) {
      out.add(_Token.vowel(vowels[place]!));
    } else if (place == _nuktaSign && lastConsonant) {
      last.sound = _nukta[last.sound] ?? last.sound;
    } else if (place == _virama && lastConsonant) {
      last.vowel = '';
    } else if ((place == 0x55 || place == 0x56 || place == 0x57) && lastConsonant && (last.vowel ?? '') != '') {
      // Length marks after a vowel sign: ೀ ೕ (longer), ై (ai), ൌ ௌ (au).
      last.vowel = switch (place) { 0x55 => last.vowel == 'i' ? 'ee' : last.vowel, 0x56 => 'ai', _ => 'au' };
    } else if (signs.containsKey(place) && lastConsonant) {
      if (last.vowel == 'e' && (place == 0x3E || place == 0x42)) {
        last.vowel = 'o'; // െ + ാ written apart: ൊ
      } else if ((last.vowel ?? '') == '') {
        last.vowel = signs[place];
      }
    } else if (signs.containsKey(place) && last != null && last.kind == _Kind.vowel && place == 0x57) {
      last.sound = 'au';
    } else if (place == _anusvara || place == _visarga || place == _candrabindu) {
      out.add(_Token.mark(place));
    } else if (place == 0x4E && script == 'malayalam') {
      // The dot reph: ർ written over what follows.
      out.add(_Token.consonant(0x30, 'r', vowel: '', chillu: true));
    } else if (place >= 0x66 && place <= 0x6F) {
      out.add(_Token.other('${place - 0x66}'));
    } else if (place == 0x64 || place == 0x65) {
      out.add(_Token.other('.')); // । ॥
    }
  }
  return out;
}

/// Hindi leaves out the "a" at a word's end and between two syllables that
/// carry their vowels (Ohala's rule, read from the end: dhadkan).
void _dropSchwa(List<_Token> tokens) {
  final letters = [for (var i = 0; i < tokens.length; i++) if (tokens[i].kind != _Kind.other) i];
  if (letters.isEmpty) return;
  final last = letters.last;
  final end = tokens[last];
  if (end.kind == _Kind.consonant && end.vowel == null && letters.length > 1) {
    if (!tokens[letters[letters.length - 2]].bare) end.vowel = ''; // mitra keeps its a
  }
  for (var i = last - 1; i > 0; i--) {
    final t = tokens[i];
    if (t.kind != _Kind.consonant || t.vowel != null) continue;
    final before = tokens[i - 1], after = tokens[i + 1];
    if (before.carries && after.kind == _Kind.consonant && after.vowel != '') t.vowel = '';
  }
}

String _word(String word, String script) {
  final tokens = _tokens(word, script);
  if (script == 'devanagari') _dropSchwa(tokens);
  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final before = i > 0 ? tokens[i - 1] : null;
    final after = i + 1 < tokens.length ? tokens[i + 1] : null;
    switch (t.kind) {
      case _Kind.other:
        out.write(t.text);
      case _Kind.vowel:
        out.write(t.sound);
      case _Kind.mark:
        if (t.place == _visarga) {
          out.write('h');
        } else if (after != null && after.kind == _Kind.consonant) {
          out.write(_labials.contains(after.place) ? 'm' : 'n');
        } else {
          out.write(script == 'devanagari' || t.place == _candrabindu ? 'n' : 'm');
        }
      case _Kind.consonant:
        out
          ..write(_consonant(t, before, after, script))
          ..write(_vowel(t, after, script));
    }
  }
  return out.toString();
}

String _consonant(_Token t, _Token? before, _Token? after, String script) {
  var sound = t.sound;
  final place = t.place;
  final joined = t.vowel == '' && after != null && after.kind == _Kind.consonant; // the first of a cluster
  final afterCluster = before != null && before.bare;
  if (place == 0x1B && afterCluster && before.place == 0x1A) return 'ch'; // അച്ഛൻ acchan
  if (script == 'malayalam' && afterCluster) {
    if (before.place == 0x23 && place == 0x1F) return 'd'; // ണ്ട nd (kondu)
    if (before.place == 0x2E && place == 0x2A) return 'b'; // മ്പ mb (ambili)
  }
  if (script == 'malayalam' && place == 0x31) {
    if (afterCluster && (before.place == 0x28 || before.place == 0x31)) return 't'; // ന്റ nt, റ്റ tt
    if (joined && after.place == 0x31) return 't';
  }
  if (script == 'tamil') {
    if (place == 0x31 && afterCluster && (before.place == 0x29 || before.place == 0x28)) return 'dr'; // ன்ற endru
    if (place == 0x31 && joined && after.place == 0x31) return 't'; // ற்ற kaatru
    final stop = _tamilStops[place];
    if (stop != null) {
      final (plain, nasal, between) = stop;
      if (joined || (afterCluster && before.place == place)) {
        sound = plain;
      } else if (afterCluster && _nasals.contains(before.place)) {
        sound = nasal;
      } else if (before != null && before.carries) {
        sound = between;
      } else if ((before == null || before.kind == _Kind.other) && place == 0x1A) {
        sound = 's';
      } else {
        sound = plain;
      }
    }
  }
  if (joined) {
    if (place == 0x19 && after.place >= 0x15 && after.place <= 0x18) return 'n'; // ങ്ക nk, ங்க ng
    if (place == 0x1E && after.place >= 0x1A && after.place <= 0x1D) return 'n'; // ഞ്ച nch, ஞ்ச nj
    if (after.place == place && (sound == 'ng' || sound == 'nj' || sound == 'zh')) return ''; // ങ്ങ ng, ഞ്ഞ nj
    if ((after.place == place || (place == 0x1A && after.place == 0x1B)) && _digraphs.contains(sound)) {
      return sound[0]; // ച്ച cch, ത്ത tth
    }
  }
  return sound;
}

String _vowel(_Token t, _Token? after, String script) {
  final vowel = t.vowel;
  if (vowel == null) return 'a';
  if (vowel.isEmpty) {
    final wordEnd = after == null || after.kind == _Kind.other;
    return script == 'malayalam' && wordEnd && !t.chillu ? 'u' : ''; // പാട്ട് paattu
  }
  return vowel;
}

/// Hindi spelt the way people type it: mera, zindagi, not meraa, zindagee.
String _hindiEnding(String word) {
  if (word.endsWith('aa') && word.length > 2) return word.substring(0, word.length - 1);
  for (final (end, said) in const [('ee', 'i'), ('een', 'in')]) {
    if (word.endsWith(end) && word.length > end.length) return word.substring(0, word.length - end.length) + said;
  }
  return word;
}

/// [text] in English letters ('' when it's already in them).
String transliterate(String text, [String? script]) {
  script ??= scriptOf(text);
  if (script == null) return '';
  final words = [
    for (final word in text.split(' '))
      if (script == 'devanagari') _hindiEnding(_word(word, script)) else _word(word, script),
  ];
  final line = words.join(' ');
  return line.isEmpty ? line : line[0].toUpperCase() + line.substring(1);
}
