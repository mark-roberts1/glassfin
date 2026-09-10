/// Small pure formatters shared by the transport, the cards and Detail.
///
/// Separate from the widgets on purpose: these are the strings the viewer reads
/// from three metres away, and getting one wrong is a visible bug that no widget
/// test would catch as cheaply as a unit test does.
library;

/// `h:mm:ss` above an hour, `m:ss` below.
///
/// A forty-minute episode should not read "0:40:12" — the leading zero is noise,
/// and at a distance it reads as a fault rather than as a duration.
String clock(Duration duration) {
  final total = duration.isNegative ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String pad(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${pad(minutes)}:${pad(seconds)}'
      : '$minutes:${pad(seconds)}';
}

/// A runtime in whole minutes, or an empty string when it is not known.
String runtimeLabel(Duration? runtime) {
  if (runtime == null || runtime == Duration.zero) return '';
  return '${(runtime.inSeconds / 60).round()} min';
}
