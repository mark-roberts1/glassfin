/// The language list offered in Settings.
///
/// **Deliberately short.** Every ISO 639-2 code is unusable on a D-pad — a
/// cycling row would need hundreds of presses — and this covers what a home
/// library actually holds. Codes are three-letter ISO 639-2, matching
/// `MediaStream.Language`; the empty code means "whatever the server ordered".
library;

import 'package:flutter/foundation.dart';

@immutable
class Language {
  const Language(this.code, this.name);

  final String code;
  final String name;
}

const List<Language> languages = [
  Language('', 'Server default'),
  Language('eng', 'English'),
  Language('spa', 'Spanish'),
  Language('fra', 'French'),
  Language('deu', 'German'),
  Language('ita', 'Italian'),
  Language('por', 'Portuguese'),
  Language('nld', 'Dutch'),
  Language('swe', 'Swedish'),
  Language('pol', 'Polish'),
  Language('rus', 'Russian'),
  Language('jpn', 'Japanese'),
  Language('kor', 'Korean'),
  Language('zho', 'Chinese'),
];

/// The display name for a code, falling back to the code itself.
///
/// A track in a language not on the list is still worth labelling — the track
/// menu shows "hun" rather than "Unknown", which at least tells the viewer the
/// file has an opinion.
String languageName(String code) {
  for (final language in languages) {
    if (language.code == code) return language.name;
  }
  return code;
}
