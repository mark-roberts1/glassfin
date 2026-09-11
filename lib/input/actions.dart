/// The semantic actions the interface responds to.
///
/// Every input source — keyboard, gamepad, HDMI-CEC remote, infrared — is
/// translated into these before it reaches the application, exactly as the Qt
/// build's `InputComponent` did. The interface never sees a key code, which is
/// what lets `assets/inputmaps/*.json` be carried over unchanged and what makes
/// a new input source a mapping file rather than a code change.
library;

enum InputAction {
  up,
  down,
  left,
  right,
  select,
  back,
  home,
  menu,
  search,
  playPause,
  play,
  pause,
  stop,
  seekForward,
  seekBackward,

  /// Continuous scan, doubling on each press. Distinct from [seekForward], which
  /// is a fixed jump — a pad's shoulder buttons scan, the transport's own arrows
  /// and a keyboard's page keys jump.
  fastForward,
  rewind,
  cycleAudio,
  cycleSubtitles,
  toggleSubtitles,
  increaseVolume,
  decreaseVolume,
  mute,
  exit;

  /// The action name as the mapping files spell it, or null if this is not one
  /// the interface answers.
  ///
  /// **A name with no case here is not an error**, and the list of them is
  /// deliberate rather than unfinished. The mapping files address a superset of
  /// what any one client does — `step_forward`, the audio and subtitle delay
  /// nudges, `toggle_watched`, the coloured CEC buttons — and the Qt build's own
  /// interface handled exactly the set below and silently dropped the rest. A
  /// name is added here when there is something for it to do, not before:
  /// `increase_volume` is the one this rebuild could add, because unlike the Qt
  /// build it has a volume control for a pad's thumbstick to reach.
  static InputAction? fromId(String id) => switch (id) {
    'up' => up,
    'down' => down,
    'left' => left,
    'right' => right,
    'select' || 'enter' => select,
    'back' => back,
    'home' => home,
    'menu' => menu,
    'search' => search,
    'play_pause' => playPause,
    'play' => play,
    'pause' => pause,
    'stop' => stop,
    'seek_forward' => seekForward,
    'seek_backward' => seekBackward,
    'fast_forward' => fastForward,
    'rewind' => rewind,
    'cycle_audio' => cycleAudio,
    'cycle_subtitles' => cycleSubtitles,
    'toggle_subtitles' => toggleSubtitles,
    'increase_volume' => increaseVolume,
    'decrease_volume' => decreaseVolume,
    'mute' || 'toggle_mute' => mute,
    'exit' => exit,
    _ => null,
  };
}
