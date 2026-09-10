/// Settings: **every row cycles.**
///
/// No pickers and no sub-screens. A sub-screen per setting is a great deal of
/// navigation for lists this short, and left/right are already spoken for by
/// spatial movement. One button, one step forward through the options, wrapping
/// at the end. See `docs/ui-spec.md` §3.3.
///
/// The sections are split along the line `CLAUDE.md` draws: **behaviour is
/// Glassfin's**, and is persisted and acted on here; **subtitle appearance is
/// mpv's**, stored by us but applied as mpv properties, because that is libass
/// drawing pixels and no amount of Flutter can restyle it.
library;

import 'package:flutter/widgets.dart';

import '../components/logo.dart';
import '../components/screen_header.dart';
import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../jellyfin/models.dart';
import '../jellyfin/track_choice.dart';
import '../nav/registry.dart';
import '../settings/languages.dart';
import '../settings/preferences.dart';
import '../settings/subtitle_appearance.dart';

/// One selectable value and the words for it.
typedef Choice<T> = (T value, String label);

const List<Choice<ThemePreference>> _themes = [
  (ThemePreference.dark, 'Dark'),
  (ThemePreference.light, 'Light'),
  (ThemePreference.system, 'Follow the system'),
];

const List<Choice<SubtitleMode>> _subtitleModes = [
  (SubtitleMode.off, 'Off'),
  (SubtitleMode.forced, 'Forced only'),
  (SubtitleMode.preferred, 'On, preferred language'),
];

const List<Choice<SkipMode>> _skipModes = [
  (SkipMode.off, 'Off'),
  (SkipMode.prompt, 'Show a button'),
  (SkipMode.auto, 'Skip automatically'),
];

List<Choice<String>> get _languageChoices => [
  for (final language in languages) (language.code, language.name),
];

// ---- Subtitle appearance ----------------------------------------------------
//
// The values here are mpv's, not ours: a size is a pixel height that becomes a
// scale factor, and a transparency is mpv's alpha byte — where FF is fully
// transparent, not fully opaque. See lib/playback/mpv_config.dart.

const List<Choice<int?>> _subtitleSizes = [
  (null, 'Default'),
  (32, 'Small'),
  (45, 'Medium'),
  (60, 'Large'),
  (80, 'Very large'),
];

const List<Choice<String?>> _subtitleColours = [
  (null, 'Default'),
  ('#FFFFFF', 'White'),
  ('#EEEEEE', 'Light grey'),
  ('#FBF93E', 'Yellow'),
  ('#FFFFCC', 'Light yellow'),
];

const List<Choice<int?>> _outlines = [
  (null, 'Default'),
  (0, 'None'),
  (2, 'Thin'),
  (4, 'Medium'),
  (6, 'Heavy'),
];

const List<Choice<String?>> _backgrounds = [
  (null, 'Default'),
  ('FF', 'None'),
  ('80', 'Half'),
  ('00', 'Solid'),
];

const List<Choice<(SubtitleAlignX, SubtitleAlignY)>> _placements = [
  ((SubtitleAlignX.center, SubtitleAlignY.bottom), 'Bottom'),
  ((SubtitleAlignX.center, SubtitleAlignY.top), 'Top'),
  ((SubtitleAlignX.left, SubtitleAlignY.bottom), 'Bottom left'),
  ((SubtitleAlignX.right, SubtitleAlignY.bottom), 'Bottom right'),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.preferences,
    required this.subtitles,
    required this.credentials,
    required this.onPreferences,
    required this.onSubtitles,
    required this.onSignOut,
    required this.onReset,
    required this.onBack,
    super.key,
  });

  final Preferences preferences;
  final SubtitleAppearance subtitles;
  final Credentials credentials;
  final void Function(Preferences next) onPreferences;
  final void Function(SubtitleAppearance next) onSubtitles;
  final VoidCallback onSignOut;
  final VoidCallback onReset;
  final VoidCallback onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Focused **by name**: a generic "focus something sensible" would land on
    // whichever element happened to register first, which on this screen is the
    // Back button rather than the list the viewer came here to use.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavRegistry.instance.focusGroup('settings');
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;
    final preferences = widget.preferences;
    final subtitles = widget.subtitles;
    final onPreferences = widget.onPreferences;
    final onSubtitles = widget.onSubtitles;
    final subtitlesOff = preferences.subtitleMode == SubtitleMode.off;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.safeX,
        vertical: metrics.safeY,
      ),
      children: [
        ScreenHeader(title: 'Settings', onBack: widget.onBack),

        // First, because it is the one setting whose effect you can see while
        // you are making it: the page changes as the row cycles.
        _Section(
          title: 'Appearance',
          children: [
            _CycleRow(
              name: 'Theme',
              options: _themes,
              current: preferences.theme,
              onCycle: (next) => onPreferences(preferences.copyWith(theme: next)),
            ),
            _StaticRow(
              name: 'Glassfin',
              // The mark sits on a raised row rather than on the page, so its
              // cuts have to be told what colour they are cut out of.
              trailing: Logo(size: 36, wordmark: true, cutColour: tokens.raised),
            ),
          ],
        ),

        _Section(
          title: 'Playback',
          children: [
            _CycleRow(
              name: 'Preferred audio language',
              options: _languageChoices,
              current: preferences.audioLanguage,
              onCycle: (next) =>
                  onPreferences(preferences.copyWith(audioLanguage: next)),
            ),
            _CycleRow(
              name: 'Subtitles',
              options: _subtitleModes,
              current: preferences.subtitleMode,
              onCycle: (next) =>
                  onPreferences(preferences.copyWith(subtitleMode: next)),
            ),
            _CycleRow(
              name: 'Preferred subtitle language',
              options: _languageChoices,
              current: preferences.subtitleLanguage,
              // Dimmed and skipped by traversal when subtitles are off: a
              // language preference for something switched off is a row that
              // cannot do anything, and reaching one from a sofa is a dead end.
              enabled: !subtitlesOff,
              onCycle: (next) =>
                  onPreferences(preferences.copyWith(subtitleLanguage: next)),
            ),
          ],
        ),

        _Section(
          title: 'Skipping',
          note:
              'Uses the markers your server provides. Jellyfin 10.10 and later '
              'supply these natively; earlier versions need the Intro Skipper '
              'plugin. With neither, nothing is skipped.',
          children: [
            _CycleRow(
              name: 'Intros',
              options: _skipModes,
              current: preferences.introSkip,
              onCycle: (next) =>
                  onPreferences(preferences.copyWith(introSkip: next)),
            ),
            _CycleRow(
              name: 'Credits',
              options: _skipModes,
              current: preferences.outroSkip,
              onCycle: (next) =>
                  onPreferences(preferences.copyWith(outroSkip: next)),
            ),
          ],
        ),

        _Section(
          title: 'Subtitle appearance',
          note:
              'Drawn by mpv, so these are the player’s own settings rather '
              'than Glassfin’s. They apply to every video, and survive a '
              'restart.',
          children: [
            _CycleRow(
              name: 'Subtitle size',
              options: _subtitleSizes,
              current: subtitles.size,
              onCycle: (next) =>
                  onSubtitles(subtitles.copyWith(size: () => next)),
            ),
            _CycleRow(
              name: 'Subtitle colour',
              options: _subtitleColours,
              current: subtitles.color,
              onCycle: (next) =>
                  onSubtitles(subtitles.copyWith(color: () => next)),
            ),
            _CycleRow(
              name: 'Outline',
              options: _outlines,
              current: subtitles.borderSize,
              onCycle: (next) =>
                  onSubtitles(subtitles.copyWith(borderSize: () => next)),
            ),
            _CycleRow(
              name: 'Background',
              options: _backgrounds,
              current: subtitles.backgroundTransparency,
              onCycle: (next) => onSubtitles(
                subtitles.copyWith(backgroundTransparency: () => next),
              ),
            ),
            _CycleRow(
              name: 'Placement',
              options: _placements,
              current: (subtitles.alignX, subtitles.alignY),
              onCycle: (next) => onSubtitles(
                subtitles.copyWith(alignX: next.$1, alignY: next.$2),
              ),
            ),
          ],
        ),

        _Section(
          title: 'Account',
          children: [
            _StaticRow(
              name: 'Signed in',
              value:
                  '${widget.credentials.userName} · '
                  '${widget.credentials.address}',
            ),
            _ActionRow(
              name: 'Sign out',
              value: 'Return to the server and sign-in screen',
              danger: true,
              onSelect: widget.onSignOut,
            ),
            _ActionRow(
              name: 'Reset preferences',
              value: 'Restore the defaults above',
              onSelect: widget.onReset,
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(2.4)),
      child: ConstrainedBox(
        // Capped rather than full width: a settings row that runs the width of a
        // 4K panel puts its name and its value a metre apart.
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: Metrics.rem(0.8)),
              child: Text(
                title,
                style: Type.rem(1).copyWith(color: tokens.inkDim),
              ),
            ),
            if (note != null)
              Padding(
                padding: EdgeInsets.only(bottom: Metrics.rem(0.9)),
                child: Text(
                  note!,
                  style: Type.rem(0.88).copyWith(color: tokens.inkFaint),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A row that steps to the next option on select, wrapping.
class _CycleRow<T> extends StatelessWidget {
  const _CycleRow({
    required this.name,
    required this.options,
    required this.current,
    required this.onCycle,
    this.enabled = true,
    super.key,
  });

  final String name;
  final List<Choice<T>> options;
  final T current;
  final void Function(T next) onCycle;
  final bool enabled;

  String get _label {
    for (final option in options) {
      if (option.$1 == current) return option.$2;
    }
    // A stored value the list no longer offers — a language dropped from the
    // short list, say. Saying "Default" is better than showing nothing.
    return 'Default';
  }

  void _next() {
    final index = options.indexWhere((option) => option.$1 == current);
    onCycle(options[(index + 1) % options.length].$1);
  }

  @override
  Widget build(BuildContext context) => _Row(
    name: name,
    value: _label,
    enabled: enabled,
    onSelect: _next,
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.name,
    required this.value,
    required this.onSelect,
    this.danger = false,
  });

  final String name;
  final String value;
  final VoidCallback onSelect;
  final bool danger;

  @override
  Widget build(BuildContext context) =>
      _Row(name: name, value: value, onSelect: onSelect, danger: danger);
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.name, this.value, this.trailing});

  final String name;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(0.55)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(1.1),
          vertical: Metrics.rem(0.85),
        ),
        decoration: BoxDecoration(
          color: tokens.raised,
          border: Border.all(color: tokens.edge),
          borderRadius: Radii.br,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: Type.body.copyWith(color: tokens.inkDim),
              ),
            ),
            ?trailing,
            if (value != null)
              Text(
                value!,
                textAlign: TextAlign.right,
                style: Type.body.copyWith(color: tokens.inkDim),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.value,
    required this.onSelect,
    this.enabled = true,
    this.danger = false,
  });

  final String name;
  final String value;
  final VoidCallback onSelect;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: Metrics.rem(0.55)),
      child: Focusable(
        group: 'settings',
        // Rows are full width, so they take the ring without scaling: at this
        // size the content is text, and scaling text resamples it into a blur.
        visual: FocusVisual.ringOnly,
        enabled: enabled,
        onSelect: onSelect,
        child: (context, focused) => Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: Metrics.rem(1.1),
              vertical: Metrics.rem(0.85),
            ),
            decoration: BoxDecoration(
              color: tokens.raised,
              border: Border.all(color: tokens.edge),
              borderRadius: Radii.br,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Type.body.copyWith(
                      color: danger ? tokens.danger : tokens.ink,
                    ),
                  ),
                ),
                SizedBox(width: Metrics.rem(1.5)),
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Type.body.copyWith(color: tokens.inkDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
