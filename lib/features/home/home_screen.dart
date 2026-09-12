import 'package:flutter/material.dart';

import '../../core/network/next_owner_api.dart';
import '../../core/platform/next_platform_bridge.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];

  bool _assistantAvailable = false;
  bool _assistantHeld = false;
  bool _checkingAssistant = true;
  bool _pulseLoading = true;
  bool _chatBusy = false;
  String _pulseError = '';
  String? _conversationId;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _refreshAssistantState();
    _loadPulse();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
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
    await NextPlatformBridge.requestAssistantRole();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshAssistantState();
  }

  Future<void> _loadPulse() async {
    if (mounted) {
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
      });
    } on OwnerAccessExpired {
      await widget.onOwnerExpired();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pulseLoading = false;
        _pulseError = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _send([String? suggested]) async {
    final text = (suggested ?? _composer.text).trim();
    if (text.isEmpty || _chatBusy) return;
    _composer.clear();
    setState(() {
      _chatBusy = true;
      _messages.add(_ChatMessage.user(text));
    });
    _scrollToBottom();

    try {
      final reply = await widget.api.chat(text, conversationId: _conversationId);
      if (!mounted) return;
      setState(() {
        _conversationId = reply.conversationId;
        _messages.add(_ChatMessage.assistant(reply.answer, tool: reply.tool));
        _chatBusy = false;
      });
      _scrollToBottom();
      if (reply.tool == 'full_report' ||
          reply.tool == 'system_status' ||
          reply.tool == 'release_summary' ||
          reply.tool == 'crash_summary' ||
          reply.tool == 'support_inbox') {
        _loadPulse();
      }
    } on OwnerAccessExpired {
      if (mounted) setState(() => _chatBusy = false);
      await widget.onOwnerExpired();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatBusy = false;
        _messages.add(_ChatMessage.assistant(
          'I could not complete that request: ${e.toString().replaceFirst('Bad state: ', '')}',
        ));
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _voiceNotReady() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Realtime voice is the next transport being connected. Text and owner actions are live now.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              busy: _chatBusy || _pulseLoading,
              onRefresh: _loadPulse,
              onSignOut: widget.onSignOut,
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 124),
                children: [
                  if (_messages.isEmpty) ...[
                    const Text(
                      'Good to see you.',
                      style: TextStyle(
                        fontSize: 34,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Talk naturally. Next can inspect OTYA, reason over what it finds, and keep sensitive actions behind owner approval.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 26),
                  ],
                  _PulseCard(
                    report: _report,
                    loading: _pulseLoading,
                    error: _pulseError,
                    onRefresh: _loadPulse,
                  ),
                  const SizedBox(height: 14),
                  _VoiceCard(
                    checking: _checkingAssistant,
                    available: _assistantAvailable,
                    held: _assistantHeld,
                    onRequest: _requestAssistantRole,
                  ),
                  if (_messages.isEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _PromptChip(
                          icon: Icons.health_and_safety_outlined,
                          label: 'How are my systems?',
                          onPressed: () => _send('Give me a concise current OTYA system report. What needs my attention?'),
                        ),
                        _PromptChip(
                          icon: Icons.rocket_launch_outlined,
                          label: 'Check releases',
                          onPressed: () => _send('Check my recent OTYA releases and tell me if anything needs attention.'),
                        ),
                        _PromptChip(
                          icon: Icons.support_agent_outlined,
                          label: 'Review support',
                          onPressed: () => _send('Review recent support and tell me what needs my attention.'),
                        ),
                        _PromptChip(
                          icon: Icons.memory_rounded,
                          label: 'What are we forgetting?',
                          onPressed: () => _send('Based on OTYA knowledge and current system state, what important unfinished work are we forgetting?'),
                        ),
                      ],
                    ),
                  ],
                  if (_messages.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    for (final message in _messages) _MessageBubble(message: message),
                    if (_chatBusy) const _ThinkingRow(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          color: theme.scaffoldBackgroundColor,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Talk to Next…'),
                  onSubmitted: (_) {
                    if (!_chatBusy) _send();
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _chatBusy
                    ? null
                    : () {
                        if (_composer.text.trim().isEmpty) {
                          _voiceNotReady();
                        } else {
                          _send();
                        }
                      },
                icon: Icon(_composer.text.trim().isEmpty ? Icons.mic_rounded : Icons.arrow_upward_rounded),
                tooltip: 'Talk or send',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.busy,
    required this.onRefresh,
    required this.onSignOut,
  });

  final bool busy;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.tertiary]),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Next', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(busy ? 'Working…' : 'Your private OTYA intelligence', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          IconButton(onPressed: busy ? null : onRefresh, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh Pulse'),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'signout') onSignOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.report,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final Map<String, dynamic>? report;
  final bool loading;
  final String error;
  final Future<void> Function() onRefresh;

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  List<dynamic> _list(dynamic value) => value is List ? value : const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _map(report?['status']);
    final plugins = _list(report?['plugins']);
    final crashes = _list(report?['crashes']);
    final support = _list(report?['support']);
    final releases = _list(report?['releases']);
    final coreHealthy = [status['database'], status['kv'], status['ai']].where((v) => v == true).length;
    final connected = plugins.where((entry) => entry is Map && entry['status'] == 'connected').length;
    final latestRelease = releases.isNotEmpty && releases.first is Map
        ? (releases.first as Map)['tag'] ?? (releases.first as Map)['version']
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Text('Pulse', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: error.isEmpty ? theme.colorScheme.primaryContainer : theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    loading ? 'Checking' : error.isEmpty ? 'Live' : 'Unavailable',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (loading)
              const LinearProgressIndicator()
            else if (error.isNotEmpty) ...[
              Text(error, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 10),
              TextButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ] else ...[
              Text(
                coreHealthy == 3 ? 'Core systems are responding.' : '$coreHealthy of 3 core services are ready.',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Metric(label: 'Connections', value: '$connected/${plugins.length}'),
                  _Metric(label: 'Crashes', value: '${crashes.length} groups'),
                  _Metric(label: 'Support', value: '${support.length} recent'),
                  if (latestRelease != null) _Metric(label: 'Release', value: '$latestRelease'),
                  if (status['feedback_7d'] != null) _Metric(label: 'Feedback 7d', value: '${status['feedback_7d']}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$label  $value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w650)),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.checking,
    required this.available,
    required this.held,
    required this.onRequest,
  });

  final bool checking;
  final bool available;
  final bool held;
  final Future<void> Function() onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.graphic_eq_rounded),
                SizedBox(width: 10),
                Text('Voice presence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              checking
                  ? 'Checking Android assistant support…'
                  : held
                      ? 'Next is selected as your assistant on this phone.'
                      : available
                          ? 'Android can let Next become your selected assistant.'
                          : 'Assistant-role support is unavailable on this device. In-app voice can still work.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
            ),
            if (!checking && available && !held) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRequest,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Make Next my assistant'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _ChatMessage {
  const _ChatMessage(this.role, this.text, {this.tool});
  final String role;
  final String text;
  final String? tool;

  factory _ChatMessage.user(String text) => _ChatMessage('user', text);
  factory _ChatMessage.assistant(String text, {String? tool}) => _ChatMessage('assistant', text, tool: tool);
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 14),
        padding: user ? const EdgeInsets.symmetric(horizontal: 15, vertical: 12) : const EdgeInsets.fromLTRB(0, 8, 24, 8),
        decoration: user
            ? BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!user) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 18),
                  const SizedBox(width: 7),
                  const Text('Next', style: TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(message.text, style: const TextStyle(height: 1.55)),
            if (!user && message.tool != null) ...[
              const SizedBox(height: 8),
              Text(
                'Checked ${message.tool!.replaceAll('_', ' ')}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Next is checking what matters…'),
        ],
      ),
    );
  }
}
