"""The words of a song in English letters, the way people type Malayalam,
Tamil, Hindi, Telugu and Kannada film songs (thelimaanam, kaadhal, pyaar),
not a scholar's transliteration with marks over the letters.

The five scripts are laid out alike in Unicode (each letter sits at the same
place in its block), so one table of sounds serves them all, and each script
changes what it says differently: Malayalam's chillu letters and its final
"u" (paattu); Tamil's k, ch, t and p sounding g, s, d/dh and b between vowels
and after n or m (kaadhal, anbe, nenjam); Hindi leaving out the "a" no one
says (dil, dhadkan, karna).

The app's transliterate.dart does the same (tests/transliterate_cases.json).
"""

BLOCKS = {"devanagari": 0x0900, "tamil": 0x0B80, "telugu": 0x0C00, "kannada": 0x0C80, "malayalam": 0x0D00}
LANGUAGES = {"devanagari": "Hindi", "tamil": "Tamil", "telugu": "Telugu", "kannada": "Kannada",
             "malayalam": "Malayalam"}

# By the letter's place in its block.
VOWELS = {0x05: "a", 0x06: "aa", 0x07: "i", 0x08: "ee", 0x09: "u", 0x0A: "oo", 0x0B: "ru", 0x0C: "lu", 0x0D: "e",
          0x0E: "e", 0x0F: "e", 0x10: "ai", 0x11: "o", 0x12: "o", 0x13: "o", 0x14: "au", 0x60: "roo", 0x61: "loo"}
SIGNS = {0x3E: "aa", 0x3F: "i", 0x40: "ee", 0x41: "u", 0x42: "oo", 0x43: "ru", 0x44: "roo", 0x45: "e", 0x46: "e",
         0x47: "e", 0x48: "ai", 0x49: "o", 0x4A: "o", 0x4B: "o", 0x4C: "au", 0x57: "au", 0x62: "lu", 0x63: "loo"}
CONSONANTS = {0x15: "k", 0x16: "kh", 0x17: "g", 0x18: "gh", 0x19: "ng", 0x1A: "ch", 0x1B: "chh", 0x1C: "j",
              0x1D: "jh", 0x1E: "nj", 0x1F: "t", 0x20: "th", 0x21: "d", 0x22: "dh", 0x23: "n", 0x24: "th",
              0x25: "th", 0x26: "d", 0x27: "dh", 0x28: "n", 0x29: "n", 0x2A: "p", 0x2B: "ph", 0x2C: "b", 0x2D: "bh",
              0x2E: "m", 0x2F: "y", 0x30: "r", 0x31: "r", 0x32: "l", 0x33: "l", 0x34: "zh", 0x35: "v", 0x36: "sh",
              0x37: "sh", 0x38: "s", 0x39: "h"}
# What each script says differently.
OWN = {
    "devanagari": {"consonants": {0x24: "t", 0x1E: "n", 0x58: "q", 0x59: "kh", 0x5A: "gh", 0x5B: "z", 0x5C: "d",
                                  0x5D: "dh", 0x5E: "f", 0x5F: "y"},
                   "vowels": {0x0B: "ri"}, "signs": {0x43: "ri"}},
    "kannada": {"consonants": {0x5E: "zh"}},
    "malayalam": {"consonants": {0x2B: "ph"}},
}
NUKTA = {"k": "q", "j": "z", "ph": "f", "g": "gh"}
# Malayalam's chillu letters, a consonant with no vowel that ends a syllable.
CHILLU = {0x0D7A: 0x23, 0x0D7B: 0x28, 0x0D7C: 0x30, 0x0D7D: 0x32, 0x0D7E: 0x33, 0x0D7F: 0x15, 0x0D54: 0x2E,
          0x0D55: 0x2F, 0x0D56: 0x34}
VIRAMA, NUKTA_SIGN, ANUSVARA, VISARGA, CANDRABINDU = 0x4D, 0x3C, 0x02, 0x03, 0x01
ZWJ, ZWNJ = "‍", "‌"
NASALS = {0x19, 0x1E, 0x23, 0x28, 0x29, 0x2E}
LABIALS = {0x2A, 0x2B, 0x2C, 0x2D, 0x2E}
# Tamil's stops: how each sounds at the start or doubled, after n or m, and between vowels.
TAMIL_STOPS = {0x15: ("k", "g", "g"), 0x1A: ("ch", "j", "s"), 0x1F: ("t", "d", "d"), 0x24: ("th", "dh", "dh"),
               0x2A: ("p", "b", "b")}
DIGRAPHS = {"ch", "chh", "th", "dh", "sh", "kh", "gh", "ph", "bh", "jh"}


def script_of(text):
    """Which of the five scripts text is in (most of its letters), or None
    when more of them are English."""
    counts = {}
    latin = 0
    for ch in text or "":
        code = ord(ch)
        if ch.isascii():
            latin += ch.isalpha()
            continue
        for name, start in BLOCKS.items():
            if start <= code < start + 0x80:
                counts[name] = counts.get(name, 0) + 1
                break
    if not counts:
        return None
    name = max(counts, key=counts.get)
    return name if counts[name] > latin else None


def _tokens(word, script):
    """A word as consonants (with the vowel each carries: None for the one
    they're born with, "" for none), vowels and marks."""
    start = BLOCKS[script]
    own = OWN.get(script, {})
    consonants = {**CONSONANTS, **own.get("consonants", {})}
    vowels = {**VOWELS, **own.get("vowels", {})}
    signs = {**SIGNS, **own.get("signs", {})}
    out = []
    for ch in word:
        code = ord(ch)
        if code in CHILLU and script == "malayalam":
            place = CHILLU[code]
            out.append({"kind": "C", "place": place, "sound": consonants[place], "vowel": "", "chillu": True})
            continue
        place = code - start
        last = out[-1] if out else None
        if ch == ZWJ and last and last["kind"] == "C" and last["vowel"] == "":
            last["chillu"] = True
        elif ch in (ZWJ, ZWNJ):
            continue
        elif not 0 <= place < 0x80:
            out.append({"kind": "X", "text": ch})
        elif place in consonants:
            out.append({"kind": "C", "place": place, "sound": consonants[place], "vowel": None, "chillu": False})
        elif place in vowels:
            out.append({"kind": "V", "sound": vowels[place]})
        elif place == NUKTA_SIGN and last and last["kind"] == "C":
            last["sound"] = NUKTA.get(last["sound"], last["sound"])
        elif place == VIRAMA and last and last["kind"] == "C":
            last["vowel"] = ""
        elif place in (0x55, 0x56, 0x57) and last and last["kind"] == "C" and last["vowel"]:
            # Length marks after a vowel sign: ೀ ೕ (longer), ై (ai), ൌ ௌ (au).
            last["vowel"] = {0x55: {"i": "ee"}.get(last["vowel"], last["vowel"]), 0x56: "ai", 0x57: "au"}[place]
        elif place in signs and last and last["kind"] == "C":
            if last["vowel"] in ("e",) and place in (0x3E, 0x42):  # െ + ാ written apart: ൊ
                last["vowel"] = "o"
            elif not last["vowel"]:
                last["vowel"] = signs[place]
        elif place in signs and last and last["kind"] == "V" and place == 0x57:
            last["sound"] = "au"
        elif place in (ANUSVARA, VISARGA, CANDRABINDU):
            out.append({"kind": "M", "place": place})
        elif place == 0x4E and script == "malayalam":  # the dot reph: ർ written over what follows
            out.append({"kind": "C", "place": 0x30, "sound": "r", "vowel": "", "chillu": True})
        elif 0x66 <= place <= 0x6F:
            out.append({"kind": "X", "text": str(place - 0x66)})
        elif place in (0x64, 0x65):  # । ॥
            out.append({"kind": "X", "text": "."})
    return out


def _carries(token):
    return token["kind"] == "V" or (token["kind"] == "C" and token["vowel"] != "")


def _drop_schwa(tokens):
    """Hindi leaves out the "a" at a word's end and between two syllables
    that carry their vowels (Ohala's rule, read from the end: dhadkan)."""
    letters = [i for i, t in enumerate(tokens) if t["kind"] != "X"]
    if not letters:
        return
    last = letters[-1]
    end = tokens[last]
    if end["kind"] == "C" and end["vowel"] is None and len(letters) > 1:
        before = tokens[letters[-2]]
        if not (before["kind"] == "C" and before["vowel"] == ""):  # mitra keeps its a
            end["vowel"] = ""
    for i in range(last - 1, 0, -1):
        t = tokens[i]
        if t["kind"] != "C" or t["vowel"] is not None:
            continue
        before, after = tokens[i - 1], tokens[i + 1]
        if _carries(before) and after["kind"] == "C" and after["vowel"] != "":
            t["vowel"] = ""


def _word(word, script):
    tokens = _tokens(word, script)
    if script == "devanagari":
        _drop_schwa(tokens)
    out = []
    n = len(tokens)
    for i, t in enumerate(tokens):
        before = tokens[i - 1] if i else None
        after = tokens[i + 1] if i + 1 < n else None
        if t["kind"] == "X":
            out.append(t["text"])
            continue
        if t["kind"] == "V":
            out.append(t["sound"])
            continue
        if t["kind"] == "M":
            if t["place"] == VISARGA:
                out.append("h")
            elif after and after["kind"] == "C":
                out.append("m" if after["place"] in LABIALS else "n")
            else:
                out.append("n" if script == "devanagari" or t["place"] == CANDRABINDU else "m")
            continue
        out.append(_consonant(t, before, after, script) + _vowel(t, after, script))
    return "".join(out)


def _consonant(t, before, after, script):
    sound, place = t["sound"], t["place"]
    joined = t["vowel"] == "" and after and after["kind"] == "C"  # the first of a cluster
    after_cluster = before and before["kind"] == "C" and before["vowel"] == ""
    if place == 0x1B and after_cluster and before["place"] == 0x1A:  # അച്ഛൻ acchan
        return "ch"
    if script == "malayalam" and after_cluster and (before["place"], place) in ((0x23, 0x1F), (0x2E, 0x2A)):
        return "d" if place == 0x1F else "b"  # ണ്ട nd (kondu), മ്പ mb (ambili)
    if script == "malayalam" and place == 0x31:
        if after_cluster and before["place"] in (0x28, 0x31):  # ന്റ nt, റ്റ tt
            return "t"
        if joined and after["place"] == 0x31:
            return "t"
    if script == "tamil":
        if place == 0x31 and after_cluster and before["place"] in (0x29, 0x28):  # ன்ற endru
            return "dr"
        if place == 0x31 and joined and after["place"] == 0x31:  # ற்ற kaatru
            return "t"
        if place in TAMIL_STOPS:
            plain, nasal, between = TAMIL_STOPS[place]
            if joined or (after_cluster and before["place"] == place):
                sound = plain
            elif after_cluster and before["place"] in NASALS:
                sound = nasal
            elif before and _carries(before):
                sound = between
            elif (not before or before["kind"] == "X") and place == 0x1A:
                sound = "s"
            else:
                sound = plain
    if joined:
        if place == 0x19 and 0x15 <= after["place"] <= 0x18:  # ങ്ക nk, ங்க ng
            return "n"
        if place == 0x1E and 0x1A <= after["place"] <= 0x1D:  # ഞ്ച nch, ஞ்ச nj
            return "n"
        if after["place"] == place and sound in ("ng", "nj", "zh"):  # ങ്ങ ng, ഞ്ഞ nj
            return ""
        if (after["place"] == place or (place == 0x1A and after["place"] == 0x1B)) and sound in DIGRAPHS:
            return sound[0]  # ച്ച cch, ത്ത tth
    return sound


def _vowel(t, after, script):
    vowel = t["vowel"]
    if vowel is None:
        return "a"
    if vowel == "":
        word_end = after is None or after["kind"] == "X"
        if script == "malayalam" and word_end and not t["chillu"]:
            return "u"  # പാട്ട് paattu
        return ""
    return vowel


def _hindi_ending(word):
    """Hindi spelt the way people type it: mera, zindagi, not meraa, zindagee."""
    if word.endswith("aa") and len(word) > 2:
        return word[:-1]
    for end, said in (("ee", "i"), ("een", "in")):
        if word.endswith(end) and len(word) > len(end):
            return word[: -len(end)] + said
    return word


def transliterate(text, script=None):
    """text in English letters ("" when it's already in them)."""
    script = script or script_of(text)
    if not script:
        return ""
    words = []
    for word in text.split(" "):
        latin = _word(word, script)
        words.append(_hindi_ending(latin) if script == "devanagari" else latin)
    line = " ".join(words)
    return line[:1].upper() + line[1:]


def language_of(text):
    script = script_of(text)
    return LANGUAGES.get(script, "") if script else ""
