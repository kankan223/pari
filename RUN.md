# RUN.md — Civic Commons (War Room) — Local Setup, Build, Test & Run Guide

This guide takes a developer or tester from a clean clone to a verified local
environment: toolchain check, dependency resolution, static analysis, the full
test suite (1,355+ tests), security-boundary verification, and launching the
app on each supported target.

> **Repository state (important):** the Flutter client (`client/`) is
> currently a **component/test library** — Phases 1–9 have delivered the
> domain, data, state (BLoC), and UI widget layers (260 Dart files, 1,355
> tests), but the app shell (`lib/main.dart` with a `runApp(...)` entry point)
> has **not been wired yet**. Only the `linux/` and `web/` platform scaffolds
> are generated. Everything in the **Testing** and **Security** sections works
> out of the box today; the **Launching** section shows how to generate the
> remaining platform scaffolds and bootstrap an entry point so the UI can
> actually run.

---

## 1. Prerequisites & Toolchain Setup

| Tool | Minimum | Channel / Notes |
|------|---------|-----------------|
| Flutter SDK | `>= 3.19.0` | **Stable** channel |
| Dart SDK | `>= 3.3.0` | Ships with Flutter 3.19+ (pubspec floor: `>=3.2.0 <4.0.0`) |
| Git | `>= 2.30.0` | `git --version` to confirm |
| Xcode (iOS/macOS only) | `15+` | macOS Sonoma+ host required |
| CocoaPods (iOS/macOS only) | latest | `sudo gem install cocoapods` |
| Android Studio | Jellyfish+ | Android SDK Platform 34+, Java 17, Android NDK + CMake |
| Linux build tools | — | CMake ≥ 3.10, Ninja, clang toolchain |
| Windows build tools | — | Visual Studio 2022 (MSVC, C++ workload), CMake, Ninja |

### Platform toolchain details

- **Android:** Android Studio Jellyfish (or newer) with the Android SDK
  (Platform **API 34+**), **Java 17**, and the **Android NDK + CMake**
  components (installed via SDK Manager). The NDK is used by the native
  dependencies (SQLCipher, platform secure storage, WorkManager); the crypto
  primitives themselves (Argon2id, AES-256-GCM, X25519) are pure-Dart via the
  `cryptography` package and need no manual shared-library builds for a
  standard debug build.
- **iOS / macOS:** macOS Sonoma+, **Xcode 15+** (accept the license with
  `sudo xcodebuild -license accept`), and CocoaPods:
  ```bash
  sudo gem install cocoapods
  ```
- **Linux:** CMake, Ninja, and a clang-based C++ toolchain:
  ```bash
  # Debian/Ubuntu
  sudo apt install cmake ninja-build clang
  # Fedora
  sudo dnf install cmake ninja-build clang
  ```
- **Windows:** Visual Studio 2022 with the "Desktop development with C++"
  workload (MSVC), plus CMake and Ninja.

### Verify the toolchain

```bash
flutter doctor
```

Resolve anything flagged in the output before continuing. The command prints
the Flutter/Dart versions and per-platform status:

```bash
flutter --version   # confirms the SDK + Dart versions
```

---

## 2. Cloning & Initial Setup

```bash
git clone https://github.com/your-org/civic-commons.git
cd civic-commons/client

# Resolve all Dart/Flutter dependencies
flutter pub get
```

> The repository is a monorepo: the Flutter client lives in `client/`, the Go
> backend services live in `services/`. All commands below assume you are in
> `client/` unless noted otherwise.

### Code generation

```bash
# Optional — the project currently defines NO codegen dependencies
# (no freezed/json_serializable/build_runner), so this is a no-op safeguard.
# Run it only if a future dependency adds code-generation annotations.
dart run build_runner build --delete-conflicting-outputs
```

---

## 3. Environment Configuration & Native Dependencies

The client relies on a mix of pure-Dart cryptography and native platform
bindings:

| Concern | Package / Mechanism | Platform |
|---------|---------------------|----------|
| Argon2id / AES-256-GCM / X25519 / Ed25519 | `cryptography` (pure Dart) | all |
| X3DH / Double Ratchet | `libsignal_protocol_dart` (pure Dart) | all |
| Encrypted local database | `sqflite_sqlcipher` (native SQLCipher) | Android, iOS, macOS, Linux, Windows |
| Platform secure storage | `flutter_secure_storage` (Keystore / Keychain) | Android, iOS, macOS, Linux, Windows, Web |
| FLAG_SECURE screen-capture guard | `MethodChannelSecureFlagService` (platform channel) | Android |
| Background sync | `workmanager` | Android, iOS |
| Geo / media / connectivity | `geolocator`, `record`, `just_audio`, `connectivity_plus` | mobile + desktop |

**CocoaPods (iOS / macOS only)** — only needed after the platform folders are
generated (see §5). From `client/`:

```bash
cd ios && pod install && cd ..      # iOS
cd macos && pod install && cd ..    # macOS
```

If CocoaPods cannot resolve or the lockfile is stale:

```bash
cd ios
pod repo update
pod install --repo-update
cd ..
```

**Android Keystore & FLAG_SECURE:** both are handled via native platform
channels (`MethodChannelSecureFlagService`) and the standard Android Gradle
build — **no manual shared-library builds are required** for a normal debug
build. `flutter_secure_storage` manages the Keystore-backed key material
automatically.

**Environment variables:** the app reads configuration through
`flutter_dotenv` when wired in the (future) app shell. For the test suite no
`.env` file is required — all tests run against in-memory and locally sealed
stores.

---

## 4. Running Tests & Static Analysis

### Static analysis (expect 0 issues)

```bash
flutter analyze
```

Expected output ends with `No issues found!`.

### Full test suite

The suite currently contains **1,355+ tests** (unit, widget, integration, and
security-checkpoint tests across all phases):

```bash
flutter test
```

On low-resource machines, run serially to avoid the Argon2id-heavy tests
tripping the runner's default per-test timeout:

```bash
flutter test --concurrency=1
```

> **Known environmental note:** under heavy RAM pressure the serial test
> runner's `flutter_tester` subprocess can intermittently segfault while
> executing one Argon2id-heavy crypto file (the identity of the file rotates
> between runs). Every such file passes in isolation — re-run it alone to
> confirm green:
> ```bash
> flutter test test/identity/identity_service_test.dart
> ```

### Coverage report

```bash
flutter test --coverage
# Human-readable summary (optional):
genhtml coverage/lcov.info -o coverage/html   # if lcov is installed
```

### Targeted suites

Phase 8 (War Room) and the PII redaction pipeline:

```bash
flutter test test/war_room/
flutter test test/pii/
```

Focused modules:

```bash
flutter test test/academy/        # Phase 9 foundation scaffold
flutter test test/state/ui/       # all screen/widget tests
flutter test test/signal/         # X3DH + Double Ratchet
flutter test test/pairing/        # multi-device pairing
flutter test test/relay/          # WebSocket relay client
```

---

## 5. Launching the Application

### List available devices

```bash
flutter devices
```

### Current state — what runs today

Only the **Linux** and **Web** platform scaffolds exist, and there is no app
entry point yet. To launch the UI you must first (a) generate any missing
platform folders and (b) create a minimal `lib/main.dart` that composes the
screens. Example bootstrap for `client/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:civic_commons/state/ui/war_room_case_list_screen.dart';
import 'package:civic_commons/state/ui/war_room_masthead.dart';

void main() => runApp(const CivicCommonsApp());

class CivicCommonsApp extends StatelessWidget {
  const CivicCommonsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Civic Commons',
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(
        body: Column(
          children: [
            WarRoomMasthead(label: 'YOUR CASES'),
            Expanded(child: Center(child: Text('War Room shell placeholder'))),
          ],
        ),
      ),
    );
  }
}
```

Generate the platform folders you want (from `client/`):

```bash
# Android
flutter create --platforms=android --org your.org .   # then configure
# iOS / macOS (requires a macOS host + Xcode)
flutter create --platforms=ios,macos --org your.org .
# Windows
flutter create --platforms=windows --org your.org .
```

### Launch commands (per platform)

```bash
# Android — FLAG_SECURE is ACTIVE on War Room screens, blocking
# screenshots/screen-recording (see Troubleshooting for emulator notes)
flutter run -d android

# iOS (macOS host + Xcode required; run `pod install` first)
flutter run -d ios

# macOS (macOS host + Xcode required; run `pod install` first)
flutter run -d macos

# Linux (CMake + Ninja + clang required)
flutter run -d linux

# Web (Chrome)
flutter run -d chrome
```

All of the above expect `lib/main.dart` to exist (see the bootstrap above).
Hot reload is available on every target: press `r` in the terminal, `R` for a
full restart.

---

## 6. Architectural & Security Boundary Checks

The project enforces strict local-first / zero-PII boundaries. The
security-checkpoint suites verify them automatically:

| Invariant | Proof |
|-----------|-------|
| **Zero network imports in core** — `lib/war_room/` and `lib/pii/` contain no `dart:io` sockets, `http`, or `web_socket_channel` imports | whole-tree static scans in `test/war_room/security_checkpoint_test.dart` + `test/pii/security_checkpoint_test.dart` |
| **Memory wiping** — `zeroFill` wipes transient inputs, picked-evidence byte buffers, and key buffers on Quick Exit / submit | `test/war_room/security_checkpoint_test.dart` |
| **Blinded actor handles** — only `VICTIM` and derived `AN-####` handles appear in War Room UI trees, custody logs, and reports | `test/war_room/security_checkpoint_test.dart` (incl. the Task 8.8 Phase 8 COMPLETION AUDIT group) |
| **Encrypted at rest** — evidence files and paused intake drafts are AES-256-GCM sealed; byte-level no-plaintext proofs | `test/war_room/evidence_cipher_test.dart`, `test/war_room/encrypted_intake_draft_store_test.dart` |
| **FLAG_SECURE** — every War Room / Vault / Academy screen wraps in `SecureScreenWrapper` | widget tests + the completion-audit source scans |

Run the full security boundary suite:

```bash
flutter test test/war_room/security_checkpoint_test.dart
flutter test test/pii/security_checkpoint_test.dart
```

Run the entire Phase 8 + Phase 9 verification in one command:

```bash
flutter test test/war_room/ test/pii/ test/academy/
```

---

## 7. Troubleshooting & FAQ

**`pod install` fails with an old CocoaPods spec repo or version errors.**
```bash
cd ios
pod repo update
pod install --repo-update
cd ..
```

**Android emulator shows a black screen / recording tools capture nothing.**
This is the **FLAG_SECURE** screen-capture guard working as designed — the
War Room, Vault, and Academy screens disable screenshots and screen recording
on Android. For UI inspection, either use a **physical Android device** or
launch the **macOS / Web** target instead.

**Argon2id cryptographic tests time out or the runner crashes mid-suite.**
Argon2id (RFC 9106, ~64 MiB memory) is intentionally resource-intensive. On a
low-RAM machine run the suite serially and with an extended timeout:
```bash
flutter test --concurrency=1
```
If a single heavy crypto file is reported as "did not complete", it is the
known runner segfault artifact — run that file alone; it passes in isolation.

**`flutter run -d <platform>` reports "No application found / no
`lib/main.dart`".**
The app shell has not been wired yet (see §5). Create the minimal
`lib/main.dart` bootstrap shown above, then generate the platform folder for
your target with `flutter create --platforms=...`.

**Android build fails on NDK/CMake.**
Install the NDK and CMake from Android Studio → SDK Manager → SDK Tools, then
re-run. No manual shared-library builds are needed for debug.

**`flutter analyze` reports pre-existing lints in generated files.**
Only `flutter analyze` output for `lib/` and `test/` matters — generated /
plugin boilerplate is excluded by `analysis_options.yaml`.

---

## 8. Clean Rebuild

Full reset sequence — use this when dependency resolution or native builds
behave unexpectedly:

```bash
cd client
flutter clean
flutter pub get

# iOS/macOS (only if those platform folders exist)
cd ios && pod install && cd ..       # repeat for macos/

flutter run -d linux                  # or your target device
```

After a clean rebuild, re-verify with:

```bash
flutter analyze
flutter test --concurrency=1
```

---

## 9. Quick Reference (all commands from `client/`)

```bash
flutter doctor                       # toolchain check
flutter pub get                      # fetch dependencies
flutter analyze                      # static analysis (expect 0 issues)
flutter test                         # full suite (1,355+ tests)
flutter test test/war_room/          # Phase 8 War Room suite
flutter test test/pii/               # PII redaction pipeline suite
flutter test --concurrency=1         # serial run for low-RAM machines
flutter run -d linux                 # launch (after §5 bootstrap)
```
