/// The Glassfin mark, and optionally the wordmark beside it.
///
/// Geometry is transcribed verbatim from the style guide's primary lockup by way
/// of `glassfin_old/web/src/components/Logo.svelte`: thirteen cuts across a fin,
/// twelve facets between them running warm to cool, and a mask fading the tail
/// into the surface. See `docs/ui-spec.md` §4.4.
///
/// **Two things about it are load-bearing, and both look like details.**
///
///  1. The facets read the theme's own fin colours. The guide draws a darker
///     ramp on paper and a lighter one on ink, and this is how the mark obeys
///     that without knowing what a theme is.
///  2. **The cuts are painted in the background colour — they are gaps, not
///     lines.** Anywhere other than the page ground — on a raised settings row,
///     on a pill — the caller has to say so with [cutColour], or the mark grows
///     a set of dark scratches across it.
library;

import 'package:flutter/widgets.dart';

import '../design/theme.dart';

/// From the guide: "Below 32px the facets close up. The flat silhouette is the
/// small-size mark, not a fallback."
const double facetFloor = 32;

/// The artboard the paths are drawn in.
const Rect _artboard = Rect.fromLTWH(10, 14, 156, 106);

class Logo extends StatelessWidget {
  const Logo({
    this.size = 48,
    this.wordmark = false,
    this.cutColour,
    super.key,
  });

  /// Height of the mark. The sizes in use are 34 (Home), 36 (Settings) and
  /// 64 (Login) — the last being the only place it is large enough to show its
  /// facets properly.
  final double size;

  /// Set the word beside it, as the primary lockup does.
  final bool wordmark;

  /// What the cuts are cut out of. Defaults to the page ground.
  final Color? cutColour;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The artboard is 156 × 106; hold that aspect at whatever height.
    final width = size * _artboard.width / _artboard.height;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: width,
          height: size,
          child: CustomPaint(
            painter: _LogoPainter(
              fins: tokens.fins,
              ink: tokens.ink,
              cut: cutColour ?? tokens.ground,
              faceted: size >= facetFloor,
            ),
          ),
        ),
        if (wordmark) ...[
          SizedBox(width: size * 0.16),
          Text(
            // Lowercase in the content rather than by transform, because that is
            // what the word is.
            'glassfin',
            style: Type.px(
              size * 0.42,
              weight: Type.medium,
              em: Type.headingEm,
              height: 1,
            ).copyWith(color: tokens.ink),
          ),
        ],
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.fins,
    required this.ink,
    required this.cut,
    required this.faceted,
  });

  final List<Color> fins;
  final Color ink;
  final Color cut;
  final bool faceted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _artboard.width, size.height / _artboard.height);
    canvas.translate(-_artboard.left, -_artboard.top);

    if (faceted) {
      _paintFacets(canvas);
      _paintCuts(canvas, strokeWidth: 2.1);
      // A hairline of the page's own ink, so the tail still has an edge where
      // the mask has taken the colour out of it.
      canvas.drawPath(
        _silhouette,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeJoin = StrokeJoin.round
          ..color = ink.withValues(alpha: ink.a * 0.32),
      );
    } else {
      // One ink. The facets become cuts in the silhouette.
      canvas.drawPath(_silhouette, Paint()..color = ink);
      _paintCuts(canvas, strokeWidth: 2.2);
    }

    canvas.restore();
  }

  /// The facets, under a vertical gradient that dissolves the tail into the
  /// surface rather than ending it.
  void _paintFacets(Canvas canvas) {
    canvas.saveLayer(_artboard, Paint());
    for (var index = 0; index < _facets.length; index++) {
      canvas.drawPath(
        _facets[index],
        // Guarding the index keeps a short palette from throwing rather than
        // simply drawing a duller mark.
        Paint()..color = fins[index % fins.length],
      );
    }
    // dstIn multiplies what is already there by this layer's alpha, which is the
    // SVG mask expressed as a blend.
    canvas.drawRect(
      _artboard,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xD1FFFFFF), // 0.82
            Color(0x33FFFFFF), // 0.20
          ],
          stops: [0, 0.58, 1],
        ).createShader(_artboard),
    );
    canvas.restore();
  }

  void _paintCuts(Canvas canvas, {required double strokeWidth}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = cut;
    for (final path in _cuts) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.faceted != faceted ||
      old.ink != ink ||
      old.cut != cut ||
      !identical(old.fins, fins);
}

// -----------------------------------------------------------------------------
// Geometry. Transcribed verbatim as SVG path data and parsed, rather than
// hand-converted into Path calls: the arithmetic in these numbers is the style
// guide's, and a transcription error in it would be invisible until someone
// noticed the mark looked slightly wrong.
// -----------------------------------------------------------------------------

final List<Path> _facets = const [
  'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 L 31.05 110.19 Z',
  'M 31.05 110.19 L 53.54 44.03 Q 66 41.02 70.69 29.1 L 43.69 108.5 Z',
  'M 43.69 108.5 L 70.69 29.1 Q 78.62 29.91 83.84 23.89 L 55.56 107.05 Z',
  'M 55.56 107.05 L 83.84 23.89 Q 88.97 27.11 94.56 24.76 L 66.96 105.94 Z',
  'M 66.96 105.94 L 94.56 24.76 Q 97.87 29.59 103.72 29.65 L 78.02 105.24 Z',
  'M 78.02 105.24 L 103.72 29.65 Q 105.85 35.53 111.88 37.16 L 88.81 105 Z',
  'M 88.81 105 L 111.88 37.16 Q 113.29 43.68 119.44 46.27 L 99.39 105.24 Z',
  'M 99.39 105.24 L 119.44 46.27 Q 120.49 53.11 126.7 56.18 L 109.79 105.94 Z',
  'M 109.79 105.94 L 126.7 56.18 Q 127.68 63.09 133.9 66.25 L 120.03 107.05 Z',
  'M 120.03 107.05 L 133.9 66.25 Q 135.05 72.98 141.22 75.91 L 130.14 108.5 Z',
  'M 130.14 108.5 L 141.22 75.91 Q 142.75 82.24 148.81 84.63 L 140.12 110.19 Z',
  'M 140.12 110.19 L 148.81 84.63 Q 151.14 90.15 157 91.41 L 150 112 Z',
].map(parseSvgPath).toList(growable: false);

final List<Path> _cuts = const [
  'M 16 112 L 24.98 85.6',
  'M 31.05 110.19 L 53.54 44.03',
  'M 43.69 108.5 L 70.69 29.1',
  'M 55.56 107.05 L 83.84 23.89',
  'M 66.96 105.94 L 94.56 24.76',
  'M 78.02 105.24 L 103.72 29.65',
  'M 88.81 105 L 111.88 37.16',
  'M 99.39 105.24 L 119.44 46.27',
  'M 109.79 105.94 L 126.7 56.18',
  'M 120.03 107.05 L 133.9 66.25',
  'M 130.14 108.5 L 141.22 75.91',
  'M 140.12 110.19 L 148.81 84.63',
  'M 150 112 L 157 91.41',
].map(parseSvgPath).toList(growable: false);

final Path _silhouette = parseSvgPath(
  'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 Q 66 41.02 70.69 29.1 '
  'Q 78.62 29.91 83.84 23.89 Q 88.97 27.11 94.56 24.76 Q 97.87 29.59 103.72 29.65 '
  'Q 105.85 35.53 111.88 37.16 Q 113.29 43.68 119.44 46.27 Q 120.49 53.11 126.7 56.18 '
  'Q 127.68 63.09 133.9 66.25 Q 135.05 72.98 141.22 75.91 Q 142.75 82.24 148.81 84.63 '
  'Q 151.14 90.15 157 91.41 L 150 112 L 140.12 110.19 L 130.14 108.5 L 120.03 107.05 '
  'L 109.79 105.94 L 99.39 105.24 L 88.81 105 L 78.02 105.24 L 66.96 105.94 '
  'L 55.56 107.05 L 43.69 108.5 L 31.05 110.19 L 16 112 Z',
);

/// Commands and numbers. Separators — spaces and commas — fall between the
/// matches and are ignored, and a command letter may abut its first number, both
/// of which are ordinary in SVG that has been through a design tool.
final RegExp _pathToken = RegExp(
  r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
);

/// A deliberately small SVG path parser: absolute `M`, `L`, `Q` and `Z` only.
///
/// That is the entire vocabulary the mark uses, and a general parser — or a
/// dependency for one — would be a great deal of machinery for three commands.
///
/// **Anything else throws rather than being skipped.** A relative `l` or a cubic
/// `C` arriving silently would bend the fin somewhere nobody would think to
/// look, so the strictness is the point: it turns a transcription slip into a
/// failed test instead of a subtly wrong mark.
@visibleForTesting
Path parseSvgPath(String data) {
  final path = Path();
  final tokens = [for (final match in _pathToken.allMatches(data)) match[0]!];

  var index = 0;
  double next() {
    if (index >= tokens.length) {
      throw FormatException('SVG path ended mid-command', data);
    }
    final token = tokens[index++];
    final value = double.tryParse(token);
    if (value == null) {
      throw FormatException('Expected a number, found "$token"', data);
    }
    return value;
  }

  while (index < tokens.length) {
    final command = tokens[index++];
    switch (command) {
      case 'M':
        path.moveTo(next(), next());
      case 'L':
        path.lineTo(next(), next());
      case 'Q':
        path.quadraticBezierTo(next(), next(), next(), next());
      case 'Z':
        path.close();
      default:
        throw FormatException('Unsupported SVG path command "$command"', data);
    }
  }
  return path;
}
