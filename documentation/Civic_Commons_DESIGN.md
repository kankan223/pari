# The Civic Commons — Design System & UX Specification
## Visual Identity, Component Library, and Pillar-by-Pillar Interface Design

**Companion documents:** Civic_Commons_PRD.md v1.0 · Civic_Commons_TECHSTACK.md v1.0
**PRD correlation policy:** Every design decision cites the PRD principle or requirement it serves.
**Status:** Phase 0 / Phase 1 design reference

---

## Table of Contents

1.  Design Philosophy
2.  Visual Identity — The "Field Documents" System
3.  Design Token System
4.  Component Library
5.  App Shell & Navigation Architecture
6.  Pillar 1 — The Vault: UX Design
7.  Pillar 2 — The Daily Ledger: UX Design
8.  Pillar 3 — The War Room: UX Design
9.  Pillar 4 — The Academy: UX Design
10. Cross-Pillar Screens
11. Security-Sensitive UX Flows
12. Offline & Low-Connectivity States
13. Vernacular & Accessibility Design
14. Dark Mode System
15. Motion & Animation Principles
16. Design-to-PRD Traceability Matrix

---

## 1. Design Philosophy

### 1.1 Grounding Statement

The Civic Commons is civic infrastructure for communities that have historically been made invisible by the institutions that govern them. Its users are not scrolling for entertainment — they are a student studying with no money for coaching classes, an activist protecting a source, a shop owner who has been blackmailed, a volunteer forensics analyst giving their Saturday to help a stranger.

This is not a lifestyle app. The design must communicate: **this tool takes your situation seriously.** It should feel like the physical objects people reach for when something really matters — a filed document, a newspaper of record, an investigator's case folder, a well-indexed textbook. Not a social feed. Not a dashboard. Something that holds weight.

### 1.2 Design Tenets (mapped to PRD §1.3)

| PRD Product Principle | Design Translation |
|---|---|
| **Privacy by architecture** | The UI never shows a phone number, a real name, or a device fingerprint. Karma scores are visible, not identities. The Vault shows only usernames and timestamps. |
| **Local-first** | Every screen has a defined offline state. No "loading…" spinners that hang forever — the app renders from cache, then updates. Data cost is always visible. |
| **Verification without surveillance** | Trust indicators are behavioral (karma tier, verified post badges), never biometric or demographic. |
| **Free at the civic core** | No upsell surfaces in the Vault, War Room intake, or base Ledger feed. Premium indicators appear only in account settings, never mid-flow. |

### 1.3 What This Design Is Not

- Not glassmorphism, not a dark-mode-first "hacker aesthetic" — that would position it as an enthusiast tool, not a civic utility for Priya's ₹6,000 Android.
- Not a warm-cream-background serif editorial template — that reads as aspirational media brand, wrong register for a crisis intake form.
- Not a Material Design clone — respects Material 3 conventions where they serve learnability, departs where they don't serve the brief.

---

## 2. Visual Identity — The "Field Documents" System

### 2.1 The Core Idea

Each of the four pillars maps to a real-world document type that the people using that pillar already trust and recognize. The app's visual system is built on those document metaphors — not as decoration, but as meaning.

| Pillar | Document Metaphor | Visual Character |
|---|---|---|
| **The Vault** | Classified security briefing | Redaction bars, stamp marks, dense mono type for IDs |
| **The Daily Ledger** | Broadsheet newspaper / local gazette | Masthead typography, column structure, edition markers |
| **The War Room** | Intelligence case dossier | Case number stamps, severity classification bands, chain-of-custody notation |
| **The Academy** | University syllabus binder | Ruled-line chapter headers, hierarchical numbering, progress tabs |

### 2.2 Signature Element — The Pillar Masthead

The single most distinctive visual element. Each pillar has a masthead strip at the top of its primary screen, styled after its document type. This gives the four pillars strong individual identity within a shared design vocabulary — a user entering The War Room should *feel* the shift from The Ledger, not just read a different tab label.

```
┌────────────────────────────────────────────────────┐  ← Vault Masthead
│ ██████  THE VAULT     [CLASSIFIED]  @username  🔒 │  Black bar, mono font,
│ ████                                               │  redaction aesthetic
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐  ← Ledger Masthead
│   THE DAILY LEDGER · EDITION 412 · PATNA 800001   │  Newspaper nameplate
│ ══════════════════════════════════════════════════ │  weight rule line
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐  ← War Room Masthead
│ ▌WAR ROOM▐  CASE #CC-0047  ⬛ HIGH  ANALYST:VIK  │  Dossier stamp bar,
│ CIVIC COMMONS OSINT UNIT — SECURE CHANNEL          │  amber severity band
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐  ← Academy Masthead
│  THE ACADEMY  ──────────────────────────────────  │  Textbook chapter
│  Chapter 3 · Mathematics · Module 12 / 48          │  header with ruled line
└────────────────────────────────────────────────────┘
```

### 2.3 Logo Concept

A single glyph: the Devanagari numeral ੪ (4, referencing the four pillars) inscribed inside an unbroken circle — the civic commons. The circle is never fully closed; a small gap at the top represents open information and community access. The glyph renders cleanly at 16px (notification icon) through to full splash screen.

Wordmark: "CIVIC COMMONS" set in Mukta Bold, tracked +80 (0.08em), all caps. The wordmark sits below the glyph mark, never beside it — vertical lockup only, to work in narrow mobile headers.

### 2.4 Color System

**Design decision:** No teals or blues as the primary brand color — those read "fintech." No red primary — that reads "alert/emergency" which collides with the War Room severity system. Saffron/civic gold as the primary accent is semantically grounded in India's civic and activist tradition, and is warm enough to feel human at human scale.

```
Semantic Color Roles
─────────────────────────────────────────────────────
Name              Hex       Role
─────────────────────────────────────────────────────
Ink               #1C1C2E   Primary text, app shell bg, nav bar
Paper             #F5F1E8   Screen backgrounds, card surfaces
Civic Gold        #D4870F   Primary CTA, karma indicators, brand accent
Alert Red         #B52A2A   Danger, destructive actions, form errors
Verified Emerald  #1E6B3A   Success, verified badges, karma gain
Muted             #6B6B7A   Secondary text, disabled states, placeholders
Surface           #FFFFFF   Card backgrounds (light mode)
Divider           #E0DDD6   Horizontal rules, card borders

Pillar Accent Colors (each pillar's masthead + primary interactive color)
─────────────────────────────────────────────────────
Vault Blue        #1A3D6B   The Vault — trustworthy, classified-document navy
Ledger Green      #1E4D38   The Daily Ledger — broadsheet forest green
War Room Amber    #8B3A0F   The War Room — urgent, dossier-stamp amber
Academy Teal      #1A5C68   The Academy — deep knowledge teal
─────────────────────────────────────────────────────

Severity Scale (War Room-specific)
─────────────────────────────────────────────────────
CRITICAL          #B52A2A   Imminent physical threat
HIGH              #8B3A0F   Active digital extortion
MEDIUM            #D4870F   Harassment / fake profile
LOW               #1A5C68   Information request
─────────────────────────────────────────────────────
```

### 2.5 Accessibility Contrast Ratios

All text combinations verified to WCAG 2.1 AA (4.5:1 minimum for body, 3:1 for large text):

| Foreground | Background | Ratio | Use |
|---|---|---|---|
| Ink #1C1C2E | Paper #F5F1E8 | 14.2:1 | Body text on screen background |
| Ink #1C1C2E | Surface #FFFFFF | 15.8:1 | Body text on cards |
| Surface #FFFFFF | Vault Blue #1A3D6B | 7.1:1 | White text on Vault masthead |
| Surface #FFFFFF | Ledger Green #1E4D38 | 7.8:1 | White text on Ledger masthead |
| Surface #FFFFFF | War Room Amber #8B3A0F | 4.6:1 | White text on War Room header |
| Surface #FFFFFF | Academy Teal #1A5C68 | 5.9:1 | White text on Academy header |
| Surface #FFFFFF | Civic Gold #D4870F | 3.1:1 | Large/bold only (button labels) |
| Surface #FFFFFF | Alert Red #B52A2A | 5.4:1 | Error state text |

---

## 3. Design Token System

All values are defined as tokens. The Flutter implementation uses `ThemeData` extension classes + a `DesignTokens` singleton. No hardcoded hex values or raw pixel values in widget files.

### 3.1 Color Tokens

```dart
// civic_tokens.dart (excerpt)
abstract class CivicColors {
  // Brand
  static const ink           = Color(0xFF1C1C2E);
  static const paper         = Color(0xFFF5F1E8);
  static const civicGold     = Color(0xFFD4870F);
  static const alertRed      = Color(0xFFB52A2A);
  static const verifiedGreen = Color(0xFF1E6B3A);
  static const muted         = Color(0xFF6B6B7A);
  static const surface       = Color(0xFFFFFFFF);
  static const divider       = Color(0xFFE0DDD6);

  // Pillar accents
  static const vaultBlue     = Color(0xFF1A3D6B);
  static const ledgerGreen   = Color(0xFF1E4D38);
  static const warRoomAmber  = Color(0xFF8B3A0F);
  static const academyTeal   = Color(0xFF1A5C68);

  // Severity
  static const sevCritical   = Color(0xFFB52A2A);
  static const sevHigh       = Color(0xFF8B3A0F);
  static const sevMedium     = Color(0xFFD4870F);
  static const sevLow        = Color(0xFF1A5C68);

  // Dark mode overrides (see §14)
  static const inkDark        = Color(0xFFF0EDE4);
  static const paperDark      = Color(0xFF14141F);
  static const surfaceDark    = Color(0xFF1F1F2E);
  static const dividerDark    = Color(0xFF2C2C3E);
}
```

### 3.2 Typography Tokens

**Type scale — mobile-optimized**

```
Font families:
  Display:   Mukta (Google Fonts) — loaded for Latin + Devanagari
  Body:      Noto Sans — base; swap to Noto Sans Devanagari/Tamil/Telugu
             at runtime based on device locale (§13)
  Technical: JetBrains Mono — hash IDs, case numbers, forensic data

Scale (px → sp on Android, pt on iOS):
  displayXL   Mukta Bold     32sp   tracking: -0.02em   Case headings, splash
  displayL    Mukta Bold     26sp   tracking: -0.01em   Pillar masthead labels
  displayM    Mukta SemiBold 22sp   tracking: 0         Section headers
  headingL    Noto Sans Bold 18sp   tracking: 0         Card titles
  headingM    Noto Sans Bold 16sp   tracking: 0         List item primaries
  bodyL       Noto Sans Reg  16sp   tracking: 0         Primary body text
  bodyM       Noto Sans Reg  14sp   tracking: 0         Secondary body, descriptions
  bodyS       Noto Sans Reg  12sp   tracking: 0.01em    Captions, timestamps
  labelL      Noto Sans Med  13sp   tracking: 0.02em    Button labels, tags
  labelM      Noto Sans Med  11sp   tracking: 0.04em    Category chips, metadata
  mono        JBMono Reg     13sp   tracking: 0         Hash IDs, case numbers
  monoSM      JBMono Reg     11sp   tracking: 0         Evidence chain entries
```

### 3.3 Spacing Tokens

4px base unit. No half-pixels, no arbitrary values.

```dart
abstract class CivicSpacing {
  static const xs  =  4.0;   // Icon padding, chip internal
  static const sm  =  8.0;   // Between related elements
  static const md  = 12.0;   // Card internal padding (compact)
  static const lg  = 16.0;   // Standard screen edge margin
  static const xl  = 24.0;   // Between sections
  static const xxl = 32.0;   // Major section separation
  static const hug = 48.0;   // Large tap target, FAB clearance
  static const hero= 64.0;   // Splash, onboarding hero height
}
```

### 3.4 Elevation & Shadow Tokens

Deliberately restrained — documents sit on a surface, they don't float above it.

```dart
abstract class CivicElevation {
  // Light mode shadows — warm ink tint, not cool grey
  static const card   = BoxShadow(color: Color(0x141C1C2E), blurRadius: 4,  offset: Offset(0, 2));
  static const modal  = BoxShadow(color: Color(0x281C1C2E), blurRadius: 16, offset: Offset(0, 8));
  static const nav    = BoxShadow(color: Color(0x1E1C1C2E), blurRadius: 8,  offset: Offset(0, -2));
  // No elevation-1 equivalent — flat cards on paper background
}
```

### 3.5 Border Radius Tokens

The app is not rounded. Civic documents don't have soft corners. Most components are sharp or very slightly rounded.

```dart
abstract class CivicRadius {
  static const sharp    =  0.0;   // Masthead bars, severity bands, dividers
  static const subtle   =  3.0;   // Cards, modals, inputs
  static const chip     =  4.0;   // Category chips, karma badges
  static const button   =  6.0;   // Primary buttons
  static const avatar   = 50.0;   // Karma ring avatar (circular)
}
```

### 3.6 Duration & Easing Tokens

```dart
abstract class CivicMotion {
  static const quick   = Duration(milliseconds: 150);  // State feedback (tap)
  static const standard= Duration(milliseconds: 280);  // Screen transitions
  static const emphasis= Duration(milliseconds: 400);  // Onboarding reveals
  static const easeOut = Curves.easeOut;               // Most transitions
  static const spring  = Curves.elasticOut;            // Karma level-up (restrained)
  // No bounce, no physics springs in error or warning states
}
```

---

## 4. Component Library

Components are organized by scope: foundational → shared → pillar-specific. Only shared components are documented here; pillar-specific ones appear in their pillar section.

### 4.1 PillarMasthead

The signature element. Takes `PillarTheme` enum and renders the appropriate document-type header.

```
┌──────────────────────────────────────────────────────┐
│ [ICON] [PILLAR NAME]        [CONTEXTUAL META]  [CTA] │ ← height: 56dp
│ [DOCUMENT-TYPE SUBTITLE BAR]                         │ ← height: 20dp
└──────────────────────────────────────────────────────┘

Props:
  pillar: PillarTheme (vault | ledger | warRoom | academy)
  contextMeta: String? (edition #, case ID, chapter, username)
  onAction: VoidCallback?
  connectionStatus: SyncStatus (live | cached | queued | offline)

Vault instance:
  Background: Vault Blue #1A3D6B
  Icon: 🔒 (lock, 20dp)
  Title: "THE VAULT" — Mukta Bold, white, tracked +0.08em
  Subtitle bar: solid black (#000000, 18dp height)
    "████ ████ ████ PRIVATE ████ ████" — pseudo-redaction marks
  CTA: New conversation icon

Ledger instance:
  Background: Ledger Green #1E4D38
  Title: "THE DAILY LEDGER" — Mukta Bold, white, full-width centered
  Subtitle bar: same green, 1dp lighter tint
    "EDITION {n} · {PIN_CODE} · {DISTRICT}" — Noto Sans Reg 11sp, muted white
  Rule: 1.5dp white horizontal line below title (broadsheet masthead rule)
  CTA: Compose post icon

War Room instance:
  Background: Ink #1C1C2E
  Severity band: 8dp strip at top, color = current highest open severity
  Title: "▌WAR ROOM▐" — JetBrains Mono Bold, white, 18sp
  Subtitle: "CASE #{id} · {SEVERITY LABEL} · ANALYST: @{username}" — mono 11sp
  CTA: File new case icon

Academy instance:
  Background: Academy Teal #1A5C68
  Title: "THE ACADEMY" — Mukta Bold, white
  Rule: 1dp white rule, full width
  Subtitle: "Chapter {n} · {Domain} · Module {current}/{total}" — Noto Sans 11sp
  Progress bar: 3dp strip, Civic Gold fill, below subtitle
  CTA: Search syllabus icon
```

### 4.2 CivicCard

Primary content container. Used for Ledger posts, War Room cases, Academy modules.

```
┌──────────────────────────────────────────────────────────┐
│ [CategoryChip]                         [Timestamp]       │ ← 8dp padding top
│                                                          │
│ [Title — headingM, Ink, 2-line max]                      │
│                                                          │
│ [Body — bodyM, Ink at 80% opacity, 3-line max]           │
│                                                          │
│ [MetaRow: location · author_karma_tier · pillar badge]   │
│ ──────────────────────────────────────────────────────── │ ← 1dp divider
│ [▲ Vote]  [💬 Replies]  [⚑ Flag]         [→ Share]       │ ← action row
└──────────────────────────────────────────────────────────┘

Variants:
  standard   — full card as above
  compact    — title + meta only, no body preview (used in War Room case list)
  featured   — 2x card height, category accent bar on left edge (4dp, pillar color)
  offline    — full card, amber offline badge top-right corner

Background: Surface (#FFFFFF)
Border: 1dp Divider (#E0DDD6) on all sides
Radius: 3dp (CivicRadius.subtle)
Shadow: CivicElevation.card
Tap state: Paper (#F5F1E8) background fill, 150ms transition
```

### 4.3 KarmaBadge

Displays a user's karma tier, shown on posts, case assignments, and profile.

```
Karma tiers:

  Score 0–49      ○  Citizen        Outline ring, muted
  Score 50–99     ◐  Contributor    Half-fill ring, Civic Gold
  Score 100–149   ●  Validator      Full ring, Civic Gold
  Score 150–499   ★  Analyst        Star ring, Civic Gold + Vault Blue border
  Score 500+      ⬡  Council        Hexagon ring, Ink fill, Civic Gold glyph

Badge renders as: [ring-icon] [score] on long form
                  [ring-icon] only on compact (avatar, list)

Color of ring: Pillar accent of the action that earned the most karma
```

### 4.4 CategoryChip

Used in the Ledger to tag post categories.

```
┌─────────────────────────┐
│  # CIVIC INFRA          │  11sp Noto Sans Medium, tracked +0.04em
└─────────────────────────┘

Background: pillar accent at 12% opacity
Border: 1dp pillar accent
Radius: 4dp
Height: 24dp
Padding: 4dp vertical, 10dp horizontal

Categories → colors:
  #CivicInfrastructure  Ledger Green
  #StudentRights        Academy Teal
  #ConsumerWatch        War Room Amber
  #SatireAndCulture     Civic Gold
  #BreakingLocal        Alert Red (used sparingly)
```

### 4.5 SyncStatusBar

Non-intrusive connectivity indicator. Appears below the masthead when not LIVE.

```
States:
  LIVE      — no bar (invisible, default)
  CACHED    — 2dp amber (#D4870F) strip + "Showing saved content" in monoSM
  QUEUED    — 2dp amber strip + "Sending when reconnected"
  OFFLINE   — 3dp Alert Red strip + "Offline — changes saved locally"

Tap to expand: shows last-sync timestamp + pending queue count
```

### 4.6 VoiceInput

Used in War Room intake and Academy accessibility mode.

```
States:
  IDLE      [🎤 Hold to speak]  — muted border, Noto Sans bodyM
  RECORDING [████ 0:12  ■ Stop] — Alert Red pulsing border (2dp, 1.5s period)
  PROCESSING [◎ Transcribing…]  — amber shimmer animation on text area
  DONE      [✓ Transcript ready — tap to review]

The pulsing border is the only animation that uses a repeating loop.
It communicates active recording without distracting from the user's
focus on what they're saying (PRD §7.3 enhancement 4 — trauma-aware UX).
```

### 4.7 PrimaryButton / SecondaryButton / DestructiveButton

```
PrimaryButton:
  Background: Civic Gold #D4870F
  Text: Surface white, labelL (13sp, +0.02em)
  Radius: 6dp
  Height: 48dp (minimum tap target)
  Disabled: 40% opacity, no tap feedback

SecondaryButton:
  Background: transparent
  Border: 1.5dp Ink #1C1C2E
  Text: Ink, labelL
  Same size as primary

DestructiveButton:
  Background: Alert Red #B52A2A
  Text: Surface white, labelL
  Same size. Requires a confirmation BottomSheet before action executes.
  Never used for first-pass actions in War Room or Vault — always confirmation-gated.

Ghost (icon-only):
  No background, no border
  Icon: 24dp, Muted #6B6B7A → Ink on hover
  Tap area: 48dp × 48dp minimum
```

### 4.8 InputField

```
┌──────────────────────────────────────────────────────┐
│ Label (bodyS, Muted, above field)                    │
│┌────────────────────────────────────────────────────┐│
││ Placeholder / value (bodyL, Ink)                   ││
│└────────────────────────────────────────────────────┘│
│ Helper text or error (bodyS, Muted | Alert Red)      │
└──────────────────────────────────────────────────────┘

Default border: 1dp Divider
Focus border: 1.5dp Ink
Error border: 1.5dp Alert Red
Filled border: 1.5dp Verified Emerald
Background: Paper #F5F1E8 (not white — reduces glare on bright-day outdoor use)
Radius: 3dp
Height: 52dp (generous tap target for touch accuracy)
```

### 4.9 BottomSheet (Confirmation / Context Menu)

```
Handle bar: 4dp × 36dp, Divider color, 2dp radius, centered, 8dp from top
Background: Surface #FFFFFF
Radius on top corners: 16dp
Shadow: CivicElevation.modal

Always used for:
- Destructive action confirmation ("Delete draft?" "Withdraw case?")
- File case — severity pre-triage question
- Ledger post — category selection
- Vault — Connection Request prompt
```

---

## 5. App Shell & Navigation Architecture

### 5.1 Bottom Navigation Bar

Five destinations. Bottom nav is the platform's primary wayfinding — thumb-accessible, always visible except in fullscreen video (Academy) and active War Room case view (distraction-free).

```
┌────────────────────────────────────────────────────────────────┐
│                      Current Pillar Screen                      │
│                                                                 │
│                                                                 │
│                                                                 │
│                                                                 │
│                                                                 │
├────────────────────────────────────────────────────────────────┤
│ ─────────────────────────────────────────────────────────────  │ ← nav shadow
│  [🔒]       [📰]       [⬡]       [🛡]       [🎓]              │
│  Vault    Ledger    Commons   War Room  Academy               │
│                      (Karma                                    │
│                       Hub)                                     │
└────────────────────────────────────────────────────────────────┘

Nav bar height: 64dp + safe area inset
Active icon: Pillar accent color fill (solid)
Inactive icon: Muted #6B6B7A, outline
Label: labelM (11sp), shown always (not icon-only — aids learnability)
Active indicator: 3dp Civic Gold underline above icon, not a pill background
Badge: War Room unread cases, Ledger review queue items

The "Commons" (center) is the Karma Hub — the one screen that sits above
all four pillars. Its icon is the platform logo glyph.
```

### 5.2 Screen Hierarchy

```
App Root
├── Onboarding (not navigable once complete)
│   ├── Language Select
│   ├── OTP Registration
│   ├── DPDP Consent
│   └── Username Setup
│
├── The Vault  [Tab 1]
│   ├── Conversation List
│   ├── Conversation Detail (individual)
│   └── Contact Request Queue
│
├── The Daily Ledger  [Tab 2]
│   ├── Feed (default: user's pin code)
│   ├── Post Detail
│   ├── Compose Post
│   └── Explore Nearby (expanded radius)
│
├── The Commons  [Tab 3 — center]
│   ├── Karma Dashboard (own profile)
│   ├── Platform Transparency Log (public)
│   └── Settings
│
├── The War Room  [Tab 4]
│   ├── Case List (victim: own cases | analyst: assigned queue)
│   ├── Case Detail / Investigation View
│   ├── File New Case (intake flow)
│   └── Analyst Vetting Gauntlet (first launch for eligible users)
│
└── The Academy  [Tab 5]
    ├── Syllabus Tree (domain browse)
    ├── Module View (video + sandbox + resources)
    ├── My Progress
    └── Study Groups (pin-code matched)
```

### 5.3 Navigation Transitions

| Transition type | Motion | Duration |
|---|---|---|
| Tab switch | Horizontal slide, same direction as tab position | 280ms easeOut |
| Push (list → detail) | Slide up from bottom | 280ms easeOut |
| Pop (back) | Slide down | 250ms easeOut |
| Modal BottomSheet | Slide up from bottom edge | 300ms easeOut |
| Fullscreen video | Fade to black, then content | 400ms easeOut |
| Onboarding steps | Horizontal slide forward | 350ms easeOut |

No zoom transitions. No shared-element transitions for Phase 1 (complexity vs. value tradeoff for Tier-3 devices).

---

## 6. Pillar 1 — The Vault: UX Design

### 6.1 Design Intent

The Vault must feel like the most trustworthy space in the app. No noise. No community features. No karma display. You are alone with the people you have chosen to let in. The visual register is close-hold: slightly darker, slightly quieter than the rest of the app.

### 6.2 Conversation List Screen

```
┌──────────────────────────────────────────────────────┐
│ ██████  THE VAULT     [CLASSIFIED]  @rekha_k  🔒     │ ← Vault masthead
│ ████ ████ █████ PRIVATE ███ ████ ████ ████ ██████    │ ← redaction bar
├──────────────────────────────────────────────────────┤
│ PENDING REQUESTS (2)                                  │ ← collapsible section
│ ┌──────────────────────────────────────────────────┐ │
│ │ @anonymous_X wants to connect            [Accept]│ │
│ │ @civic_helper_99 wants to connect        [Accept]│ │
│ └──────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────┤
│ CONVERSATIONS                                         │
│ ┌──────────────────────────────────────────────────┐ │
│ │ ● @arjun_r34        Preview ciphertext ···       │ │ ← ● = unread
│ │             [end-to-end encrypted]    Wed 11:42  │ │
│ ├──────────────────────────────────────────────────┤ │
│ │ ○ @vikram_csec      Preview ciphertext ···       │ │
│ │             [end-to-end encrypted]   Mon 08:17   │ │
│ └──────────────────────────────────────────────────┘ │
│                                                       │
│                                          [+] New      │ ← FAB, Vault Blue
└──────────────────────────────────────────────────────┘

Key UX decisions:
- Message preview is always "[end-to-end encrypted]" — never a plaintext preview
  even on the device. This prevents shoulder-surfing exposure on a shared family
  device (Priya persona, PRD §3).
- No "online" / "last seen" for any contact, ever (PRD FR-V3: status not shared
  without accepted connection).
- Username shown as the only identifier. No avatar, no profile photo.
- Long-press on any conversation → BottomSheet with: Mute / Export local backup /
  Delete conversation / Report abuse (which opens a separate voluntary report flow)
```

### 6.3 Conversation Detail Screen

```
┌──────────────────────────────────────────────────────┐
│ ← Back   @arjun_r34          🔒 E2EE       ⋮ More   │ ← simplified header
├──────────────────────────────────────────────────────┤
│                                                       │
│           [Session started. Keys verified.]           │ ← safety number prompt
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │ I need to share something about the extortion │    │ ← received message
│  │                              Wed 11:42  ✓✓   │    │ ← ✓✓ = delivered+read
│  └──────────────────────────────────────────────┘    │
│                                                       │
│    ┌──────────────────────────────────────────────┐  │
│    │ I understand. Use the War Room to file        │  │ ← sent message
│    │ securely. I can't see it but can help.        │  │
│    │                              Wed 11:43  ✓    │  │ ← ✓ = delivered only
│    └──────────────────────────────────────────────┘  │
│                                                       │
├──────────────────────────────────────────────────────┤
│ [📎 Attach]  [Type a message…]              [🎤] [→] │ ← input bar, 52dp
└──────────────────────────────────────────────────────┘

Received bubble: Surface white, left-aligned, 3dp radius, Vault Blue 3dp left bar
Sent bubble: Vault Blue bg, right-aligned, white text, 3dp radius
Timestamps: monoSM, Muted
Read receipts: ✓ (sent), ✓✓ (delivered), ✓✓ (teal = read) — same convention as Signal
Message queue indicator: amber "⏳ Sending when online" below queued messages
```

### 6.4 Connection Request Gate

```
┌──────────────────────────────────────────────────────┐
│                   Connection Request                  │
│                                                       │
│    ⬡ @vikram_csec                                    │
│    Karma tier: Analyst (★)                            │
│                                                       │
│    "Hi — I'm an OSINT volunteer. Reached out via     │
│     The Daily Ledger about your RTI post."            │
│                                                       │
│    If you accept:                                     │
│    · They can send you messages and media             │
│    · They can see when you have read messages         │
│    · You can block them at any time                   │
│                                                       │
│    If you decline: they are not notified why.         │
│                                                       │
│  [Decline — no notification]   [Accept connection]   │
└──────────────────────────────────────────────────────┘

Design rationale: The explainer copy ("If you accept/decline") is required —
the Request Gate is central to Vault's privacy model (PRD FR-V3) and many
users will not have encountered this pattern before.
"No notification" on decline is a privacy feature, stated explicitly.
```

### 6.5 Vault Security Settings (⋮ More menu)

```
Vault Settings
───────────────────────────────────────────────
Security
  [>] Change PIN
  [>] Set up Duress PIN
      "Opens an empty vault when entered"
  [>] Verify safety numbers with contact
  [>] Disguised app icon
      Appears as "Calculator" on home screen

Conversations
  [>] Message auto-delete: Off / 7 days / 30 days
  [>] Export encrypted local backup

Danger Zone (red section, collapsed by default)
  [>] Delete all conversations
  [>] Wipe device keys (logs you out of all sessions)
```

---

## 7. Pillar 2 — The Daily Ledger: UX Design

### 7.1 Design Intent

The Ledger should feel like the front page of a trusted local newspaper, not a social media feed. Chronological order. Structural categories. No algorithmic surprises. The masthead carries the date and edition — a newspaper says "this is the record for today"; so does the Ledger.

### 7.2 Feed Screen

```
┌──────────────────────────────────────────────────────┐
│      THE DAILY LEDGER · EDITION 412 · 800001         │ ← Ledger masthead
│  ══════════════════════════════════════════════════  │ ← rule
├──────────────────────────────────────────────────────┤
│ [All] [#Civic] [#Students] [#Consumer] [#Satire] [+] │ ← category filter chips
├──────────────────────────────────────────────────────┤
│                                                       │
│ ┌────────────────────────────────────────────────┐   │
│ │ [⬛ #CIVIC INFRA]                    4 hrs ago │   │ ← CategoryChip + time
│ │ Municipal contractor stopped work on Boring   │   │
│ │ Road drainage — third time this season        │   │
│ │ Patna · Sadar Constituency                    │   │
│ │ ──────────────────────────────────────────── │   │
│ │ ▲ 48  💬 12  ⚑ Flag      [✓ Verified — 3/3] │   │ ← verified badge
│ └────────────────────────────────────────────────┘   │
│                                                       │
│ ┌────────────────────────────────────────────────┐   │
│ │ [🟡 #SATIRE]                          6 hrs ago │   │
│ │ "Local councillor discovers pothole map was   │   │
│ │  actually a bingo card all along"             │   │
│ │ 800001 · ✏ @civic_memer                       │   │
│ │ ──────────────────────────────────────────── │   │
│ │ ▲ 204  💬 38  ⚑ Flag                          │   │
│ └────────────────────────────────────────────────┘   │
│                                                       │
│ [~ 3 more posts in Peer Review — tap to preview ~]   │ ← shadow queue indicator
│                                                       │
│ [Load older posts]                                    │ ← pagination, NOT infinite scroll
│                                           [✏ Compose]│ ← FAB, Ledger Green
└──────────────────────────────────────────────────────┘

Key UX decisions:
- Pagination not infinite scroll. Infinite scroll is an engagement-maximization
  pattern that contradicts the platform's explicit anti-algorithmic stance (PRD §1.1B).
  Pagination makes the reader aware they are choosing to continue.
- Shadow Queue posts shown as a teaser strip but not as full cards — transparent
  about the moderation process without giving unreviewed content equal weight.
- [✓ Verified — 3/3] badge: all 3 Peer Review Gate reviewers approved this post.
  Partial: [◑ 1/3] or [◑ 2/3]. No badge = not yet reviewed.
```

### 7.3 Compose Post Screen

```
┌──────────────────────────────────────────────────────┐
│ ← Cancel          New Post              [Preview]    │
├──────────────────────────────────────────────────────┤
│ Category *                                            │
│ ┌──────────────────────────────────────────────────┐ │
│ │ # CIVIC INFRASTRUCTURE                     ▼     │ │
│ └──────────────────────────────────────────────────┘ │
│ Pin Code *                                            │
│ ┌────────────────────┐  [Use my location]            │
│ │ 800001             │                               │
│ └────────────────────┘                               │
│ Headline *                                            │
│ ┌──────────────────────────────────────────────────┐ │
│ │ State the issue plainly                          │ │
│ └──────────────────────────────────────────────────┘ │
│ Details                                               │
│ ┌──────────────────────────────────────────────────┐ │
│ │ What happened, when, and what evidence you have  │ │
│ │                                                  │ │
│ └──────────────────────────────────────────────────┘ │
│ Evidence (optional)                                   │
│ [📷 Add photo]  [📎 Add document]  [🎤 Voice note]   │
│                                                       │
│ ℹ Your karma tier is Contributor (◐). This post       │
│   goes to Peer Review Gate before publishing.        │
│                         [Publish — send to review]   │
└──────────────────────────────────────────────────────┘

Karma state messaging:
  ≥100 karma: "Your post publishes immediately."
  <100 karma: "Goes to Peer Review Gate — usually under 2 hours."
  New account (<96h): "Goes to Shadow Queue — reviewed by the community."
  All states: non-alarming, informative. Never "Your post is blocked."
```

### 7.4 Post Detail Screen

```
┌──────────────────────────────────────────────────────┐
│ ← Back                              ⚑ Flag   ↗ Share│
├──────────────────────────────────────────────────────┤
│ [#CIVIC INFRA]        Patna · Sadar · 800001         │
│                                                       │
│ Municipal contractor stopped work on Boring Road     │
│ drainage — third time this season                    │
│ — 22sp Mukta SemiBold                               │
│                                                       │
│ ──────────────────────────────────────────────────── │
│ Posted by ★ Analyst-tier · Wed 14:03                 │
│ [✓ Peer Review Gate: 3/3 approved · Wed 16:41]       │
│ ──────────────────────────────────────────────────── │
│                                                       │
│ Drainage work on Boring Road has stopped for the     │
│ third consecutive week despite an active work order  │
│ (RTI ref #BMP/2026/4821, attached). The contractor   │
│ was last seen on-site June 28.                       │
│                                                       │
│ [Evidence: RTI_ref_4821.pdf →]                       │
│ [Photo: site_photo_jun28.jpg →]                      │
│                                                       │
│ ──────────────────────────────────────────────────── │
│ ▲ 48   ▼ 3                     [💬 12 Replies ▼]     │
└──────────────────────────────────────────────────────┘
```

---

## 8. Pillar 3 — The War Room: UX Design

### 8.1 Design Intent

The War Room is the pillar where a real person is in real distress. The design must:
1. Be calm and directive — not clinical, not frightening
2. Give the user constant control (pause, withdraw, choose next step)
3. Never feel like a bureaucratic form — every screen should feel like talking to a knowledgeable, careful friend

The dossier aesthetic establishes authority and seriousness without coldness.

### 8.2 Case List Screen — Victim View

```
┌──────────────────────────────────────────────────────┐
│ ▌WAR ROOM▐  YOUR CASES        OSINT UNIT — SECURE   │ ← War Room masthead
│ ──────────────────────────────────────────────────── │
├──────────────────────────────────────────────────────┤
│                                                       │
│ ┌──────────────────────────────────────────────────┐ │
│ │ CASE #CC-0047                                    │ │ ← JetBrains Mono
│ │ Digital extortion — photo leak threat             │ │
│ │ ▌HIGH SEVERITY                                   │ │ ← Severity band (amber)
│ │ Filed: 3 Jul 2026 · Status: UNDER INVESTIGATION  │ │
│ │ 2 analysts assigned · Est. report: 48 hrs        │ │
│ │                                    [View case →] │ │
│ └──────────────────────────────────────────────────┘ │
│                                                       │
│ ┌──────────────────────────────────────────────────┐ │
│ │ CASE #CC-0031                                    │ │
│ │ Fake social media profile — identity theft        │ │
│ │ ▌MEDIUM SEVERITY                                 │ │ ← amber-gold severity
│ │ Filed: 18 Jun 2026 · Status: REPORT READY        │ │
│ │                           [Download report →]    │ │
│ └──────────────────────────────────────────────────┘ │
│                                                       │
│                              [+ File a new case]      │ ← Civic Gold button
└──────────────────────────────────────────────────────┘
```

### 8.3 New Case Intake Flow (Trauma-Aware)

This is a multi-step flow, not a single form. Each step is one screen — never overwhelming the user with everything at once (PRD §7.3, enhancement 4).

```
Step 1 of 5 — SITUATION OVERVIEW
──────────────────────────────────────────────────────
  ← Close                                    [1●2○3○4○5○]

  "You're in the right place."

  What best describes your situation?

  [○] I am being blackmailed or extorted
  [○] Someone is threatening to share intimate images
  [○] I found a fake profile using my identity
  [○] I received threatening or abusive messages
  [○] I need help tracing who is harassing me
  [○] Something else

  Nothing you share here is visible to anyone except
  the War Room analysts assigned to your case.

                                           [Continue →]

──────────────────────────────────────────────────────

Step 2 of 5 — YOUR SITUATION
──────────────────────────────────────────────────────
  [○ Back]                                   [1✓●2●3○4○5○]

  Describe what happened — in your own words.
  There is no wrong way to say it.

  ┌────────────────────────────────────────────────┐
  │                                                │
  │                                                │
  │                                    [🎤 Dictate]│ ← voice input opt
  └────────────────────────────────────────────────┘

  Or record a voice note instead:
  [🎤 Hold to record]

  You can stop and return to this at any time.
                   [Save & pause]    [Continue →]

──────────────────────────────────────────────────────

Step 3 of 5 — EVIDENCE
──────────────────────────────────────────────────────
  [○ Back]                                   [1✓2✓●3●4○5○]

  Share anything that might help the analysts.
  Screenshots, messages, usernames, links — anything.

  ⚠ Evidence is encrypted before leaving your device.
    Only assigned analysts can view it.

  [📸 Add screenshots]  [🔗 Add links/usernames]
  [📁 Add files]        [🎤 Describe verbally]

  Added: 3 screenshots, 1 username
  [× screenshot_01.jpg]
  [× screenshot_02.jpg]
  [× screenshot_03.jpg]
  [× @fake_account_123]

                   [Save & pause]    [Continue →]

──────────────────────────────────────────────────────

Step 4 of 5 — URGENCY
──────────────────────────────────────────────────────
  [○ Back]                                   [1✓2✓3✓●4●5○]

  How urgent is this?

  [○] There is an immediate threat or deadline (< 24 hrs)
  [○] This needs attention soon (this week)
  [○] No immediate deadline — take the time needed

  Your safety matters more than the case timeline.
  If you feel you are in immediate physical danger,
  please contact emergency services first.

                                           [Continue →]

──────────────────────────────────────────────────────

Step 5 of 5 — CONSENT & SUBMIT
──────────────────────────────────────────────────────
  [○ Back]                                   [1✓2✓3✓4✓●5●]

  Before we assign analysts:

  ☑ I understand this service is provided by volunteer
    analysts and is not a substitute for legal advice.

  ☑ I agree that the platform may refer my case to
    legal aid partners if analysts recommend it.

  ☐ I would like to be notified if I can publish an
    anonymized version of my case to the Daily Ledger
    to warn others (optional — you decide later).

  Your case is assigned a random number.
  Analysts see only that number and your evidence —
  not your username or karma profile.

                            [Submit case securely →]   ← Civic Gold
──────────────────────────────────────────────────────
```

### 8.4 Active Case View — Victim

```
┌──────────────────────────────────────────────────────┐
│ ▌WAR ROOM▐  CASE #CC-0047  ⬛ HIGH  2 ANALYSTS       │
├──────────────────────────────────────────────────────┤
│ STATUS TIMELINE                                       │
│                                                       │
│ ✓ Case filed              3 Jul 11:32                 │
│ ✓ Auto-triage complete    3 Jul 11:33  HIGH severity  │
│ ✓ Analysts assigned       3 Jul 12:04  2 assigned     │
│ ◎ Investigation ongoing   Est. report: 5 Jul          │
│ ○ Report ready                                        │
│ ○ Choose next step                                    │
│                                                       │
│ [You can pause or withdraw this case at any time]     │ ← always visible
│                                                       │
│ ANALYST UPDATE  (3 Jul 14:20)                         │
│ ┌──────────────────────────────────────────────────┐ │
│ │ "We have identified the origin platform of the   │ │
│ │  account. Working on metadata extraction."       │ │
│ │                           ◎ In progress          │ │
│ └──────────────────────────────────────────────────┘ │
│                                                       │
│ [Pause case]         [Add more evidence]   [Withdraw] │
└──────────────────────────────────────────────────────┘
```

### 8.5 Verified Intel Report — Final Screen

```
┌──────────────────────────────────────────────────────┐
│ ▌WAR ROOM▐  CASE #CC-0047  ✓ CLOSED  REPORT READY   │
├──────────────────────────────────────────────────────┤
│  VERIFIED INTELLIGENCE REPORT                         │
│  Civic Commons OSINT Unit                            │
│  Case #CC-0047 · Finalized 5 Jul 2026               │
│  HMAC Signature: 9f3a...b221  [✓ Verified]           │ ← mono font, integrity
│ ────────────────────────────────────────────────────  │
│  FINDING SUMMARY                                      │
│  The account @fake_account_123 was created from a    │
│  Reliance Jio IP cluster in Bihar on 1 Jun 2026.    │
│  Image metadata trace confirms…                      │
│ ────────────────────────────────────────────────────  │
│  WHAT YOU CAN DO WITH THIS REPORT                    │
│  [🏛 Send to legal aid partner →]                    │
│  [📰 Publish anonymized version to Daily Ledger →]   │
│  [💾 Save encrypted copy to device]                  │
│  [🔒 Keep private — case closed]                     │
│                                                       │
│  You are in control of what happens next.            │
└──────────────────────────────────────────────────────┘
```

---

## 9. Pillar 4 — The Academy: UX Design

### 9.1 Design Intent

The Academy is organized like a proper syllabus — not an algorithm. The user navigates the curriculum; the curriculum does not navigate the user. Clean hierarchy. Reading-friendly. Optimized for low-data use and bright outdoor light (Priya in a Tier-3 town reading on a shared phone).

### 9.2 Syllabus Tree Screen

```
┌──────────────────────────────────────────────────────┐
│  THE ACADEMY  ──────────────────────────────────────  │ ← masthead
│  Browse Curriculum · 847 modules · 12 languages      │
├──────────────────────────────────────────────────────┤
│ [🔍 Search any subject…]                             │
├──────────────────────────────────────────────────────┤
│                                                       │
│  MY PROGRESS                                          │
│  Mathematics ▓▓▓▓▓▓▓▓░░ 78%  (Module 42 / 54)        │ ← progress bars
│  [Continue: Trigonometry II →]                        │
│                                                       │
│  BROWSE BY DOMAIN                                     │
│                                                       │
│  ┌────────────────────┐  ┌────────────────────────┐  │
│  │ 📐 Mathematics      │  │ 🔬 Science             │  │
│  │ 54 modules         │  │ 67 modules             │  │
│  └────────────────────┘  └────────────────────────┘  │
│  ┌────────────────────┐  ┌────────────────────────┐  │
│  │ 📖 Literature &    │  │ 💻 Technology          │  │
│  │    Languages       │  │ 38 modules             │  │
│  │ 48 modules         │  │                        │  │
│  └────────────────────┘  └────────────────────────┘  │
│  ┌────────────────────┐  ┌────────────────────────┐  │
│  │ ⚖ Civic Education  │  │ 🌿 Environment         │  │
│  │ 22 modules         │  │ 19 modules             │  │
│  └────────────────────┘  └────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### 9.3 Module View Screen

```
┌──────────────────────────────────────────────────────┐
│  THE ACADEMY  ─── Mathematics › Trigonometry II ─── │ ← breadcrumb
│  Module 42/54  ████████████████████░░░ 77% complete  │ ← progress
├──────────────────────────────────────────────────────┤
│                                                       │
│  [VIDEO ROOM ▼]                                       │ ← expandable tab
│  ┌──────────────────────────────────────────────┐    │
│  │                                              │    │
│  │         ▶  [Lecture: Sine Rule — 24 min]    │    │ ← no sidebar
│  │                                              │    │ ← no autoplay
│  │  [↓ Download for offline — 48 MB]            │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  [GUTENBERG ARCHIVE ▼]                               │
│  · NCERT Mathematics Textbook XI — Chapter 3 (OER)   │
│    License: NCERT Open License · [Open →]            │
│  · Introduction to Trigonometry (CC BY 4.0)          │
│    [Open →]                                          │
│                                                       │
│  [SANDBOX ▼] — Community notes for this module       │
│  ┌──────────────────────────────────────────────┐    │
│  │ The sine rule shortcut for state board exams │    │
│  │ (contributed by ★ priya_m · 14 upvotes)      │    │
│  │ [Edit / contribute ✏]                        │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  [← Previous module]         [Next module: Cosine →] │
└──────────────────────────────────────────────────────┘
```

---

## 10. Cross-Pillar Screens

### 10.1 The Commons — Karma Hub

```
┌──────────────────────────────────────────────────────┐
│                   THE COMMONS                         │ ← centered logo glyph
│                   @vikram_csec                        │
│                   ⬡ Analyst · 247 karma              │
├──────────────────────────────────────────────────────┤
│ KARMA BREAKDOWN                                       │
│ ┌─────────────────────────────────────────────────┐  │
│ │  Vault           0   (messaging is private)     │  │
│ │  Ledger          ▓▓▓▓░  +68  (12 verified posts)│  │
│ │  War Room        ▓▓▓▓▓▓▓▓▓  +179  (11 cases)   │  │
│ │  Academy         ▓  +8  (4 modules, 2 sandbox)  │  │
│ └─────────────────────────────────────────────────┘  │
│ NEXT TIER: Council (⬡)    253 karma needed            │
│ ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░ 49%                            │
├──────────────────────────────────────────────────────┤
│ PLATFORM TRANSPARENCY                                 │
│ Last 30 days: 0 government data requests received     │
│ Platform uptime: 99.97%                               │
│ [Full transparency log →]                            │
├──────────────────────────────────────────────────────┤
│ [Settings]  [Connectivity: LIVE ●]  [Sign out]        │
└──────────────────────────────────────────────────────┘
```

### 10.2 Onboarding Flow

```
Screen 1 — Language Select
──────────────────────────────────────────────────────
  [App logo, large]

  "Choose your language"
  (select a language to continue in it)

  [हिन्दी]  [English]  [বাংলা]  [తెలుగు]
  [தமிழ்]   [ਪੰਜਾਬੀ]   [ಕನ್ನಡ]   [More…]

  → sets device locale for all subsequent screens

Screen 2 — What This Is
──────────────────────────────────────────────────────
  [Four pillar icons, horizontal]

  One app. Four tools.

  🔒 The Vault — private messages, no data collected
  📰 The Ledger — local news, no algorithm
  🛡 The War Room — help if you are being threatened
  🎓 The Academy — free, structured learning

  [Continue →]

Screen 3 — Phone Verification + DPDP Consent
──────────────────────────────────────────────────────
  Your phone number is used only to prevent fake
  accounts. It is converted to a code immediately
  and never stored.

  [Read the full privacy notice (DPDP Act) →]

  ┌──────────────────────────────────────────────┐
  │ +91  ·  [Your phone number]                  │
  └──────────────────────────────────────────────┘

  ☑ I have read and agree to the privacy notice.
    (required by India's DPDP Act, 2023)

  [Send verification code →]

  Note: requires consent checkbox to be checked —
  not pre-checked. Compliant with DPDP Act §6.
```

---

## 11. Security-Sensitive UX Flows

### 11.1 Duress PIN Setup

```
Setting up Duress PIN
──────────────────────────────────────────────────────
  Your Vault has two PINs. Your real PIN opens your
  conversations. Your duress PIN opens an empty vault.

  Use the duress PIN if someone forces you to unlock
  your phone. They will see an empty vault and not
  know your real conversations exist.

  Step 1: Enter your REAL PIN (the one you use now)
  Step 2: Choose a new DURESS PIN (different from real)
  Step 3: Confirm duress PIN

  ⚠ Write down your real PIN somewhere safe. If you
    forget it, conversations cannot be recovered.

  [Set up duress PIN →]        [Not now]
```

### 11.2 Disguised Icon Mode

```
Disguised app icon
──────────────────────────────────────────────────────
  The app will appear as "Calculator" on your home
  screen. It will also function as a basic calculator.

  To open the real app: open "Calculator" and enter
  your PIN followed by the # key.

  [Enable disguised icon]      [Cancel]

  ℹ This does not hide app data from OS-level forensic
    tools. For high-risk situations, consult a digital
    security expert.
```

### 11.3 Safety Number Verification (Vault)

```
Verify safety numbers with @arjun_r34
──────────────────────────────────────────────────────
  Safety numbers confirm you are talking to the right
  person and that messages have not been tampered with.

  Your numbers:
  ┌──────────────────────────────────────────────────┐
  │ 04832 71920  38471 09234  17392 84710  23847 1029│
  │ — JetBrains Mono, 2-column layout, 4-digit groups│
  └──────────────────────────────────────────────────┘

  Compare these with @arjun_r34 in person or via
  another channel. If they match, your conversation
  is secure.

  [Mark as verified]    [Share my numbers]   [Cancel]
```

---

## 12. Offline & Low-Connectivity States

### 12.1 State System

Every screen has a defined behavior for each connectivity state. No screen should hard-fail or show a generic "No internet" wall.

| Screen | LIVE | CACHED | QUEUED | OFFLINE |
|---|---|---|---|---|
| Vault — Conversation List | Real-time | Shows local conversations, amber SyncStatusBar | Same as CACHED, unsent messages marked ⏳ | Same as QUEUED, compose still works |
| Vault — Compose | Sends immediately | Queues locally | Queues locally | Queues locally, user informed |
| Ledger Feed | Fresh posts | Last-synced posts, timestamp shown | Last-synced posts | Last-synced posts, compose works as draft |
| War Room Intake | Submit instantly | n/a (intake needs connection) | Submit queued | Cannot submit — amber notice + "Save draft locally" option |
| Academy Module | Live video | Cached modules only, live modules greyed out | — | Cached modules only |

### 12.2 Offline Banner Design

```
┌──────────────────────────────────────────────────────┐
│ ▌ Offline — changes saved locally. Reconnecting… ▌  │ ← 3dp Alert Red top
└──────────────────────────────────────────────────────┘
```
- 44dp full-width strip, below masthead, above content
- Dismiss-able with a swipe-down (reappears if still offline after 30 s)
- Never blocks content, never modal

### 12.3 Data-Cost Transparency (PRD §3, Priya persona)

```
Academy module download prompt:
──────────────────────────────────────────────────────
  Download "Trigonometry II" for offline use?

  Size: 48 MB (video 44 MB + notes 4 MB)
  At typical 4G rates: ~₹0.24 on most plans

  Download over:
  [📶 Any network]  [📡 Wi-Fi only (recommended)]

  [Download]     [Not now]
──────────────────────────────────────────────────────

Data-saver mode (in Settings):
  · Forces 360p video
  · Disables Vault heartbeat traffic obfuscation
  · Disables auto-download of media in Ledger cards
  · Shows data estimate before any download > 5 MB
```

---

## 13. Vernacular & Accessibility Design

### 13.1 Multi-Script Text Rendering

The device locale drives font selection, handled by the `VernacularTextTheme` class:

```dart
TextTheme vernacularTextTheme(Locale locale) {
  return switch (locale.languageCode) {
    'hi' || 'mr' || 'ne' => _buildTheme('NotoSansDevanagari'),
    'ta'                  => _buildTheme('NotoSansTamil'),
    'te'                  => _buildTheme('NotoSansTelugu'),
    'bn'                  => _buildTheme('NotoSansBengali'),
    'kn'                  => _buildTheme('NotoSansKannada'),
    'ml'                  => _buildTheme('NotoSansMalayalam'),
    'pa'                  => _buildTheme('NotoSansGurmukhi'),
    _                     => _buildTheme('NotoSans'),  // English + fallback
  };
}
```

Mukta (display font) covers Latin + Devanagari natively. For other scripts, the display font falls back to Noto Sans of that script — still clean but not the characterized Mukta style. This is an acceptable Phase 1 tradeoff; custom display variants per script are a Phase 4 design task.

### 13.2 Bidirectional Text

Urdu (RTL) support: `Directionality` widget wraps the app root, reads device locale. The navigation bar and masthead mirror horizontally. Card layouts use `TextDirection.rtl`. Phase 1 scope: detect and handle Urdu locale, mirror layout.

### 13.3 Accessibility Requirements (WCAG 2.1 AA)

| Requirement | Implementation |
|---|---|
| Minimum tap target 48×48dp | All interactive elements, enforced via lint rule |
| Focus ring on keyboard/switch nav | `FocusNode` with visible outline in Civic Gold |
| Screen reader (TalkBack / VoiceOver) | All icons have `Semantics(label:)` wrapper |
| Reduced motion | All animations check `MediaQuery.disableAnimations` |
| Voice input | War Room intake + Academy reading mode (§4.6) |
| Text scale up to 200% | Layouts tested at 200% system font scale, no truncation |
| Colour not sole indicator | Every severity level has both a colour and a text label |

### 13.4 Readability for Low-Literacy Users

The War Room intake flow (§8.3) is the highest-stakes surface for low-literacy users:
- Every step has a "Read aloud" button (TTS via `flutter_tts`)
- Voice input available at every text field
- Maximum reading age: Grade 8 equivalence (tested via Flesch-Kincaid in English; reviewed by native-language editors for regional variants)
- No legal or technical jargon without an inline explanation

---

## 14. Dark Mode System

### 14.1 Color Mapping

```
Light → Dark mapping
─────────────────────────────────────────────────────
Token             Light             Dark
─────────────────────────────────────────────────────
Background        Paper #F5F1E8     #14141F (deep ink)
Surface           #FFFFFF           #1F1F2E
Divider           #E0DDD6           #2C2C3E
Primary text      Ink #1C1C2E       #F0EDE4 (warm white)
Secondary text    Muted #6B6B7A     #9090A0
─────────────────────────────────────────────────────
Civic Gold        #D4870F           #E8A020 (slightly brighter)
Alert Red         #B52A2A           #D44040 (slightly brighter)
Verified Emerald  #1E6B3A           #2A9450
Vault Blue        #1A3D6B           #2455A0
Ledger Green      #1E4D38           #286048
War Room Amber    #8B3A0F           #B04C15
Academy Teal      #1A5C68           #227A8C
─────────────────────────────────────────────────────
```

### 14.2 Dark Mode Masthead Treatment

In dark mode, the pillar mastheads lighten slightly rather than inverting:
- Vault: #1A3D6B → #1E4A82 (slightly lighter navy)
- Ledger: #1E4D38 → #226045 (slightly lighter forest)
- War Room: stays near-black (#1A1A26), amber severity band becomes the primary visual
- Academy: #1A5C68 → #1E7080

The redaction bar in the Vault masthead inverts to white-on-dark: `████ ████ PRIVATE ████` in white on dark navy.

---

## 15. Motion & Animation Principles

### 15.1 The Rule

Animation serves information, not delight. The Civic Commons is not a game. Every animated element must pass: *"What would this screen communicate worse without this animation?"*

If the answer is "nothing," the animation is removed.

### 15.2 Permitted Animations

| Animation | Purpose | Duration | Easing |
|---|---|---|---|
| Screen push/pop | Spatial orientation (where am I in the hierarchy) | 280ms | easeOut |
| Tab switch | Spatial orientation (which pillar am I in) | 280ms | easeOut |
| Vault — send message | Confirms action completed | 150ms | easeOut |
| Ledger — upvote | Tactile confirmation of vote cast | 200ms | easeOut (number increments) |
| Karma level-up | One-time event, warrants emphasis | 400ms | Elastic out (controlled, single bounce) |
| Recording pulse | Communicates active audio capture | 1500ms loop | sinusoidal (smooth, not jarring) |
| BottomSheet | Standard Material pattern | 300ms | easeOut |
| SyncStatusBar appear | Non-intrusive state change | 200ms | easeIn |

### 15.3 Banned Animations

- Parallax scroll effects — performance on budget Androids, no information value
- Staggered list item reveals — unnecessary complexity
- Lottie animations for loading — too heavy for 2G init
- Any animation in War Room case detail (distraction during high-stakes reading)
- Any animation on error states (red should be immediately visible, not animated in)

---

## 16. Design-to-PRD Traceability Matrix

Every major design decision mapped to its PRD source.

| Design Decision | PRD Reference |
|---|---|
| No message preview in Vault conversation list | PRD FR-V3: status/presence not shared without accepted connection. Shared-device shoulder-surfing protection (Priya persona §3) |
| Pagination, not infinite scroll, in Ledger feed | PRD §1.1B: algorithmic engagement maximization is the problem the platform solves. Infinite scroll is that pattern. |
| Trauma-aware multi-step War Room intake | PRD §7.3 enhancement 4: trauma-informed intake UX, voice-note option |
| Consent checkbox not pre-checked at registration | PRD §13.2: DPDP Act §6 requires affirmative, unambiguous consent |
| Duress PIN (decoy vault) | PRD §5.3 enhancement 1 |
| Disguised app icon mode | PRD §5.3 enhancement 2 |
| SyncStatusBar (not a hard offline wall) | PRD §11 NFR: Offline tolerance — queue and sync, not hard-fail |
| Data-cost warnings before downloads > 5MB | PRD §3 Priya persona: patchy data, shared family device |
| Voice input in War Room and Academy | PRD §11 NFR: Accessibility — WCAG 2.1 AA, voice input |
| No avatar/profile photo anywhere in Vault | PRD §9.1: identity is composed of minimum necessary claims only |
| Muted, non-alarming karma-gate messaging | PRD §1.3: "verification without surveillance" — gates inform, not punish |
| No algorithmic content in Academy | PRD §1.1C: the problem is algorithm-driven fragmentation; the Academy solution is structured curriculum navigation |
| "You are in control of what happens next" on Intel Report | PRD §7.3 enhancement 4: victim consent checkpoint at every stage |
| Pillar-accent colors in nav bar and masthead | PRD §4.1: four functionally distinct pillars sharing one identity layer — distinct visual identity per pillar reinforces the structural separation |
| Flesch-Kincaid Grade 8 for War Room copy | PRD §3 Arjun persona: user in distress, potentially not a high-literacy professional |
| F-Droid as first-class release channel | PRD §12.2 Risk 5: resilient distribution if Play Store removed under Section 69A |
| HMAC signature on Verified Intel Report | PRD §7, FR-W5: chain-of-custody integrity for evidentiary use |
| No real name or phone number displayed anywhere | PRD §1.3 principle: privacy by architecture, not policy |
| Karma scores visible but not identities | PRD §9.2: behavioral trust indicators, not biometric or demographic |
| Public transparency log in The Commons | PRD §14.1: warrant-canary accountability mechanism |
