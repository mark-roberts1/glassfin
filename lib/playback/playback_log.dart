/// The `glassfin: playback` diagnostic line.
///
/// Stutter has several unrelated causes — software rendering, dropped frames at
/// output, a decoder that cannot keep up, a server transcode — and from the sofa
/// they all look the same. This line tells them apart. It is how the BC-250's
/// Game Mode stutter was found and how its fix was confirmed, so it is written
/// for someone reading a journal after the fact: every line names what was
/// playing and how far in it was taken.
///
/// Pure, so the format can be tested without libmpv; the controller supplies
/// the property values.
library;

import '../format.dart';
import '../jellyfin/labels.dart';
import '../jellyfin/models.dart';

/// When a line was taken.
enum PlaybackLogPoint {
  /// A few seconds in: which render and decode path mpv actually chose.
  started('start'),

  /// Periodically during play. mpv's counters are cumulative for the file, so
  /// the latest of these covers the play so far even if nothing follows it — a
  /// film that ends on its own may already be unloaded by the time it stops.
  playing('play'),

  /// The viewer stopped, or the item ended: the counters cover the whole play.
  stopped('stop'),

  /// Reloaded in place for a track change. mpv's counters start again from zero
  /// on the reload, so a second `start` line for the same item follows.
  reloaded('reload');

  const PlaybackLogPoint(this.label);

  final String label;
}

/// The mpv properties the line reports, in order.
const List<String> playbackLogProperties = [
  'hwdec',
  'hwdec-current',
  'video-codec',
  'width',
  'height',
  'container-fps',
  'estimated-vf-fps',
  'display-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'video-sync',
];

/// How the line names an item: `Your Name.` for a film,
/// `Sex and the City · S1:E1 · Sex and the City` for an episode, and
/// `Sex and the City · Pilot` when the episode has no season or episode number.
///
/// Double quotes are swapped for single ones, because the title is quoted in
/// the line and a stray quote would make it ambiguous where the title ends.
String playbackLogTitle(Item item) {
  final String title;
  if (item.type == ItemKind.episode) {
    final code = episodeCode(item);
    title = [itemTitle(item), if (code.isNotEmpty) code, item.name].join(' · ');
  } else {
    title = itemTitle(item);
  }
  return title.replaceAll('"', "'");
}

/// One whole line, for example:
///
/// `glassfin: playback stop [direct] "Your Name." id=abc at=1:46:31 hwdec=auto-copy …`
///
/// [values] pairs each property with its value, or null when mpv could not
/// supply one, which prints as `?`.
String playbackLogLine({
  required PlaybackLogPoint point,
  required Item item,
  required bool transcoding,
  required Duration position,
  required List<(String, String?)> values,
}) {
  final delivery = transcoding ? 'transcode' : 'direct';
  final properties = [
    for (final (name, value) in values) '$name=${value ?? '?'}',
  ].join(' ');
  return 'glassfin: playback ${point.label} [$delivery] '
      '"${playbackLogTitle(item)}" id=${item.id} at=${clock(position)} '
      '$properties';
}
