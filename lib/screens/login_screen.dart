/// Sign-in — walking-skeleton form.
///
/// Roughly styled on purpose: this exists to prove the stack reaches a real
/// server, not to look right. Phase 5 rebuilds it against `docs/ui-spec.md` §3.6
/// with the four stages and the on-screen keyboard.
///
/// Quick Connect is the television answer: the server shows a code, someone
/// approves it from a phone, and no password is ever typed on a D-pad. The
/// address still has to be entered once, which is the only unavoidably tedious
/// moment in the application.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../design/metrics.dart';
import '../design/theme.dart';
import '../jellyfin/client.dart';
import '../jellyfin/models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.deviceId,
    required this.onSignedIn,
    super.key,
  });

  final String deviceId;
  final void Function(Credentials credentials) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;
  QuickConnectState? _quickConnect;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (cause) {
      if (mounted) {
        setState(
          () => _error = cause is JellyfinException
              ? cause.message
              : 'Something went wrong: $cause',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithPassword() => _run(() async {
    final credentials = await Jellyfin.authenticate(
      address: _address.text,
      username: _username.text,
      password: _password.text,
      deviceId: widget.deviceId,
    );
    widget.onSignedIn(credentials);
  });

  Future<void> _startQuickConnect() => _run(() async {
    final state = await Jellyfin.quickConnectInitiate(
      _address.text,
      deviceId: widget.deviceId,
    );
    if (!mounted) return;
    setState(() => _quickConnect = state);

    // Poll rather than wait: there is no push channel, and the viewer is
    // walking to another room to approve it.
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final approved = await Jellyfin.quickConnectApproved(
          _address.text,
          state.secret,
          deviceId: widget.deviceId,
        );
        if (!approved) return;
        timer.cancel();
        final credentials = await Jellyfin.authenticateWithQuickConnect(
          _address.text,
          state.secret,
          deviceId: widget.deviceId,
        );
        widget.onSignedIn(credentials);
      } catch (cause) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _quickConnect = null;
            _error = '$cause';
          });
        }
      }
    });
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final metrics = context.metrics;

    return Scaffold(
      backgroundColor: tokens.ground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: metrics.safeX),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Glassfin', style: Type.title.copyWith(color: tokens.ink)),
                const SizedBox(height: 24),
                _field(_address, 'Server address', tokens.ink),
                const SizedBox(height: 12),

                if (_quickConnect != null) ...[
                  Text(
                    'Enter this code in Jellyfin on another device:',
                    style: Type.body.copyWith(color: tokens.inkDim),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _quickConnect!.code,
                    style: Type.display.copyWith(color: tokens.accentText),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: _busy ? null : _startQuickConnect,
                    child: const Text('Sign in with Quick Connect'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'or with a password',
                    style: Type.body.copyWith(color: tokens.inkFaint),
                  ),
                  const SizedBox(height: 8),
                  _field(_username, 'Username', tokens.ink),
                  const SizedBox(height: 8),
                  _field(_password, 'Password', tokens.ink, obscure: true),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _signInWithPassword,
                    child: const Text('Sign in'),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: Type.body.copyWith(color: tokens.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// An ordinary text field, which the Qt build could not have — its shell ate
  /// every key event before the page saw it.
  Widget _field(
    TextEditingController controller,
    String label,
    Color ink, {
    bool obscure = false,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    style: Type.body.copyWith(color: ink),
    decoration: InputDecoration(labelText: label),
  );
}
