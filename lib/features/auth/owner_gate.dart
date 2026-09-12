import 'package:flutter/material.dart';

import '../../core/auth/owner_auth_service.dart';
import '../../core/network/next_owner_api.dart';
import '../home/home_screen.dart';

enum _OwnerStage { loading, signIn, ownerStart, ownerOtp, ownerTelegram, ready }

class OwnerGate extends StatefulWidget {
  const OwnerGate({super.key});

  @override
  State<OwnerGate> createState() => _OwnerGateState();
}

class _OwnerGateState extends State<OwnerGate> with WidgetsBindingObserver {
  final _auth = OwnerAuthService.instance;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _secondFactor = TextEditingController();
  final _otp = TextEditingController();

  _OwnerStage _stage = _OwnerStage.loading;
  bool _busy = false;
  bool _needsSecondFactor = false;
  bool _useRecoveryCode = false;
  bool _telegramLaunchStarted = false;
  String _error = '';
  String _notice = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    _secondFactor.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _stage == _OwnerStage.ownerTelegram &&
        _telegramLaunchStarted &&
        !_busy) {
      _completeTelegram(silent: true);
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _auth.initialize();
      if (!await _auth.hasSignedInSession()) {
        _setStage(_OwnerStage.signIn);
        return;
      }
      final ownerReady = await _auth.hasValidOwnerGrant();
      _setStage(ownerReady ? _OwnerStage.ready : _OwnerStage.ownerStart);
    } catch (_) {
      _setStage(_OwnerStage.signIn);
    }
  }

  void _setStage(_OwnerStage stage, {String notice = ''}) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _busy = false;
      _error = '';
      _notice = notice;
    });
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _notice = '';
    });
    final result = await _auth.login(
      _email.text,
      _password.text,
      totpCode: _needsSecondFactor && !_useRecoveryCode ? _secondFactor.text : null,
      recoveryCode: _needsSecondFactor && _useRecoveryCode ? _secondFactor.text : null,
    );
    if (!mounted) return;
    if (result.ok) {
      _password.clear();
      _secondFactor.clear();
      _setStage(_OwnerStage.ownerStart, notice: 'Signed in to your OTYA account.');
      return;
    }
    setState(() {
      _busy = false;
      _error = result.error ?? 'Sign-in failed.';
      if (result.twoFactorRequired || result.twoFactorInvalid) {
        _needsSecondFactor = true;
      }
    });
  }

  Future<void> _startOwnerUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _notice = '';
    });
    try {
      await _auth.startOwnerVerification();
      _setStage(
        _OwnerStage.ownerOtp,
        notice: 'A single-use owner code was sent to your verified OTYA email.',
      );
    } on OwnerAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Owner verification could not start. Try again.');
    }
  }

  Future<void> _verifyOtpAndOpenTelegram() async {
    final code = _otp.text.trim().toUpperCase();
    if (code.length != 5 || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _notice = '';
    });
    try {
      await _auth.verifyOwnerOtp(code);
      _otp.clear();
      if (!mounted) return;
      setState(() {
        _stage = _OwnerStage.ownerTelegram;
        _busy = true;
        _telegramLaunchStarted = true;
        _notice = 'Email verified. Finish the linked Telegram check, then return to Next.';
      });
      await _auth.startTelegramOwnerVerification();
      if (mounted) setState(() => _busy = false);
    } on OwnerAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Telegram verification could not start. Try again.');
    }
  }

  Future<void> _openTelegramAgain() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      _telegramLaunchStarted = true;
      await _auth.startTelegramOwnerVerification();
      if (mounted) setState(() => _busy = false);
    } on OwnerAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Telegram verification could not start.');
    }
  }

  Future<void> _completeTelegram({bool silent = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (!silent) _error = '';
    });
    try {
      await _auth.completeOwnerVerification();
      _setStage(_OwnerStage.ready, notice: 'Owner mode unlocked.');
    } on OwnerAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!silent || e.code != 'TELEGRAM_PENDING') _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!silent) _error = 'Owner verification could not be completed.';
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  Future<void> _signOut() async {
    _setStage(_OwnerStage.loading);
    await _auth.logout();
    _email.clear();
    _password.clear();
    _secondFactor.clear();
    _otp.clear();
    _needsSecondFactor = false;
    _useRecoveryCode = false;
    _telegramLaunchStarted = false;
    _setStage(_OwnerStage.signIn);
  }

  Future<void> _ownerExpired() async {
    await _auth.clearOwnerGrant();
    _setStage(
      _OwnerStage.ownerStart,
      notice: 'Owner verification expired. Unlock Next again to continue.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _OwnerStage.ready) {
      return HomeScreen(
        api: NextOwnerApi(_auth),
        onSignOut: _signOut,
        onOwnerExpired: _ownerExpired,
      );
    }
    if (_stage == _OwnerStage.loading) return const _LoadingOwner();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _NextIdentity(),
                  const SizedBox(height: 28),
                  if (_notice.isNotEmpty) ...[
                    _Notice(text: _notice),
                    const SizedBox(height: 12),
                  ],
                  if (_error.isNotEmpty) ...[
                    _Notice(text: _error, error: true),
                    const SizedBox(height: 12),
                  ],
                  switch (_stage) {
                    _OwnerStage.signIn => _buildSignIn(),
                    _OwnerStage.ownerStart => _buildOwnerStart(),
                    _OwnerStage.ownerOtp => _buildOtp(),
                    _OwnerStage.ownerTelegram => _buildTelegram(),
                    _ => const SizedBox.shrink(),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignIn() {
    return _Panel(
      title: 'Sign in to OTYA',
      subtitle: 'Next uses your existing OTYA identity. There is no separate owner account.',
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _signIn(),
        ),
        if (_needsSecondFactor) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _secondFactor,
            keyboardType: _useRecoveryCode ? TextInputType.text : TextInputType.number,
            decoration: InputDecoration(
              labelText: _useRecoveryCode ? 'Recovery code' : 'Authenticator code',
            ),
            onSubmitted: (_) => _signIn(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _useRecoveryCode = !_useRecoveryCode;
                        _secondFactor.clear();
                      }),
              child: Text(_useRecoveryCode ? 'Use authenticator code' : 'Use a recovery code'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: Text(_busy ? 'Signing in…' : 'Continue'),
        ),
      ],
    );
  }

  Widget _buildOwnerStart() {
    return _Panel(
      title: 'Unlock owner mode',
      subtitle:
          'For company controls, Next requires fresh owner verification. We will verify your OTYA email and linked Telegram identity.',
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _startOwnerUnlock,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(_busy ? 'Starting…' : 'Unlock Next'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
      ],
    );
  }

  Widget _buildOtp() {
    return _Panel(
      title: 'Check your email',
      subtitle: 'Enter the five-character owner verification code. It expires quickly and is never stored by Next.',
      children: [
        TextField(
          controller: _otp,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          decoration: const InputDecoration(labelText: 'Owner verification code', counterText: ''),
          onSubmitted: (_) => _verifyOtpAndOpenTelegram(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verifyOtpAndOpenTelegram,
          child: Text(_busy ? 'Checking…' : 'Continue with Telegram'),
        ),
        TextButton(
          onPressed: _busy ? null : _startOwnerUnlock,
          child: const Text('Send a new code'),
        ),
      ],
    );
  }

  Widget _buildTelegram() {
    return _Panel(
      title: 'Confirm with Telegram',
      subtitle:
          'Use the Telegram identity already linked to this OTYA account. After Telegram finishes, return to Next and we will complete owner unlock automatically.',
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _completeTelegram(),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(_busy ? 'Checking…' : 'I completed Telegram verification'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openTelegramAgain,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open Telegram verification again'),
        ),
      ],
    );
  }
}

class _LoadingOwner extends StatelessWidget {
  const _LoadingOwner();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Orb(size: 66),
            SizedBox(height: 16),
            Text('Opening Next…'),
          ],
        ),
      ),
    );
  }
}

class _NextIdentity extends StatelessWidget {
  const _NextIdentity();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _Orb(size: 78),
        SizedBox(height: 16),
        Text('Next', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
        SizedBox(height: 5),
        Text('Your private OTYA intelligence'),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: .22), blurRadius: 34, spreadRadius: 3),
        ],
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * .42),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.6)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45)),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: TextStyle(color: error ? scheme.onErrorContainer : scheme.onSecondaryContainer, height: 1.4),
      ),
    );
  }
}
