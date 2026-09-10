/// The logo's geometry is transcribed verbatim from the style guide, so what is
/// worth testing is the transcription mechanism rather than the numbers: if the
/// parser is right, the mark is right, and a broken parser would otherwise be
/// invisible until somebody noticed the shape looked slightly wrong.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/components/logo.dart';

void main() {
  group('parseSvgPath', () {
    test('a closed triangle bounds exactly its points', () {
      final path = parseSvgPath('M 10 20 L 30 20 L 30 60 Z');
      expect(path.getBounds(), const Rect.fromLTRB(10, 20, 30, 60));
    });

    test('a quadratic reaches its control point rather than being flattened', () {
      // Path.getBounds reports the *control hull*, not the tight curve, so this
      // checks the control point was consumed as a control point — a Q parsed
      // as two line segments would bound to the same box, which is why the
      // midpoint is measured separately below.
      // Left open: a closing Z would add a straight run back to the origin, and
      // half of *that* total length is not the curve's midpoint.
      final path = parseSvgPath('M 0 0 Q 50 100 100 0');
      expect(path.getBounds(), const Rect.fromLTRB(0, 0, 100, 100));

      // The curve is symmetric, so half its arc length is t = 0.5, where a
      // quadratic sits half way to its control point: y = 50 if it is a curve,
      // y = 100 if the control point was mistaken for a vertex.
      final metric = path.computeMetrics().first;
      final middle = metric.getTangentForOffset(metric.length / 2)!.position;
      expect(middle.dy, closeTo(50, 1));
    });

    test('tolerates commas, tight commands and irregular whitespace', () {
      // Design tools emit all three shapes, and the mark's data is pasted from
      // one.
      final tight = parseSvgPath('M10,20L30,20L30,60Z');
      final commas = parseSvgPath('M10,20 L30,20 L30,60 Z');
      final spaces = parseSvgPath('M 10 20  L 30 20   L 30 60 Z');
      expect(tight.getBounds(), spaces.getBounds());
      expect(commas.getBounds(), spaces.getBounds());
    });

    test('an unclosed path is still a path', () {
      // Compared loosely because Path stores 32-bit floats: 85.6 comes back as
      // 85.5999984741211, which is exact enough for a fin and not exact enough
      // for ==.
      final bounds = parseSvgPath('M 16 112 L 24.98 85.6').getBounds();
      expect(bounds.left, closeTo(16, 0.001));
      expect(bounds.top, closeTo(85.6, 0.001));
      expect(bounds.right, closeTo(24.98, 0.001));
      expect(bounds.bottom, closeTo(112, 0.001));
    });

    test('rejects a path that ends mid-command', () {
      expect(
        () => parseSvgPath('M 10 20 L 30'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a command it does not implement rather than drawing wrong', () {
      // Only M, L, Q and Z are used by the mark. A cubic or a relative command
      // arriving silently would bend the fin somewhere nobody would look.
      expect(
        () => parseSvgPath('M 0 0 C 1 1 2 2 3 3'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseSvgPath('M 0 0 l 10 10'),
        throwsA(isA<FormatException>()),
      );
    });

    test('the silhouette spans the artboard the viewBox declares', () {
      // viewBox="10 14 156 106", so the mark lives inside x 10–166, y 14–120.
      // This is the check that the whole transcription landed in the right
      // coordinate space.
      final silhouette = parseSvgPath(
        'M 16 112 L 24.98 85.6 Q 50.07 72.24 53.54 44.03 Q 66 41.02 70.69 29.1 '
        'Q 78.62 29.91 83.84 23.89 Q 88.97 27.11 94.56 24.76 '
        'Q 97.87 29.59 103.72 29.65 Q 105.85 35.53 111.88 37.16 '
        'Q 113.29 43.68 119.44 46.27 Q 120.49 53.11 126.7 56.18 '
        'Q 127.68 63.09 133.9 66.25 Q 135.05 72.98 141.22 75.91 '
        'Q 142.75 82.24 148.81 84.63 Q 151.14 90.15 157 91.41 L 150 112 Z',
      );
      final bounds = silhouette.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(10));
      expect(bounds.right, lessThanOrEqualTo(166));
      expect(bounds.top, greaterThanOrEqualTo(14));
      expect(bounds.bottom, lessThanOrEqualTo(120));
    });
  });
}
