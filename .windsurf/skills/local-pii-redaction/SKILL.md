---
name: local-pii-redaction
description: Use this skill when building moderation layers, submission forms, or War Room data parsers that handle potentially sensitive User-Generated Content (UGC).
---

# Skill Info
This skill strictly enforces the AI Boundary Rule for the Civic Commons platform. No unredacted plaintext can ever touch a cloud-based AI API.

**Execution Steps:**
1. **Deterministic Filter First:** Pass the raw input string through the project's standard regex dictionary to scrub obvious phone numbers, government IDs, and email addresses.
2. **Local Model Routing:** For contextual PII (like names or local addresses), pipe the string through the locally hosted, on-device Gemma model (or the designated open-weights proxy) using the prompt template defined in our resources.
3. **Ciphertext Output:** Ensure the output of the redaction pipeline is immediately encrypted using the user's local key before being queued for API transmission.
4. **Memory Wipe:** Explicitly nullify the plaintext string variables from memory immediately after encryption.

**Resource References:**
* Reference `./prompts/gemma_redaction_prompt.txt` for the strict JSON-output instructions required by the local model.
* Reference `./regex/pii_patterns.json` for the deterministic fallback filters.