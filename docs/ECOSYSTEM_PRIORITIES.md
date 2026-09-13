# Ecosystem improvement register

Scope: Next private owner app, Otya Player, Otya-Server, website and connected delivery services.
Updated: 2026-09-13. Code changes are not production verification. Live releases remain deferred.
This is a target and validation register, not a claim that every capability is absent or complete.

## Product boundaries
- Next is the private owner companion and operations interface.
- Otya Player is the customer media experience.
- Cloudflare holds privileged execution, identity enforcement and secrets.
- Public website and Telegram surfaces expose only approved customer information.
- Extend existing systems after checking current implementation; avoid duplicate services.

## Release-critical checks
1. Android playback: background and lock-screen media controls, audio focus, headset/Bluetooth changes, notification permission denial, process recovery.
2. Updates: signed artifact verification, version compatibility, resumable download, progress/cancel/retry, Android installation consent, actionable errors, recovery from failed update.
3. Identity: account/owner separation, revocation, expired sessions, verified Telegram Mini App identity, authorization on every privileged endpoint.
4. Delivery: durable event IDs, bounded retry/backoff, deduplication, delivery receipts, quiet hours/preferences and correct deep links for FCM, email and Telegram.
5. Operations: correlated errors without secrets, quota alerts, queue backlog/dead-letter recovery, migrations, backup restoration and documented rollback.
6. End-to-end release gate: actual Android evidence plus staging email/push/Telegram delivery and recovery tests. Never equate a provider accepting a request with delivery to a person.

## Unified customer experience
- Shared brand tokens and approved logos; readable light/dark themes, text scaling, accessible contrast, touch targets and reduced motion.
- Useful public pages: product, download, support, privacy, terms, release history, verified service status.
- Consistent friendly email/Telegram templates with clear purpose, one primary action and notification preferences.
- Offline and slow-network states, cached content with freshness labels, progress and cancellation.
- Support feedback with consent-based diagnostics; avoid collecting private media or unnecessary personal data.

## Next intelligence and HUD
- Quiet voice-first launch; content summoned on demand, readable translucent panels, focus/hide/restore.
- Real report time ranges, source references and timestamps; distinguish retrieved data from AI interpretation.
- Explicit comparison of visible readable documents; unavailable extraction must not silently omit a document.
- Preserve browser history and document position across panel changes within an authorized session.
- Private PDF/image/Office extraction with limits and explicit data-use boundaries.
- Editable and deletable memory, conversation continuity, task history and searchable decisions.
- Friendly professional tone, optional light humor, honest uncertainty; never claim consciousness.
- Long-running jobs: progress, cancel, retry, result receipts and recovery after reconnect.
- Sensitive actions: scoped permissions, concrete preview, owner confirmation and auditable outcomes.
- Treat web pages/documents as untrusted data; they cannot authorize tools or override owner instructions.

## Dynamic configuration
- Remotely configurable copy, release metadata, bounded theme tokens and feature availability.
- Schema validation, versioning, cached safe defaults, staged rollout and rollback.
- Security boundaries, signature verification and privileged authorization remain enforced in code/server policy.
- No arbitrary downloaded executable feature code masquerading as configuration.

## Evidence and current change
- HUD simultaneous panels and quiet defaults: committed; Android verification pending.
- Visible text comparison context: implementation and regression tests added; Flutter execution pending.
- Remaining items above require inventory and evidence before being marked verified.
