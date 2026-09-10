/// The ambient backdrop and the veil that sits on it.
///
/// **This is not the same thing as Detail's hero**, and the two are separate
/// widgets on purpose. Ambient is blurred, dim, behind everything, and
/// cross-fades over 420ms as focus moves between cards. The hero is sharp, 62vh,
/// and veiled by gradients tuned per theme. See `docs/ui-spec.md` §1.9 and §5.1.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    required this.imageUrl,
    required this.visible,
    super.key,
  });

  /// Whatever the focused card is showing, or null when nothing has been
  /// focused yet.
  final String? imageUrl;

  /// False during playback and on Detail, which has its own hero.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // **Only the opacity cross-fades; the image swaps instantly
          // underneath.** Cross-fading the images themselves would mean two
          // full-screen blurred layers alive at once for every card the viewer
          // passes over, and the wash is too dim for anyone to see the swap.
          AnimatedOpacity(
            opacity: visible && imageUrl != null ? tokens.ambientOpacity : 0,
            duration: Motion.slow,
            curve: Motion.ease,
            child: imageUrl == null
                ? const SizedBox.expand()
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Transform.scale(
                      // Scaled up so the blur has material to work with at the
                      // edges instead of smearing the frame's own border inward.
                      scale: 1.08,
                      child: Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.expand(),
                      ),
                    ),
                  ),
          ),
          const _AmbientVeil(),
        ],
      ),
    );
  }
}

/// **Always present, even with no ambient image behind it.**
///
/// It is what tints the left edge and the bottom of every screen — the thing
/// that gives the interface its edges rather than letting text run to the frame.
class _AmbientVeil extends StatelessWidget {
  const _AmbientVeil();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gradients = tokens.ambientVeil;

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final gradient in gradients)
          DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
      ],
    );
  }
}

/// Detail's backdrop: sharp, full strength, and fading into the page ground.
///
/// Named `DetailHero` because Flutter already owns `Hero` for shared-element
/// transitions, which is a different idea entirely.
class DetailHero extends StatelessWidget {
  const DetailHero({required this.imageUrl, super.key});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: metrics.heroHeight,
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                // `center 18%` — faces and titles live in the upper third of a
                // backdrop, and centring cuts them in half.
                alignment: const Alignment(0, -0.64),
                errorBuilder: (context, error, stack) =>
                    const SizedBox.expand(),
              ),
            ),

          // The two stop alphas are theme tokens because paper needs far more of
          // itself over a photograph than near-black does before text on top is
          // readable.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tokens.ground.withValues(alpha: tokens.veilNear),
                  tokens.ground.withValues(alpha: tokens.veilMid),
                  tokens.ground,
                ],
                stops: const [0, 0.45, 0.72],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [tokens.ground, tokens.ground.withValues(alpha: 0.1)],
                stops: const [0.05, 0.7],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
