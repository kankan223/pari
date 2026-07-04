---
name: zero-knowledge-crypto
description: Use this skill whenever generating logic that encrypts user payloads, decrypts Vault data, or manages cryptographic keys.
---

# Skill Info
This skill ensures the backend never receives plaintext user data or the keys required to decrypt it.

**Execution Steps:**
1. **Key Generation:** If generating a new asymmetric key pair, it must happen entirely on the client device. 
2. **Secure Storage:** Store private keys exclusively in the platform's hardware-backed keystore (e.g., iOS Keychain, Android Keystore via `flutter_secure_storage`). Never write keys to the standard SQLite database.
3. **Payload Wrapping:** Before sending a sensitive payload to the repository layer, serialize the JSON and encrypt it using the user's public key. The repository must only accept the resulting ciphertext.
4. **No Fallbacks:** If a private key is lost or corrupted locally, do not attempt to fetch a backup from the server. Fail securely and prompt the user for their manual recovery phrase.

**Resource References:**
* Reference `./services/crypto_service.dart` for the approved encryption/decryption methods.