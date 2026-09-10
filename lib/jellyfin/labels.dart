/// The strings an [Item] is presented as.
///
/// Pure, and separate from the widgets that show them: what a card is captioned
/// with turned out to be one of the more error-prone decisions in the old
/// project (see [itemCaption]), and it is far cheaper to test as a function than
/// to spot on a television.
library;

import 'models.dart';

/// A card's or the transport's title: the **series** name for an episode.
///
/// An episode's own name belongs in the caption. On a shelf of Continue
/// Watching, "The Expanse" scanned at a distance is what the viewer is looking
/// for; "Leviathan Wakes" is not.
String itemTitle(Item item) =>
    item.type == ItemKind.episode ? (item.seriesName ?? item.name) : item.name;

/// `S2:E4`, or an empty string when either index is missing.
String episodeCode(Item item) {
  final season = item.parentIndexNumber;
  final episode = item.indexNumber;
  if (season == null || episode == null) return '';
  return 'S$season:E$episode';
}

/// The second line under a card.
///
/// **A series is captioned by its years, never by a season count.** `ChildCount`
/// looks like the number of seasons and sometimes is, but it is whatever the
/// endpoint felt like counting: on `/Items/Latest`, which groups new episodes
/// under their series, it is the number of recently added episodes — so a show
/// with one new episode read "1 season". Years are already here and are always
/// true.
String itemCaption(Item item) {
  if (item.type == ItemKind.episode) {
    final code = episodeCode(item);
    return [
      if (code.isNotEmpty) code,
      item.name,
    ].join(' · ');
  }

  final year = item.productionYear;
  if (year == null) return '';
  if (item.type != ItemKind.series) return '$year';

  if (item.status == 'Continuing') return '$year–present';
  final ended = _yearOf(item.endDate);
  return ended != null && ended != year ? '$year–$ended' : '$year';
}

/// The episode line under the transport's title, e.g. `S2:E4 · Leviathan Wakes`.
String episodeSubtitle(Item item) {
  if (item.type != ItemKind.episode) return '';
  final code = episodeCode(item);
  return [if (code.isNotEmpty) code, item.name].join(' · ');
}

int? _yearOf(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.year;
}
