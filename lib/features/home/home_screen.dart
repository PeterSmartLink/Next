import 'package:flutter/material.dart';

import '../../core/platform/next_platform_bridge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _assistantAvailable = false;
  bool _assistantHeld = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refreshAssistantState();
  }

  Future<void> _refreshAssistantState() async {
    try {
      final available = await NextPlatformBridge.isAssistantRoleAvailable();
      final held = available ? await NextPlatformBridge.isAssistantRoleHeld() : false;
      if (!mounted) return;
      setState(() {
        _assistantAvailable = available;
        _assistantHeld = held;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _requestAssistantRole() async {
    await NextPlatformBridge.requestAssistantRole();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshAssistantState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.tertiary,
                      ]),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Next', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        Text('Your private OTYA intelligence', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
                children: [
                  const Text(
                    'Good to see you.',
                    style: TextStyle(fontSize: 34, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -1.2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Talk naturally. Next will understand the context, inspect OTYA when needed, and ask before sensitive actions.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  _PulseCard(theme: theme),
                  const SizedBox(height: 14),
                  Card(
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
                            _checking
                                ? 'Checking Android assistant support…'
                                : _assistantHeld
                                    ? 'Next is selected as your assistant on this phone.'
                                    : _assistantAvailable
                                        ? 'Android can let Next become your selected assistant.'
                                        : 'Assistant-role support is unavailable on this device. Push-to-talk will still work.',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
                          ),
                          if (!_checking && _assistantAvailable && !_assistantHeld) ...[
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _requestAssistantRole,
                              icon: const Icon(Icons.mic_rounded),
                              label: const Text('Make Next my assistant'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _PromptChip(icon: Icons.health_and_safety_outlined, label: 'How are my systems?'),
                      _PromptChip(icon: Icons.rocket_launch_outlined, label: 'Check releases'),
                      _PromptChip(icon: Icons.support_agent_outlined, label: 'Review support'),
                      _PromptChip(icon: Icons.memory_rounded, label: 'What are we forgetting?'),
                    ],
                  ),
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
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Talk to Next…'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: () {},
                icon: const Icon(Icons.mic_rounded),
                tooltip: 'Talk',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text('Connecting', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Next is ready for the owner gateway.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'The UI is now separated from privileged execution. System health, releases, support, crashes, connections and approvals will arrive here from the existing OTYA backend.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () {},
    );
  }
}
