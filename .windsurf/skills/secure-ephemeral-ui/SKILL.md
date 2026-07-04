---
name: secure-ephemeral-ui
description: Use this skill when generating Flutter UI components for the Vault, the War Room, or any cross-lingual peer review screens that display sensitive or translated data.
---

# Skill Info
This skill enforces hardware security and zero-retention principles on the presentation layer.

**Execution Steps:**
1. **Hardware Security Flag:** Wrap the topmost widget of the secure screen in the designated platform channel wrapper to enforce `FLAG_SECURE` on Android (blocking screenshots/recordings).
2. **State Management Enforcement:** Do not instantiate any HTTP requests in the `initState` or widget build methods. Bind the UI strictly to local state streams (e.g., listening to the SQLite database stream).
3. **Ephemeral Translation:** If rendering localized text for user-generated content, use the in-memory translation provider. Do not save the translated output back to the local database.
4. **Zero-Plaintext Logging:** Do not add `print()` or `debugPrint()` to the widget lifecycle. If debugging state changes, log only the hashed ID or the boolean success state of the render.

**Resource References:**
* Reference `./snippets/secure_route_wrapper.dart` to see how to implement the anti-screenshot layout builder.