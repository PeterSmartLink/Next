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
  String? _telegramChallenge;
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
      _setStage(
        ownerReady ? _OwnerStage.ready : _OwnerStage.ownerStart,
        notice: ownerReady ? '' : 'Your OTYA account is signed in. Trust this phone once to enable private owner controls.',
      );
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
      _setStage(
        _OwnerStage.ownerStart,
        notice: 'Signed in. This is the last setup step for this phone.',
      );
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
      _telegramChallenge = null;
      _telegramLaunchStarted = false;
    });
    try {
      await _auth.startOwnerVerification();
      _setStage(
        _OwnerStage.ownerOtp,
        notice: 'A one-time device enrollment code was sent to your verified OTYA email.',
      );
    } on OwnerAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Trusted-phone enrollment could not start. Try again.');
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
      final challenge = await _auth.verifyOwnerOtp(code);
      _otp.clear();
      if (!mounted) return;
      setState(() {
        _telegramChallenge = challenge;
        _stage = _OwnerStage.ownerTelegram;
        _busy = true;
        _telegramLaunchStarted = true;
        _notice = 'Email confirmed. Telegram will open @OtyaPlayerBot directly. Tap Start there, then return to Next.';
      });
      await _auth.startTelegramOwnerVerification(challenge);
      if (mounted) setState(() => _busy = false);
    } on OwnerAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Telegram verification could not start. Make sure Telegram is installed and try again.');
    }
  }

  Future<void> _openTelegramAgain() async {
    if (_busy) return;
    final challenge = _telegramChallenge;
    if (challenge == null || challenge.isEmpty) {
      _setStage(
        _OwnerStage.ownerStart,
        notice: 'The Telegram enrollment challenge is no longer available. Start trusted-phone enrollment again.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      _telegramLaunchStarted = true;
      await _auth.startTelegramOwnerVerification(challenge);
      if (mounted) setState(() => _busy = false);
    } on OwnerAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Telegram could not open. Make sure it is installed on this phone.');
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
      _telegramChallenge = null;
      _telegramLaunchStarted = false;
      _setStage(
        _OwnerStage.ready,
        notice: 'This phone is now trusted. Normal Next launches will open directly.',
      );
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
        if (!silent) _error = 'Trusted-phone enrollment could not be completed.';
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
    _telegramChallenge = null;
    _setStage(_OwnerStage.signIn);
  }

  Future<void> _ownerExpired() async {
    final signedIn = await _auth.hasSignedInSession();
    if (!mounted) return;
    if (!signedIn) {
      _setStage(
        _OwnerStage.signIn,
        notice: 'Your OTYA account session was revoked or expired. Sign in again to restore Next.',
      );
      return;
    }
    await _auth.clearOwnerGrant();
    _telegramChallenge = null;
    _telegramLaunchStarted = false;
    _setStage(
      _OwnerStage.ownerStart,
      notice: 'This phone is no longer trusted for owner controls. Re-verify it to continue.',
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
      title: 'Sign in once',
      subtitle:
          'Use your existing OTYA account on this phone. After the one-time owner enrollment, Next keeps this device signed in until you revoke it or replace it.',
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          decoration: const InputDecoration(labelText: 'OTYA email'),
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
      title: 'Trust this phone',
      subtitle:
          'This is a one-time security ceremony for a new owner phone: verify your OTYA email, then your linked Telegram identity. After that, normal launches open straight into live voice.',
      children: [
        const _EnrollmentStep(number: '1', text: 'OTYA account signed in'),
        const _EnrollmentStep(number: '2', text: 'Confirm email code'),
        const _EnrollmentStep(number: '3', text: 'Confirm in @OtyaPlayerBot'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _startOwnerUnlock,
          icon: const Icon(Icons.phonelink_lock_rounded),
          label: Text(_busy ? 'Starting…' : 'Trust this phone'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
      ],
    );
  }

  Widget _buildOtp() {
    return _Panel(
      title: 'Check your email',
      subtitle:
          'Enter the five-character device enrollment code. It expires quickly and is never stored by Next.',
      children: [
        TextField(
          controller: _otp,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          decoration: const InputDecoration(labelText: 'Device enrollment code', counterText: ''),
          onSubmitted: (_) => _verifyOtpAndOpenTelegram(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verifyOtpAndOpenTelegram,
          child: Text(_busy ? 'Checking…' : 'Confirm and open Telegram'),
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
      title: 'Confirm in Telegram',
      subtitle:
          'Next opens @OtyaPlayerBot directly in the Telegram app with a single-use challenge. Tap Start there and return here. No browser sign-in is required for this step.',
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _completeTelegram(),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(_busy ? 'Checking…' : 'I confirmed in Telegram'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openTelegramAgain,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open Telegram again'),
        ),
      ],
    );
  }
}

class _EnrollmentStep extends StatelessWidget {
  const _EnrollmentStep({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 25,
            height: 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer,
            ),
            child: Text(number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
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
