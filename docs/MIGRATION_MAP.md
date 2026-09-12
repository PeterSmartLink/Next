# Next migration map

This file tracks owner-AI capabilities that currently exist across OTYA and where they belong in the new `next` app. The rule is simple: **move the owner experience into Next; keep privileged execution and secrets on the backend.**

## Existing capabilities already discovered

| Existing capability | Current source | Next destination | Backend rule |
| --- | --- | --- | --- |
| Owner conversations | Otya-Server browser Command Center | Talk | keep conversation store server-side |
| System status | AI console `system_status` | Pulse / Talk cards | read through owner gateway |
| Configuration status | `config_status` | Pulse / Connections | never expose raw secrets |
| Connected services | `plugins` registry | Connections | show health/capabilities only |
| Feedback summary | `feedback_summary` | Pulse / Talk | server query |
| Crash summary | `crash_summary` | Pulse / incidents | server query |
| Release summary | `release_summary` | Activity / Talk | server + GitHub context |
| Support inbox | `support_inbox` | Talk / Support detail | server retrieves Gmail |
| Support audit | `support_audit` | Activity | immutable audit trail |
| Private knowledge search | `knowledge_search` | invisible retrieval for Talk | AI Search remains private |
| Full operating report | `full_report` | Pulse briefing | backend synthesis |
| Resend | connection registry | Connections / AI tools | key never enters APK |
| Telegram | connection registry | Connections / communications | backend transport |
| Firebase Remote Config | control plane | Connections / approvals | writes require owner policy |
| GitHub | planned server connector | Talk / Activity / approvals | GitHub App/token server-side |
| Cloudflare | existing bindings | Talk / Pulse / Activity | account token never enters APK |

## Owner app capability groups

### Talk

The default home surface. One conversation can:

- answer ordinary questions
- inspect OTYA status automatically when useful
- explain incidents and recent changes
- retrieve private OTYA knowledge
- review support, releases and crashes
- prepare a change
- surface an approval card when a write is required
- continue naturally by voice or text

No command syntax should be required.

### Pulse

A prioritized live briefing rather than a dashboard wall:

- overall health
- active/developing incidents
- authentication health
- playback/download health
- release/build status
- support pressure
- crashes/regressions
- quota/resource risks
- security signals
- unresolved work
- AI confidence / missing telemetry when important

### Activity

A chronological, auditable stream of meaningful work:

- observations
- investigations
- actions
- approvals
- deployments
- messages/publications
- verification results
- failures/retries
- lessons recorded

### Approvals

Cards produced by backend policy, not by UI guesses:

- external communication
- configuration changes
- GitHub writes
- rollout changes
- deployments
- destructive operations
- security changes
- user/account changes

The app can request biometric confirmation, but server policy remains authoritative.

### Memory

Owner-visible access to structured long-term memory:

- decisions and rationale
- architecture choices
- previous incidents/fixes
- recurring problems
- commitments / unfinished work
- release history
- lessons
- stable owner preferences

Users must be able to correct or retire incorrect operational memories.

### Connections

Health and authorization state for:

- OTYA core/auth/store
- Cloudflare
- GitHub
- Gmail
- Resend
- Firebase
- Telegram
- AI providers / Workers AI / AI Gateway

Show status and scopes, not credential values.

### Device

Android-native owner capabilities:

- selected assistant role
- active real-time voice session
- local wake-word path when supported
- push-to-talk fallback
- lock-screen safe notification entry
- open apps/deep links
- media controls
- approved notification context
- safe device state (battery/network/device version later)
- headset / Bluetooth assistant entry later

Android OS restrictions remain authoritative. Do not use unrestricted AccessibilityService automation as a shortcut.

### Settings

- voice and speech behavior
- personality / humor level
- interruption rules
- proactive notification threshold
- autonomy policy
- action approval policy
- privacy controls
- device permissions
- security / biometric policy
- connection management
- memory controls

## AI capability layers to add on backend

These are capabilities of the same Next identity, not separate bots:

1. **perception** — service events, user reports, telemetry, releases, device context
2. **attention** — rank what matters and suppress noise
3. **world/system model** — services, dependencies, current versions and ownership
4. **self model** — available tools, permissions, limitations and health
5. **working memory** — current investigation and open hypotheses
6. **long-term memory** — decisions, incidents and lessons
7. **planning** — break goals into safe ordered work
8. **reflection** — challenge diagnosis before action and evaluate results afterward
9. **adaptation** — change strategy based on evidence and outcomes
10. **prediction** — detect trends such as quota, crash or latency deterioration
11. **proactivity** — surface important issues without waiting for a prompt
12. **social context** — owner/customer/public/incident tone selection
13. **personality continuity** — stable friendly/professional/humorous presence
14. **verification** — never claim a fix until the observable result is checked
15. **uncertainty** — separate verified fact, inference and hypothesis

## Voice roadmap

### Phase 1
- push-to-talk
- streaming transcript
- streaming TTS reply
- interruption/barge-in
- same conversation as text

### Phase 2
- Android assistant role
- assistant gesture / system entry
- lock-screen safe entry
- headset entry

### Phase 3
- supported local wake phrase
- low-power hotword integration where device/Android APIs permit
- proactive incident conversation from notification

Wake phrase audio should be processed locally until activation whenever feasible.

## Browser retirement

The target is no ordinary owner operations in a browser. However, browser capability is not removed before Next has passed:

- owner sign-in + MFA
- recovery path
- all read-only parity
- all required write approvals
- support/release/incident parity
- audit parity
- notification and voice fallbacks
- emergency access test

Once those checks pass, the web Command Center can become recovery-only and later be deliberately retired. This prevents locking the owner out during migration.

## Immediate implementation order

1. Flutter owner shell and Android bridge
2. mobile owner authentication/grant
3. owner AI REST/WebSocket gateway
4. migrate existing read-only admin tools
5. persistent Talk + Pulse
6. approvals and biometric step-up
7. GitHub/Cloudflare operational tools
8. FCM proactive alerts
9. real-time voice
10. Android assistant service / wake paths
11. memory/reflection/adaptation loops
12. browser parity audit and retirement
