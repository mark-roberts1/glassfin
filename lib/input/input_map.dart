/// Raw key codes → semantic action names, driven by `assets/inputmaps/*.json`.
///
/// Ported from `glassfin_old/src/input/InputMapping.cpp` and
/// `src/utils/CachedRegexMatcher.cpp`; see docs/native-audit.md §3. **The JSON
/// files are data and are carried over unchanged** — they are the reason a new
/// remote is a file rather than a code change, and the reason this engine has to
/// reproduce some decisions it would not have made on its own.
///
/// Deliberately free of any Flutter import. Everything here is a pure function
/// of a source name and a key code, which is what makes the behaviour testable
/// without a gamepad plugged in.
library;

import 'dart:convert';

/// What one mapping entry resolves to.
///
/// The JSON has four value forms; these are three types, because a plain string
/// and an array of strings differ only in length.
sealed class Mapped {
  const Mapped();
}

/// Actions to fire as soon as the key goes down, in order.
///
/// The array form is how one key does two things — `"Space": ["space",
/// "play_pause"]` types a space *and* pauses the film, and which of those
/// actually happens depends on whether a text field is open.
final class MappedActions extends Mapped {
  const MappedActions(this.actions);

  final List<String> actions;

  @override
  String toString() => 'MappedActions($actions)';
}

/// One action for a tap, a different one for a hold.
///
/// Resolved on key **up**, because until the key is released there is no way to
/// know which of the two this press was. See `InputPipeline`.
final class MappedHold extends Mapped {
  const MappedHold({this.short, this.long});

  final String? short;
  final String? long;

  @override
  String toString() => 'MappedHold(short: $short, long: $long)';
}

/// An ordered list of anchored patterns with a memoised lookup.
///
/// Every pattern that matches contributes, and **that is the important
/// semantic** rather than an accident: pressing `P` on a keyboard matches both
/// the letter rule and the play/pause rule, and the interface wants both
/// answers so it can use whichever suits its current state.
///
/// [T] is the mapping value. [expand] is how a capture group reaches it —
/// `"KEY_NUMERIC_([0-9])": "%1"` is one rule for ten buttons.
class CachedRegexMatcher<T> {
  CachedRegexMatcher({this.collapseDuplicatePatterns = false, this.expand});

  /// When true, adding a pattern that is already present **replaces** the
  /// earlier entry instead of sitting beside it.
  ///
  /// This is the overlay mechanism for sources: a user map claiming the same
  /// `idmatcher` as a bundled one takes it over rather than doubling up with it.
  final bool collapseDuplicatePatterns;

  /// Applies a regex match's capture groups to the value, or null if the value
  /// cannot carry them.
  final T Function(T value, RegExpMatch match)? expand;

  final List<(RegExp, T)> _entries = [];
  final Map<String, List<T>> _cache = {};

  /// Adds [pattern], anchored. False if it does not compile, which is a bad
  /// mapping file rather than a bad key press.
  bool add(String pattern, T value) {
    final RegExp matcher;
    try {
      matcher = RegExp('^$pattern\$');
    } on FormatException {
      return false;
    }

    if (collapseDuplicatePatterns) {
      _entries.removeWhere((entry) => entry.$1.pattern == matcher.pattern);
    }
    _entries.add((matcher, value));
    _cache.clear();
    return true;
  }

  /// Every value whose pattern matches [input], in the order they were added.
  ///
  /// Misses are cached as well as hits — the original cached only hits, so every
  /// unmapped key walked the whole list again. The entry list never changes
  /// after a load, so there is nothing for a stale negative to be wrong about.
  List<T> match(String input) => _cache.putIfAbsent(input, () {
    final matches = <T>[];
    for (final (matcher, value) in _entries) {
      final match = matcher.firstMatch(input);
      if (match == null) continue;
      matches.add(
        match.groupCount > 0 && expand != null
            ? expand!(value, match)
            : value,
      );
    }
    return List.unmodifiable(matches);
  });

  int get length => _entries.length;
}

/// Substitutes `%1`…`%9` in [value] with [match]'s capture groups.
///
/// Qt's `QString::arg` did this one placeholder at a time; a plain replace is
/// the same thing for these files, none of which contain a literal `%`.
String expandCaptures(String value, RegExpMatch match) {
  if (!value.contains('%')) return value;
  var out = value;
  for (var group = 1; group <= match.groupCount && group <= 9; group++) {
    out = out.replaceAll('%$group', match.group(group) ?? '');
  }
  return out;
}

Mapped _expandMapped(Mapped value, RegExpMatch match) => switch (value) {
  MappedActions(:final actions) => MappedActions([
    for (final action in actions) expandCaptures(action, match),
  ]),
  MappedHold(:final short, :final long) => MappedHold(
    short: short == null ? null : expandCaptures(short, match),
    long: long == null ? null : expandCaptures(long, match),
  ),
};

/// One mapping file.
class InputMapFile {
  InputMapFile({
    required this.id,
    required this.name,
    required this.idMatcher,
    required this.mapping,
  });

  /// **The overlay key, and it is the file name rather than the `name` field.**
  ///
  /// The original keyed its loaded mappings on `name`, and three bundled files
  /// are all called "Xbox Controller" with three different `idmatcher`s and
  /// three *different* axis layouts. Keyed on the name they overwrite each
  /// other, so on Linux an Xbox pad got whichever file the directory happened to
  /// yield last — the Windows layout, whose thumbstick axes are not the Linux
  /// ones. Keyed on the file name all three coexist and the `idmatcher` picks
  /// the right one, which is plainly what the files intend.
  final String id;

  /// Human-readable, for logs. No longer load-bearing — see [id].
  final String name;

  /// Matched against the *source* — a joystick's name as SDL reports it,
  /// `"Keyboard"`, `"CEC"`. Anchored like every other pattern here.
  final String idMatcher;

  final Map<String, Mapped> mapping;

  /// Parses a mapping file's text.
  ///
  /// Returns null for a file with no `idmatcher`, which is how a bundled map is
  /// deliberately disabled rather than an error. Throws [FormatException] for a
  /// file that is actually broken.
  static InputMapFile? parse(String id, String text) {
    final decoded = json.decode(stripLineComments(text));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('not a JSON object');
    }

    // A disabled map, not a broken one.
    final idMatcher = decoded['idmatcher'];
    if (idMatcher == null) return null;
    if (idMatcher is! String) {
      throw const FormatException('"idmatcher" is not a string');
    }

    final name = decoded['name'];
    if (name is! String) throw const FormatException('missing "name"');

    final mapping = decoded['mapping'];
    if (mapping is! Map<String, Object?>) {
      throw const FormatException('missing "mapping"');
    }

    final parsed = <String, Mapped>{};
    for (final entry in mapping.entries) {
      final value = parseMappedValue(entry.value);
      if (value != null) parsed[entry.key] = value;
    }

    return InputMapFile(
      id: id,
      name: name,
      idMatcher: idMatcher,
      mapping: parsed,
    );
  }
}

/// Reads one JSON mapping value, or null when the key is deliberately unbound.
///
/// `"KEY_BUTTON_8": ""` appears in the bundled pads and means "this button does
/// nothing". The original treated it as an action named `""`, which matched no
/// handler but did start the autorepeat timer, so holding an unbound button set
/// a 60ms timer firing an empty action for as long as you held it. Treating it
/// as absent is the same behaviour with none of that.
Mapped? parseMappedValue(Object? value) {
  if (value is String) {
    return value.isEmpty ? null : MappedActions([value]);
  }

  if (value is List) {
    final actions = [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty) entry,
    ];
    return actions.isEmpty ? null : MappedActions(actions);
  }

  if (value is Map<String, Object?>) {
    String? at(String key) {
      final found = value[key];
      return found is String && found.isNotEmpty ? found : null;
    }

    final short = at('short');
    final long = at('long');
    return short == null && long == null
        ? null
        : MappedHold(short: short, long: long);
  }

  return null;
}

/// Drops whole-line `//` comments, which is all the original ever supported.
///
/// Narrow on purpose: a `//` that is not the first thing on its line is left
/// alone, so a pattern containing one survives. The bundled files were written
/// against exactly this rule.
String stripLineComments(String text) => text
    .split('\n')
    .where((line) => !RegExp(r'^\s*//').hasMatch(line))
    .join('\n');

/// The loaded set of mapping files, and the lookup across all of them.
class InputMaps {
  InputMaps(Iterable<InputMapFile> files) {
    for (final file in files) {
      add(file);
    }
  }

  /// Source name → file id. Duplicate `idmatcher` patterns collapse, so a later
  /// file claiming the same one wins outright instead of both contributing.
  final _sources = CachedRegexMatcher<String>(collapseDuplicatePatterns: true);

  final Map<String, CachedRegexMatcher<Mapped>> _byFile = {};

  /// Adds or replaces a file. Later wins, which is what makes a user map
  /// override a bundled one of the same name.
  void add(InputMapFile file) {
    if (!_sources.add(file.idMatcher, file.id)) return;

    final matcher = CachedRegexMatcher<Mapped>(expand: _expandMapped);
    for (final entry in file.mapping.entries) {
      matcher.add(entry.key, entry.value);
    }
    _byFile[file.id] = matcher;
  }

  /// Every mapping that [source] and [keycode] together select.
  ///
  /// `"direct"` is the escape hatch the old local socket used: the key code *is*
  /// the action, with no mapping file in the way. Kept because it is how an
  /// external process — the CEC bridge, eventually — injects a semantic action
  /// without having to own a map.
  List<Mapped> lookUp(String source, String keycode) {
    if (source == 'direct') return [MappedActions([keycode])];

    final results = <Mapped>[];
    for (final id in _sources.match(source)) {
      final matcher = _byFile[id];
      if (matcher != null) results.addAll(matcher.match(keycode));
    }
    return results;
  }

  /// The file ids [source] resolves to, for diagnostics — "which map am I
  /// actually using for this pad" is the first question when a button does
  /// nothing.
  List<String> filesFor(String source) => _sources.match(source);

  int get length => _byFile.length;
}
