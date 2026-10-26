/// 두벌식 한글 조합기. 자모가 아닌 글자는 조합 중인 글자를 확정하고 그대로 붙인다.
class HangulComposer {
  final _done = StringBuffer();
  String? _cho, _jung, _jong; // 호환 자모

  static const _choList = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  static const _jungList = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
  static const _jongList = [
    '', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ',
    'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  ];
  static const _jungPairs = {
    'ㅗㅏ': 'ㅘ', 'ㅗㅐ': 'ㅙ', 'ㅗㅣ': 'ㅚ', 'ㅜㅓ': 'ㅝ', 'ㅜㅔ': 'ㅞ', 'ㅜㅣ': 'ㅟ', 'ㅡㅣ': 'ㅢ',
  };
  static const _jongPairs = {
    'ㄱㅅ': 'ㄳ', 'ㄴㅈ': 'ㄵ', 'ㄴㅎ': 'ㄶ', 'ㄹㄱ': 'ㄺ', 'ㄹㅁ': 'ㄻ', 'ㄹㅂ': 'ㄼ',
    'ㄹㅅ': 'ㄽ', 'ㄹㅌ': 'ㄾ', 'ㄹㅍ': 'ㄿ', 'ㄹㅎ': 'ㅀ', 'ㅂㅅ': 'ㅄ',
  };

  String get text => '$_done${_composing()}';

  void type(String ch) {
    if (_choList.contains(ch)) {
      _consonant(ch);
    } else if (_jungList.contains(ch)) {
      _vowel(ch);
    } else {
      _commit();
      _done.write(ch);
    }
  }

  void backspace() {
    if (_jong != null) {
      _jong = _unpair(_jongPairs, _jong!)?[0]; // ㄺ → ㄹ, ㄹ → 없음
    } else if (_jung != null) {
      _jung = _unpair(_jungPairs, _jung!)?[0]; // ㅘ → ㅗ, ㅗ → 없음
    } else if (_cho != null) {
      _cho = null;
    } else if (_done.isNotEmpty) {
      final s = _done.toString();
      _done
        ..clear()
        ..write(s.substring(0, s.length - 1));
    }
  }

  void _consonant(String c) {
    if (_cho == null && _jung == null) {
      _cho = c;
    } else if (_cho == null || _jung == null) {
      _commit();
      _cho = c;
    } else if (_jong == null) {
      if (_jongList.contains(c)) {
        _jong = c;
      } else {
        _commit(); // ㄸ ㅃ ㅉ 은 받침이 못 된다
        _cho = c;
      }
    } else if (_jongPairs.containsKey('$_jong$c')) {
      _jong = _jongPairs['$_jong$c'];
    } else {
      _commit();
      _cho = c;
    }
  }

  void _vowel(String v) {
    if (_jung == null) {
      _jung = v;
    } else if (_jong == null) {
      final pair = _jungPairs['$_jung$v'];
      if (pair != null) {
        _jung = pair;
      } else {
        _commit();
        _jung = v;
      }
    } else {
      // 받침이 다음 글자 초성으로 넘어간다: 닭 + ㅏ → 달가
      final split = _unpair(_jongPairs, _jong!);
      final next = split?[1] ?? _jong!;
      _jong = split?[0];
      _commit();
      _cho = next;
      _jung = v;
    }
  }

  void _commit() {
    _done.write(_composing());
    _cho = _jung = _jong = null;
  }

  String _composing() {
    if (_cho == null || _jung == null) return (_cho ?? '') + (_jung ?? '');
    final code = 0xAC00 +
        (_choList.indexOf(_cho!) * 21 + _jungList.indexOf(_jung!)) * 28 +
        _jongList.indexOf(_jong ?? '');
    return String.fromCharCode(code);
  }

  static String? _unpair(Map<String, String> pairs, String joined) {
    for (final e in pairs.entries) {
      if (e.value == joined) return e.key;
    }
    return null;
  }
}
