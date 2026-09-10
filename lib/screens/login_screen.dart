/// Sign-in: four stages, and **only the first needs typing.**
///
/// Quick Connect is the default because it is the only sign-in that respects the
/// couch bar: the server shows a code, you approve it from a phone, and no
/// password is ever spelled out on a D-pad. The password path stays for servers
/// with Quick Connect switched off. See `docs/ui-spec.md` §3.6.
///
/// The server address still has to be entered once, which is the only
/// unavoidably tedious moment in the application.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../components/buttons.dart';
import '../components/logo.dart';
import '../design/focus.dart';
import '../design/metrics.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../input/text_entry.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';
import '../nav/registry.dart';

/// Quick Connect has no push channel, so the code has to be polled — and the
/// viewer is walking to another room to approve it.
const Duration quickConnectPoll = Duration(seconds: 3);

enum LoginStage { address, choose, quick, password }

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.deviceId,
    required this.onSignedIn,
    required this.onEditText,
    super.key,
  });

  final String deviceId;
  final void Function(Credentials credentials) onSignedIn;

  /// Opens the on-screen keyboard, which lives at the application root so that
  /// it can sit above everything. See `lib/input/text_entry.dart`.
  final void Function(TextEntrySession session) onEditText;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  LoginStage _stage = LoginStage.address;
  bool _quickEnabled = false;
  String _code = '';
  String? _error;
  bool _busy = false;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _claimFocus();
  }

  @override
  void dispose() {
    _poller?.cancel();
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Focus is claimed on mount and after **every** stage transition: each stage
  /// replaces the whole panel, so the node that had focus no longer exists.
  void _claimFocus() {
    NavRegistry.instance.resetGroup('login');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavRegistry.instance.focusGroup('login');
    });
  }

  void _goTo(LoginStage stage) {
    setState(() => _stage = stage);
    _claimFocus();
  }

  void _edit(
    TextEditingController controller,
    String label, {
    String? placeholder,
    bool obscure = false,
    VoidCallback? onCommit,
  }) => widget.onEditText(
    TextEntrySession(
      label: label,
      controller: controller,
      placeholder: placeholder,
      obscure: obscure,
      onCommit: onCommit,
    ),
  );

  Future<void> _checkServer() async {
    if (_address.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enabled = await Jellyfin.quickConnectEnabled(
        _address.text,
        deviceId: widget.deviceId,
      );
      if (!mounted) return;
      setState(() => _quickEnabled = enabled);
      _goTo(enabled ? LoginStage.choose : LoginStage.password);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startQuickConnect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await Jellyfin.quickConnectInitiate(
        _address.text,
        deviceId: widget.deviceId,
      );
      if (!mounted) return;
      setState(() => _code = state.code);
      _goTo(LoginStage.quick);

      _poller?.cancel();
      _poller = Timer.periodic(quickConnectPoll, (timer) async {
        try {
          final approved = await Jellyfin.quickConnectApproved(
            _address.text,
            state.secret,
            deviceId: widget.deviceId,
          );
          if (!approved) return;
          timer.cancel();
          widget.onSignedIn(
            await Jellyfin.authenticateWithQuickConnect(
              _address.text,
              state.secret,
              deviceId: widget.deviceId,
            ),
          );
        } catch (cause) {
          timer.cancel();
          if (!mounted) return;
          setState(() => _error = _messageFor(cause, 'Quick Connect failed.'));
          _goTo(LoginStage.choose);
        }
      });
    } catch (cause) {
      if (mounted) {
        setState(() => _error = _messageFor(cause, 'Quick Connect failed.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithPassword() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.onSignedIn(
        await Jellyfin.authenticate(
          address: _address.text,
          username: _username.text,
          password: _password.text,
          deviceId: widget.deviceId,
        ),
      );
    } catch (cause) {
      if (mounted) {
        setState(
          () => _error = _messageFor(cause, 'Could not reach that server.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    _poller?.cancel();
    _goTo(_quickEnabled ? LoginStage.choose : LoginStage.address);
  }

  String _messageFor(Object cause, String fallback) =>
      cause is JellyfinException ? cause.message : fallback;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return Center(
      child: SizedBox(
        width: metrics.panelWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The one screen with room for the mark at a size that shows its
              // facets, and the one screen where nobody is in a hurry.
              Padding(
                padding: EdgeInsets.only(bottom: Metrics.rem(0.4)),
                child: const Logo(size: 64, wordmark: true),
              ),
              ..._stageWidgets(),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: Metrics.rem(0.25)),
                  child: Text(
                    _error!,
                    style: Type.rem(0.9).copyWith(color: tokens.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageWidgets() => switch (_stage) {
    LoginStage.address => [
      _lede('Where does your Jellyfin server live?'),
      _Field(
        label: 'Server',
        controller: _address,
        placeholder: 'nas.local:8096',
        priority: 1,
        onSelect: () => _edit(
          _address,
          'Server address',
          placeholder: 'nas.local:8096',
          onCommit: _checkServer,
        ),
      ),
      _gap(),
      if (_address.text.isNotEmpty)
        GlassButton(
          label: _busy ? 'Checking…' : 'Continue',
          group: 'login',
          tone: ButtonTone.primary,
          centred: true,
          onSelect: _checkServer,
        ),
    ],

    LoginStage.choose => [
      _lede('Signed in as this device on ${_address.text}'),
      GlassButton(
        label: _busy ? 'Starting…' : 'Use Quick Connect',
        group: 'login',
        tone: ButtonTone.primary,
        centred: true,
        priority: 1,
        onSelect: _startQuickConnect,
      ),
      _gap(),
      GlassButton(
        label: 'Sign in with a password',
        group: 'login',
        onSelect: () => _goTo(LoginStage.password),
      ),
      _gap(),
      GlassButton(
        label: 'Change server',
        group: 'login',
        tone: ButtonTone.quiet,
        centred: true,
        onSelect: () => _goTo(LoginStage.address),
      ),
    ],

    LoginStage.quick => [
      _lede('Open Jellyfin on your phone or computer and enter this code.'),
      _QuickCode(code: _code),
      Text(
        'Waiting for approval…',
        textAlign: TextAlign.center,
        style: Type.body.copyWith(color: context.tokens.inkDim),
      ),
      _gap(),
      GlassButton(
        label: 'Cancel',
        group: 'login',
        tone: ButtonTone.quiet,
        centred: true,
        priority: 1,
        onSelect: _back,
      ),
    ],

    LoginStage.password => [
      _lede('Sign in to ${_address.text}'),
      _Field(
        label: 'Username',
        controller: _username,
        placeholder: 'Not set',
        priority: 1,
        onSelect: () => _edit(_username, 'Username'),
      ),
      _gap(),
      _Field(
        label: 'Password',
        controller: _password,
        placeholder: 'Not set',
        obscure: true,
        onSelect: () => _edit(_password, 'Password', obscure: true),
      ),
      _gap(),
      GlassButton(
        label: _busy ? 'Signing in…' : 'Sign in',
        group: 'login',
        tone: ButtonTone.primary,
        centred: true,
        onSelect: _signInWithPassword,
      ),
      if (_quickEnabled) ...[
        _gap(),
        GlassButton(
          label: 'Back',
          group: 'login',
          tone: ButtonTone.quiet,
          centred: true,
          onSelect: _back,
        ),
      ],
    ],
  };

  Widget _lede(String text) => Padding(
    padding: EdgeInsets.only(bottom: Metrics.rem(0.75)),
    child: Text(
      text,
      style: Type.body.copyWith(color: context.tokens.inkDim),
    ),
  );

  Widget _gap() => SizedBox(height: Metrics.rem(0.75));
}

/// A value with its name above it, opening the keyboard when selected.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.onSelect,
    this.obscure = false,
    this.priority = 0,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final VoidCallback onSelect;
  final bool obscure;
  final int priority;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final empty = value.text.isEmpty;
        final shown = empty
            ? placeholder
            : (obscure ? '•' * value.text.length : value.text);

        return _FieldButton(
          priority: priority,
          onSelect: onSelect,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Type.rem(0.8).copyWith(color: tokens.inkDim),
              ),
              SizedBox(height: Metrics.rem(0.2)),
              Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.body.copyWith(
                  color: empty ? tokens.inkFaint : tokens.ink,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [GlassButton] takes a string; a field needs two lines, so it gets the same
/// treatment with a widget inside it.
class _FieldButton extends StatelessWidget {
  const _FieldButton({
    required this.child,
    required this.onSelect,
    required this.priority,
  });

  final Widget child;
  final VoidCallback onSelect;
  final int priority;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Focusable(
      group: 'login',
      visual: FocusVisual.ringOnly,
      priority: priority,
      onSelect: onSelect,
      child: (context, focused) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: Metrics.rem(1),
          vertical: Metrics.rem(0.85),
        ),
        decoration: BoxDecoration(
          color: tokens.raised,
          border: Border.all(color: tokens.edge),
          borderRadius: Radii.br,
        ),
        child: child,
      ),
    );
  }
}

/// The code is the whole point of the screen: readable from a sofa, and
/// unmistakable when you are holding a phone in the other hand.
class _QuickCode extends StatelessWidget {
  const _QuickCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final size = Metrics.rem(3.4);

    return Padding(
      padding: EdgeInsets.only(
        top: Metrics.rem(1.2),
        bottom: Metrics.rem(1),
        // Tracking is applied *after* the last character too, so a centred
        // string sits half a letter-space left of true centre. Padding the
        // start by the same amount puts it back — the `text-indent: .35em` the
        // CSS used, for the same reason.
        left: size * 0.35,
      ),
      child: Text(
        code,
        textAlign: TextAlign.center,
        style: Type.px(
          size,
          weight: Type.medium,
          // Wide tracking, so the digits read as separate characters to type
          // into a phone rather than as one number.
          em: 0.35,
        ).copyWith(color: tokens.ink),
      ),
    );
  }
}
