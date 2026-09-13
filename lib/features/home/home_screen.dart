import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/network/next_owner_api.dart';
import '../../core/platform/next_platform_bridge.dart';
import '../../core/security/owner_biometric.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_overlay.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.onSignOut,
    required this.onOwnerExpired,
  });

  final NextOwnerApi api;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onOwnerExpired;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _voiceSubscription;
  Timer? _listenRestart;
  Timer? _pulseTimer;
  final _workspace = WorkspaceController.instance;

  void _workspaceChanged() { if (mounted) setState(() {}); }

  Future<void> _openFile() async {
    try {
      final result = await _workspace.pickFile();
      if (mounted && !result.ok) setState(() => _hudError = result.message);
    } catch (_) {
      if (mounted) setState(() => _hudError = 'That file could not be opened. Please try another file.');
    }
  }

  Future<void> _openWeb() async {
    final input = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Open a web source'),
      content: TextField(controller: input, keyboardType: TextInputType.url,
        autofocus: true, decoration: const InputDecoration(labelText: 'HTTPS address', hintText: 'https://…'),
        onSubmitted: (value) => Navigator.pop(context, value)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, input.text), child: const Text('Open'))],
    ));
    // Wait until the dialog transition releases its text field before disposal.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (!mounted || value == null) return;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      setState(() => _hudError = 'Enter a full HTTPS address without a username or password.');
      return;
    }
    _workspace.openWeb(uri);
  }


  bool _assistantAvailable = false;
  bool _assistantHeld = false;
  bool _checkingAssistant = true;
  bool _pulseLoading = true;
  bool _chatBusy = false;
  bool _approvalBusy = false;
  bool _listening = false;
  bool _speaking = false;
  bool _autoVoice = true;
  double _voiceLevel = 0;

  String _voiceState = 'opening';
  String _heard = '';
  String _nextText = 'Opening your private OTYA intelligence…';
  String _hudError = '';
  String _pulseError = '';
  String? _conversationId;
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _pendingAction;
  final List<_HudEvent> _events = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspace.addListener(_workspaceChanged);
    _subscribeToVoice();
    _refreshAssistantState();
    _loadPulse();
    _pulseTimer = Timer.periodic(const Duration(minutes: 2), (_) => _loadPulse(silent: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 700), _startListening);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workspace.removeListener(_workspaceChanged);
    _workspace.closeAll();
    _voiceSubscription?.cancel();
    _listenRestart?.cancel();
    _pulseTimer?.cancel();
    unawaited(NextPlatformBridge.stopVoiceListening());
    unawaited(NextPlatformBridge.stopSpeaking());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _autoVoice && !_chatBusy && !_speaking) {
      _scheduleListen(const Duration(milliseconds: 500));
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _listenRestart?.cancel();
      unawaited(NextPlatformBridge.stopVoiceListening());
    }
  }

  void _subscribeToVoice() {
    _voiceSubscription = NextPlatformBridge.voiceEvents.listen(
      _handleVoiceEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _voiceState = 'voice unavailable';
          _hudError = 'The phone voice service is temporarily unavailable.';
          _listening = false;
        });
      },
    );
  }

  void _handleVoiceEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString() ?? '';

    switch (type) {
      case 'state':
        final state = event['state']?.toString() ?? 'idle';
        setState(() {
          _voiceState = state;
          _listening = state == 'listening' || state == 'hearing';
          _speaking = state == 'speaking';
          if (state == 'listening') _hudError = '';
        });
      case 'level':
        final value = event['value'];
        if (value is num) setState(() => _voiceLevel = value.toDouble().clamp(0, 1));
      case 'partial':
        final text = event['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _heard = text;
            _voiceState = 'hearing';
            _listening = true;
          });
        }
      case 'final':
        final text = event['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _heard = text;
            _listening = false;
            _voiceState = 'thinking';
          });
          unawaited(_handleUtterance(text));
        }
      case 'silence':
        setState(() {
          _listening = false;
          _voiceLevel = 0;
          if (!_chatBusy && !_speaking) _voiceState = 'idle';
        });
        _scheduleListen(const Duration(milliseconds: 650));
      case 'tts_done':
        setState(() {
          _speaking = false;
          _voiceState = 'idle';
          _voiceLevel = 0;
        });
        _scheduleListen(const Duration(milliseconds: 350));
      case 'error':
        final message = event['message']?.toString().trim();
        setState(() {
          _listening = false;
          _voiceLevel = 0;
          _voiceState = 'attention';
          _hudError = message?.isNotEmpty == true ? message! : 'Voice stopped unexpectedly.';
        });
        _pushEvent(_hudError, severity: _HudSeverity.warning);
      default:
        break;
    }
  }

  Future<void> _refreshAssistantState() async {
    try {
      final available = await NextPlatformBridge.isAssistantRoleAvailable();
      final held = available ? await NextPlatformBridge.isAssistantRoleHeld() : false;
      if (!mounted) return;
      setState(() {
        _assistantAvailable = available;
        _assistantHeld = held;
        _checkingAssistant = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingAssistant = false);
    }
  }

  Future<void> _requestAssistantRole() async {
    try {
      await NextPlatformBridge.requestAssistantRole();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshAssistantState();
    } catch (_) {
      if (mounted) {
        setState(() => _hudError = 'Android could not open the assistant selector.');
      }
    }
  }

  Future<void> _loadPulse({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _pulseLoading = true;
        _pulseError = '';
      });
    }
    try {
      final report = await widget.api.report();
      if (!mounted) return;
      setState(() {
        _report = report;
        _pulseLoading = false;
        _pulseError = '';
      });
    } on OwnerAccessExpired {
      await _ownerExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pulseLoading = false;
        _pulseError = _cleanError(error);
      });
      if (!silent) _pushEvent(_pulseError, severity: _HudSeverity.warning);
    }
  }

  Future<void> _startListening() async {
    if (!mounted || !_autoVoice || _chatBusy || _approvalBusy || _speaking || _listening) return;
    _listenRestart?.cancel();
    try {
      await NextPlatformBridge.startVoiceListening();
      if (!mounted) return;
      setState(() {
        _voiceState = 'listening';
        _listening = true;
        _hudError = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceState = 'tap to talk';
        _listening = false;
        _hudError = 'Tap the center to start voice.';
      });
    }
  }

  Future<void> _stopListening() async {
    _listenRestart?.cancel();
    try {
      await NextPlatformBridge.stopVoiceListening();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _listening = false;
      _voiceLevel = 0;
      if (!_chatBusy && !_speaking) _voiceState = 'idle';
    });
  }

  void _scheduleListen(Duration delay) {
    if (!_autoVoice || _chatBusy || _approvalBusy || _speaking || !mounted) return;
    _listenRestart?.cancel();
    _listenRestart = Timer(delay, _startListening);
  }

  Future<void> _toggleVoice() async {
    if (_speaking) {
      await NextPlatformBridge.stopSpeaking();
      if (mounted) setState(() => _speaking = false);
      await _startListening();
      return;
    }
    if (_listening) {
      _autoVoice = false;
      await _stopListening();
      if (mounted) setState(() => _voiceState = 'paused');
      return;
    }
    setState(() => _autoVoice = true);
    await _startListening();
  }

  bool _isApprovalIntent(String text) {
    return RegExp(
      r'^(approve|approve it|yes approve|yes, approve|go ahead|send it|post it|publish it|do it|confirm|confirm it)$',
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  bool _isCancellationIntent(String text) {
    return RegExp(
      r"^(cancel|cancel it|stop|don't send it|do not send it|don't post it|do not post it)$",
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  Future<void> _handleUtterance(String text) async {
    final workspaceRequest = text.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), '');
    if (workspaceRequest == 'open file' || workspaceRequest == 'open a file') {
      await _stopListening();
      await _openFile();
      _scheduleListen(const Duration(milliseconds: 500));
      return;
    }
    if (workspaceRequest == 'show system report' && _report != null) {
      _workspace.openReport('System report', _report!);
      _scheduleListen(const Duration(milliseconds: 350));
      return;
    }
    if (_workspace.isOpen && const {'next tab', 'previous tab', 'close current tab', 'close workspace'}.contains(workspaceRequest)) {
      switch (workspaceRequest) {
        case 'next tab': _workspace.nextTab();
        case 'previous tab': _workspace.previousTab();
        case 'close current tab': _workspace.closeActive();
        case 'close workspace': _workspace.closeAll();
      }
      _scheduleListen(const Duration(milliseconds: 350));
      return;
    }

    if (_pendingAction != null && _isApprovalIntent(text)) {
      await _approvePending();
      return;
    }
    if (_pendingAction != null && _isCancellationIntent(text)) {
      await _cancelPending();
      return;
    }
    await _sendToNext(text);
  }

  Future<void> _approvePending() async {
    if (_pendingAction == null || _approvalBusy || _chatBusy) return;
    await _stopListening();
    setState(() {
      _approvalBusy = true;
      _voiceState = 'confirming';
    });
    final summary = (_pendingAction?['summary'] ?? 'this owner action').toString();
    final confirmed = await OwnerBiometric.confirmSensitiveAction(reason: 'Confirm: $summary');
    if (!mounted) return;
    setState(() => _approvalBusy = false);
    if (!confirmed) {
      setState(() {
        _nextText = 'Nothing was executed.';
        _voiceState = 'idle';
      });
      _pushEvent('Owner confirmation was cancelled.', severity: _HudSeverity.info);
      _scheduleListen(const Duration(milliseconds: 450));
      return;
    }
    await _sendToNext('approve', confirmedApproval: true);
  }

  Future<void> _cancelPending() async {
    if (_pendingAction == null || _chatBusy) return;
    await _sendToNext('cancel it', confirmedApproval: true);
  }

  Future<void> _sendToNext(String text, {bool confirmedApproval = false}) async {
    final request = text.trim();
    if (request.isEmpty || _chatBusy) return;
    await _stopListening();
    if (!mounted) return;

    setState(() {
      _chatBusy = true;
      _voiceState = 'thinking';
      _hudError = '';
      _heard = confirmedApproval ? _heard : request;
      _nextText = '…';
    });

    try {
      final reply = await widget.api.chat(request, conversationId: _conversationId);
      if (!mounted) return;
      setState(() {
        if (reply.conversationId?.isNotEmpty == true) _conversationId = reply.conversationId;
        _nextText = reply.answer;
        _chatBusy = false;
        if (reply.approvalRequired && reply.action != null) {
          _pendingAction = reply.action;
          _voiceState = 'approval needed';
        } else if (reply.action != null) {
          final status = reply.action?['status']?.toString();
          if (status == 'completed' || status == 'cancelled' || status == 'failed') {
            _pendingAction = null;
          }
          _voiceState = 'speaking';
        } else if (confirmedApproval) {
          _pendingAction = null;
          _voiceState = 'speaking';
        } else {
          _voiceState = 'speaking';
        }
      });

      _pushEvent(
        reply.tool == null ? 'Next answered.' : 'Next used ${reply.tool!.replaceAll('_', ' ')}.',
        severity: _HudSeverity.info,
      );

      if (_toolRefreshesPulse(reply.tool)) unawaited(_loadPulse(silent: true));

      try {
        await NextPlatformBridge.speak(reply.answer);
        if (mounted) setState(() => _speaking = true);
      } catch (_) {
        if (mounted) {
          setState(() {
            _speaking = false;
            _voiceState = reply.approvalRequired ? 'approval needed' : 'idle';
          });
        }
        if (!reply.approvalRequired) _scheduleListen(const Duration(milliseconds: 650));
      }
    } on OwnerAccessExpired {
      if (mounted) setState(() => _chatBusy = false);
      await _ownerExpired();
    } catch (error) {
      if (!mounted) return;
      final message = _cleanError(error);
      setState(() {
        _chatBusy = false;
        _voiceState = 'attention';
        _hudError = message;
        _nextText = 'I could not complete that request.';
      });
      _pushEvent(message, severity: _HudSeverity.error);
      _scheduleListen(const Duration(seconds: 1));
    }
  }

  bool _toolRefreshesPulse(String? tool) {
    return tool == 'full_report' ||
        tool == 'system_status' ||
        tool == 'release_summary' ||
        tool == 'crash_summary' ||
        tool == 'support_inbox';
  }

  Future<void> _ownerExpired() async {
    _autoVoice = false;
    _listenRestart?.cancel();
    try {
      await NextPlatformBridge.stopVoiceListening();
      await NextPlatformBridge.stopSpeaking();
    } catch (_) {}
    await widget.onOwnerExpired();
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
  }

  void _pushEvent(String text, {required _HudSeverity severity}) {
    if (!mounted || text.trim().isEmpty) return;
    setState(() {
      _events.insert(0, _HudEvent(text.trim(), severity));
      if (_events.length > 4) _events.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pulse = _PulseSnapshot.fromReport(_report, loading: _pulseLoading, error: _pulseError);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CyberBackdrop(
            active: _listening || _speaking || _chatBusy,
            level: _voiceLevel,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  _HudHeader(
                    state: _voiceState,
                    pulse: pulse,
                    busy: _pulseLoading,
                    onRefresh: () => _loadPulse(),
                    onAssistant: _requestAssistantRole,
                    assistantAvailable: _assistantAvailable,
                    assistantHeld: _assistantHeld,
                    onSignOut: widget.onSignOut,
                  ),
                  Expanded(
                    child: Column(children: [
                      Flexible(
                        flex: _workspace.isOpen ? 1 : 3,
                        child: Center(child: FittedBox(fit: BoxFit.scaleDown,
                          child: _VoiceCore(
                            state: _voiceState, level: _voiceLevel,
                            listening: _listening, speaking: _speaking,
                            thinking: _chatBusy || _approvalBusy, onTap: _toggleVoice,
                          ),
                        )),
                      ),
                      if (_workspace.isOpen)
                        Expanded(flex: 3, child: WorkspacePanel(controller: _workspace)),
                    ]),
                  ),
                  Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
                    TextButton.icon(onPressed: _openFile, icon: const Icon(Icons.folder_open_outlined), label: const Text('File')),
                    TextButton.icon(onPressed: _openWeb, icon: const Icon(Icons.public), label: const Text('Web')),
                    TextButton.icon(onPressed: _report == null ? null : () => _workspace.openReport('System report', _report!),
                      icon: const Icon(Icons.analytics_outlined), label: const Text('Report')),
                    if (_workspace.isOpen) IconButton(tooltip: 'Close workspace', onPressed: _workspace.closeAll,
                      icon: const Icon(Icons.close_fullscreen)),
                  ]),
                  if (!_checkingAssistant && _assistantAvailable && !_assistantHeld)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _GlassPanel(
                        child: Row(
                          children: [
                            const Icon(Icons.assistant_outlined, size: 18),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Make Next your phone assistant for faster voice access.',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                            TextButton(onPressed: _requestAssistantRole, child: const Text('Enable')),
                          ],
                        ),
                      ),
                    ),
                  if (_pendingAction != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ApprovalHud(
                        action: _pendingAction!,
                        busy: _approvalBusy || _chatBusy,
                        onApprove: _approvePending,
                        onCancel: _cancelPending,
                      ),
                    ),
                  _LiveTranscriptHud(
                    heard: _heard,
                    answer: _nextText,
                    error: _hudError,
                    listening: _listening,
                    speaking: _speaking,
                    thinking: _chatBusy,
                  ),
                  if (_events.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _EventStrip(events: _events),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseSnapshot {
  const _PulseSnapshot({
    required this.label,
    required this.detail,
    required this.healthy,
    required this.loading,
  });

  final String label;
  final String detail;
  final bool healthy;
  final bool loading;

  factory _PulseSnapshot.fromReport(
    Map<String, dynamic>? report, {
    required bool loading,
    required String error,
  }) {
    if (loading) {
      return const _PulseSnapshot(label: 'SYNC', detail: 'Checking OTYA', healthy: true, loading: true);
    }
    if (error.isNotEmpty) {
      return const _PulseSnapshot(label: 'LINK', detail: 'Needs attention', healthy: false, loading: false);
    }
    final status = report?['status'];
    final map = status is Map ? Map<String, dynamic>.from(status) : const <String, dynamic>{};
    final ready = [map['database'], map['kv'], map['ai']].where((value) => value == true).length;
    final crashes = report?['crashes'];
    final crashCount = crashes is List ? crashes.length : 0;
    final healthy = ready == 3;
    return _PulseSnapshot(
      label: healthy ? 'LIVE' : 'PULSE',
      detail: '$ready/3 core · $crashCount crash groups',
      healthy: healthy,
      loading: false,
    );
  }
}

class _HudHeader extends StatelessWidget {
  const _HudHeader({
    required this.state,
    required this.pulse,
    required this.busy,
    required this.onRefresh,
    required this.onAssistant,
    required this.assistantAvailable,
    required this.assistantHeld,
    required this.onSignOut,
  });

  final String state;
  final _PulseSnapshot pulse;
  final bool busy;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onAssistant;
  final bool assistantAvailable;
  final bool assistantHeld;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _GlassPanel(
          compact: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NEXT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                  Text(state.toUpperCase(), style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant, letterSpacing: .8)),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        _GlassPanel(
          compact: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pulse.healthy ? scheme.primary : scheme.error,
                ),
              ),
              const SizedBox(width: 7),
              Text(pulse.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(width: 7),
              Text(pulse.detail, style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          tooltip: 'Next controls',
          onSelected: (value) {
            if (value == 'refresh') onRefresh();
            if (value == 'assistant') onAssistant();
            if (value == 'signout') onSignOut();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'refresh', child: Text('Refresh system pulse')),
            if (assistantAvailable && !assistantHeld)
              const PopupMenuItem(value: 'assistant', child: Text('Make Next phone assistant')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'signout', child: Text('Sign out and revoke this phone')),
          ],
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.more_horiz_rounded, size: 22),
          ),
        ),
      ],
    );
  }
}

class _VoiceCore extends StatefulWidget {
  const _VoiceCore({
    required this.state,
    required this.level,
    required this.listening,
    required this.speaking,
    required this.thinking,
    required this.onTap,
  });

  final String state;
  final double level;
  final bool listening;
  final bool speaking;
  final bool thinking;
  final Future<void> Function() onTap;

  @override
  State<_VoiceCore> createState() => _VoiceCoreState();
}

class _VoiceCoreState extends State<_VoiceCore> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.listening || widget.speaking || widget.thinking;
    final size = 164.0 + (widget.level * 22);

    return Semantics(
      button: true,
      label: widget.listening ? 'Pause Next listening' : 'Start Next voice',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pulse = .5 + .5 * math.sin(_controller.value * math.pi * 2);
            return SizedBox(
              width: 250,
              height: 250,
              child: CustomPaint(
                painter: _VoiceRingPainter(
                  progress: _controller.value,
                  intensity: active ? .45 + pulse * .35 : .18,
                  primary: scheme.primary,
                  secondary: scheme.tertiary,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          scheme.primary.withValues(alpha: active ? .95 : .72),
                          scheme.tertiary.withValues(alpha: active ? .68 : .36),
                          scheme.surface.withValues(alpha: .12),
                        ],
                        stops: const [0, .58, 1],
                      ),
                      border: Border.all(color: scheme.primary.withValues(alpha: .42)),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: active ? .34 : .15),
                          blurRadius: active ? 48 : 28,
                          spreadRadius: active ? 8 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.thinking
                          ? Icons.auto_awesome_rounded
                          : widget.speaking
                              ? Icons.graphic_eq_rounded
                              : widget.listening
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VoiceRingPainter extends CustomPainter {
  const _VoiceRingPainter({
    required this.progress,
    required this.intensity,
    required this.primary,
    required this.secondary,
  });

  final double progress;
  final double intensity;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = math.min(size.width, size.height) / 2;
    for (var i = 0; i < 3; i++) {
      final radius = base * (.62 + i * .14) + math.sin((progress + i * .21) * math.pi * 2) * 5;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 1.8 : 1
        ..color = (i.isEven ? primary : secondary).withValues(alpha: intensity / (i + 1));
      canvas.drawCircle(center, radius, paint);
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = primary.withValues(alpha: intensity + .12);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: base * .86),
      progress * math.pi * 2,
      math.pi * .58,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _VoiceRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.intensity != intensity || oldDelegate.primary != primary || oldDelegate.secondary != secondary;
  }
}

class _LiveTranscriptHud extends StatelessWidget {
  const _LiveTranscriptHud({
    required this.heard,
    required this.answer,
    required this.error,
    required this.listening,
    required this.speaking,
    required this.thinking,
  });

  final String heard;
  final String answer;
  final String error;
  final bool listening;
  final bool speaking;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heard.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOU', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: scheme.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    heard,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NEXT', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: scheme.tertiary)),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    thinking ? 'Thinking…' : answer,
                    key: ValueKey('$thinking-$answer'),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, height: 1.42, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: .42),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error, style: const TextStyle(fontSize: 11.5))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovalHud extends StatelessWidget {
  const _ApprovalHud({
    required this.action,
    required this.busy,
    required this.onApprove,
    required this.onCancel,
  });

  final Map<String, dynamic> action;
  final bool busy;
  final Future<void> Function() onApprove;
  final Future<void> Function() onCancel;

  String get _detail {
    final payload = action['payload'];
    if (payload is! Map) return '';
    final subject = payload['subject']?.toString().trim() ?? '';
    final text = payload['text']?.toString().trim() ?? '';
    if (subject.isNotEmpty && text.isNotEmpty) return '$subject\n$text';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassPanel(
      strong: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint_rounded, color: scheme.primary, size: 19),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('OWNER APPROVAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              ),
              Text('NOT EXECUTED', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant, letterSpacing: .7)),
            ],
          ),
          const SizedBox(height: 9),
          Text(action['summary']?.toString() ?? 'Review this action', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (_detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.35, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: const Icon(Icons.fingerprint_rounded, size: 17),
                  label: Text(busy ? 'Confirming…' : 'Approve'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: busy ? null : onCancel, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventStrip extends StatelessWidget {
  const _EventStrip({required this.events});
  final List<_HudEvent> events;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, index) {
          final event = events[index];
          final icon = switch (event.severity) {
            _HudSeverity.info => Icons.bolt_rounded,
            _HudSeverity.warning => Icons.warning_amber_rounded,
            _HudSeverity.error => Icons.error_outline_rounded,
          };
          final color = event.severity == _HudSeverity.error ? scheme.error : scheme.primary;
          return Container(
            constraints: const BoxConstraints(maxWidth: 250),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: .25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 5),
                Flexible(child: Text(event.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5))),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _HudSeverity { info, warning, error }

class _HudEvent {
  const _HudEvent(this.text, this.severity);
  final String text;
  final _HudSeverity severity;
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.compact = false, this.strong = false});
  final Widget child;
  final bool compact;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 18 : 22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: strong ? 18 : 12, sigmaY: strong ? 18 : 12),
        child: Container(
          padding: compact ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7) : const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: strong ? .66 : .46),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: strong ? .38 : .24)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CyberBackdrop extends StatelessWidget {
  const _CyberBackdrop({required this.active, required this.level});
  final bool active;
  final double level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.18),
          radius: 1.25,
          colors: [
            scheme.primary.withValues(alpha: active ? .16 + level * .08 : .07),
            scheme.tertiary.withValues(alpha: active ? .09 : .035),
            scheme.surface,
          ],
          stops: const [0, .48, 1],
        ),
      ),
      child: CustomPaint(painter: _GridPainter(color: scheme.outlineVariant.withValues(alpha: .08))),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = .6;
    const gap = 42.0;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.color != color;
}
