# Next architecture

## Goal

Next is the private owner interface to OTYA intelligence. The phone app is a secure client and device agent; privileged reasoning, company knowledge and infrastructure actions remain on Cloudflare.

The design target is a persistent, conversational operating companion rather than a dashboard or command syntax.

## Runtime split

```text
Owner
  │
  ├─ text / voice / camera / screen / approvals
  ▼
Next Android app
  ├─ Flutter presentation + feature logic
  ├─ secure OTYA identity session
  ├─ native Android assistant/device bridge
  ├─ local wake/assistant entry points
  └─ biometric approval
  │
  │ HTTPS / WebSocket
  ▼
OTYA owner gateway
  ├─ validates OTYA bearer identity
  ├─ validates owner allowlist/role
  ├─ validates short-lived step-up grant
  ├─ applies action policy / scopes
  └─ never exposes infrastructure credentials
  │
  ▼
OTYA AI / control plane on Cloudflare
  ├─ Agents SDK / Durable Object identity
  ├─ Workers AI + AI Gateway
  ├─ Voice agent transport
  ├─ AI Search / Vectorize memory
  ├─ D1 / SQLite state + audit
  ├─ Workflows for durable jobs
  └─ existing OTYA service bindings/tools
```

## Flutter architecture

Use feature-first MVVM with repositories and services. UI remains declarative and does not directly call privileged APIs.

```text
lib/
  app/
    next_app.dart
    router.dart
    theme.dart
  core/
    auth/
    config/
    network/
    platform/
    security/
    models/
  features/
    talk/
    pulse/
    activity/
    approvals/
    memory/
    connections/
    device/
    settings/
```

### State

Riverpod owns app state and dependency injection. Providers are feature-scoped where possible. Long-lived identity, socket and device services are explicit singleton providers.

### Navigation

`go_router` provides deep links and resumable notification destinations. The primary owner shell is intentionally small:

- Talk
- Pulse
- Activity
- Settings

Approvals, memory, connections and device controls are destinations opened from conversation cards, alerts or Settings rather than permanent tabs.

## Android native layer

Flutter is not used to emulate OS-level assistant behavior. Native Kotlin owns Android-specific capabilities and exposes a typed bridge to Dart.

Planned native services:

- `NextVoiceInteractionService` — qualifies Next for the Android assistant role and hosts lightweight always-available assistant plumbing.
- `NextVoiceInteractionSessionService` — creates active assistant sessions and launches the conversational surface.
- `NextNotificationListenerService` — optional owner-granted notification context; data is filtered locally before any server transmission.
- `NextDeviceBridge` — launches apps/deep links, exposes safe device state, media controls and approved Android actions.
- biometric approval remains on-device; a successful local biometric does not replace server authorization.

### Wake word

The wake phrase must not be implemented by continuously uploading microphone audio. The preferred path is Android assistant-role/hotword support when available. Unsupported devices fall back to assistant gesture, lock-screen notification, headset action or push-to-talk.

## Voice

The first voice path is real-time conversational voice while a session is active:

1. microphone audio is captured locally
2. audio streams over authenticated WebSocket
3. Cloudflare voice agent performs STT / turn handling / TTS
4. audio response streams back
5. local playback supports interruption/barge-in
6. transcript and tool activity join the same persistent conversation

Wake-word detection and active conversation audio are separate trust boundaries.

## Cloudflare AI plane

Cloudflare is suitable for the server-side orchestration because the current platform supports durable agents, WebSockets, persistent SQLite-backed state, scheduling, Workflows, Workers AI, AI Gateway and real-time voice agents.

### Agent identity

Create one durable owner-agent instance for the primary owner identity. It contains transient/working state and connection state, not raw credentials.

Suggested state:

```text
mode: normal | focused | incident | recovery
current_focus[]
active_incidents[]
pending_approvals[]
unfinished_work[]
confidence_map
last_reflection_at
last_owner_contact_at
```

### Memory tiers

- working memory: Durable Object state / SQLite
- conversation history: Durable Object SQLite or existing AI conversation tables
- structured company memory: D1
- semantic product/incident memory: AI Search / Vectorize
- large generated artifacts: R2

Memory writes are classified as facts, decisions, observations, hypotheses or lessons. Hypotheses must never silently become facts.

### Cognitive loop

```text
observe
→ prioritize
→ retrieve memory/context
→ reason
→ self-check / uncertainty
→ plan
→ policy check
→ act or request approval
→ verify result
→ record outcome
→ reflect
```

Reflection is a controlled server workflow, not uncontrolled self-rewriting.

## Tool and permission model

Every tool declares:

- scopes required
- read/write class
- risk level
- whether biometric/server step-up is needed
- whether it can run unattended
- audit payload policy
- verification procedure

Suggested classes:

### Green — autonomous

- health/status reads
- release/workflow reads
- support summarization
- crash/feedback analysis
- knowledge search
- diagnostics
- safe local media/device actions

### Yellow — policy approval or user confirmation

- send external message
- publish announcement
- retry/restart an operation
- modify remote configuration
- create/update issue or pull request
- start deployment to non-production

### Red — fresh owner authorization

- production deployment/rollback
- destructive data/resource operations
- credential/security policy changes
- user/account privilege changes
- financial actions
- public release publication

The model never grants itself permission. Server policy is authoritative.

## Owner authentication

The existing OTYA account tokens remain the base identity. Next should add a mobile-owner grant rather than reuse browser cookies.

Target flow:

1. normal OTYA sign-in gives access + refresh token
2. app calls `/auth/admin/start` using bearer token
3. existing email OTP + Telegram verification completes
4. auth service issues a short-lived, scoped owner grant bound to user/device/session
5. Next stores it in Android secure storage
6. owner gateway requires both normal identity and valid owner grant
7. sensitive operations can additionally require recent biometric + server challenge

Browser admin cookies remain separate and cannot be replayed as mobile credentials.

## Proactivity

The backend may decide that the owner should be contacted, but Android decides how that contact is surfaced.

- low priority: add to Pulse
- normal: Next notification
- important: high-priority FCM notification with concise safe summary
- critical: notification requesting owner attention; sensitive details remain hidden until unlock

Cloudflare itself does not bypass Android background rules. FCM and Android assistant-role behavior are the supported wake-up paths.

## Personality and relationship continuity

Personality is a stable policy layer shared across text and voice:

- friendly and natural
- professional during work
- calm and factual during incidents/security/payment problems
- light situational humor when appropriate
- able to disagree respectfully
- transparent about uncertainty
- no fake claims of consciousness or emotions
- no manipulative dependency behavior

The owner relationship may have shared history and jokes, but truth, privacy and safety outrank personality.

## Browser retirement rule

Do not delete the existing browser Command Center immediately. New owner capability is built in Next first. Once feature parity, mobile owner auth, recovery, audit and emergency access have been tested, browser operational UI can become a recovery-only surface or be removed deliberately.

## Non-goals

- storing Cloudflare/GitHub/Resend/Firebase secrets in the APK
- giving Android AccessibilityService unrestricted autonomous UI control as a shortcut around supported APIs
- pretending the model is literally conscious
- putting each AI skill in a separate app/repository
- replacing server authorization with a local biometric check
