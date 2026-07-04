---
trigger: always_on
---


# Civic Commons: Windsurf AI Development Guidelines

These rules strictly govern the architectural decisions, code generation, and agentic behavior of the Windsurf AI assistant for the Civic Commons project.

## I. Core System & Product Rules

**1. The Cross-Lingual UGC Rule (Zero-Retention Translation)**
* Any machine translation for cross-lingual peer review or moderation must execute purely client-side or via a self-hosted translation service within the API Gateway Layer.
* The system must immediately drop plaintext post-translation. No retention of translated strings on the server.

**2. The AI / Agentic Automation Boundary**
* PII filtering and severity scoring must rely on deterministic logic (Regex, known-hash matching) or self-hosted, open-weights models (e.g., Gemma) running exclusively within the secure backend.
* Do not use standard cloud-based AI APIs that retain plaintext data. Local on-device models are prioritized for PII redaction prior to API transit.

**3. The Graceful "Cold Start" Protocol**
* If a hyperlocal pin code query returns fewer than 5 posts in the last 7 days, smoothly expand the query radius to the Assembly constituency or district level.
* Clearly mark expanded results with a "Nearby" badge to manage user expectations.

**4. Hardware Trust & Zero Fingerprinting**
* Enforce strict ephemeral hardware policies. Apply `FLAG_SECURE` (Android) to block OS-level screenshots and screen recordings in the Vault and War Room.
* Define graceful degradation for rooted/jailbroken devices without sending root-status telemetry back to the server (strictly zero device fingerprinting).

---

## II. Coding Standards & Agent Behavior

**1. The "Zero-Plaintext" Logging Guardrail**
* Under no circumstances should you generate `print()` or `debugPrint()` statements that output raw payload data, user IDs, or decrypted Vault data to the console.
* All debugging logic interacting with Zero-Knowledge layers must log encrypted hashes or boolean success/fail states only.

**2. State Management & Offline-First Enforcement**
* Never write direct HTTP calls from UI widgets.
* All network requests must be routed through the local SQLite/queue repository first to maintain the offline-first architecture. 
* Enforce strict separation of concerns using the designated state manager. UI components must only listen to local state, never direct network futures.

**3. Strict Package Management**
* Do not add new dependencies to `pubspec.yaml` without explicit permission. 
* Utilize pre-approved packages for cryptography and local storage. Prioritize Dart-native implementations over platform-channel wrappers where possible.

**4. Agentic Debugging & Execution Limits**
* When encountering a build error or analyzer warning, do not blindly attempt iterative syntax fixes.
* Read the specific framework analyzer output or stack trace first. If a fix fails twice, halt autonomous execution and await human architectural clarification.