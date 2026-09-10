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
  cycleAudio,
  cycleSubtitles,
  toggleSubtitles,
  exit;

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
    'cycle_audio' => cycleAudio,
    'cycle_subtitles' => cycleSubtitles,
    'toggle_subtitles' => toggleSubtitles,
    'exit' => exit,
    _ => null,
  };
}
