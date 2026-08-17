import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 9 foundation SECURITY CHECKPOINT (Task 8.8 scaffold).
///
/// 1. The Academy domain/data/state layers import NO networking
///    (http/WebSocket/dart:io sockets) — local-first by construction.
/// 2. No raw debug output (print/logger) exists in Academy production code.
/// 3. No PII-shaped literals (E.164 phones, 64-hex blind hashes, emails)
///    exist in Academy production code.
/// 4. The Academy UI surface is wrapped in FLAG_SECURE (verified by the
///    masthead widget test; the scaffold ships one entry-point component).
void main() {
  group('Phase 9 SECURITY CHECKPOINT (Task 8.8 scaffold)', () {
    test('Academy production code imports no networking packages', () {
      final libDir = Directory('lib/academy');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty, reason: 'academy tree must exist');

      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in files) {
        final source = f.readAsStringSync();
        if (forbidden.hasMatch(source)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in lib/academy');
    });

    test('Academy production code never prints', () {
      final libDir = Directory('lib/academy');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in files) {
        final source = f.readAsStringSync();
        if (printPattern.hasMatch(source)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in lib/academy');
    });

    test('Academy production code contains no PII-shaped literals', () {
      final libDir = Directory('lib/academy');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      // E.164 phone / 64-hex blind hash / email shapes.
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in files) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in lib/academy');
    });
    test('Academy state declares no identity-typed fields', () async {
      // Structural proof: the state projection declares no identity-typed
      // fields — only syllabus content, module-id sets, and the generic
      // error string. (The value objects themselves are zero-identity by
      // construction — validated in academy_module_test.dart.)
      final stateFile =
          File('lib/state/domain/academy_state.dart').readAsStringSync();
      // Field declarations only — the security doc comment may mention
      // the words "phone"/"email", which is not a leak.
      final declared = RegExp(r'final\s+[\w<>]+\s+(\w+);')
          .allMatches(stateFile)
          .map((m) => m.group(1)!.toLowerCase())
          .toList();
      expect(declared, isNot(contains('phone')));
      expect(declared, isNot(contains('email')));
      expect(declared, isNot(contains('blindHash')));
      expect(declared, isNot(contains('name')));
    });
  });

  group('Task 9.1 Academy UI Foundation SECURITY CHECKPOINT', () {
    /// The Task 9.1 Academy UI surface: the two new screens + the domain
    /// progress helper (which sits in lib/academy).
    List<File> uiFiles() => [
          File('lib/state/ui/academy_syllabus_screen.dart'),
          File('lib/state/ui/academy_module_screen.dart'),
          File('lib/academy/domain/academy_progress.dart'),
        ];

    test('Academy UI screens import no networking packages', () {
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in uiFiles()) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the 9.1 UI surface');
    });

    test('Academy UI screens never print', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in uiFiles()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the 9.1 UI surface');
    });

    test('Academy UI screens contain no PII-shaped literals', () {
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in uiFiles()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the 9.1 UI surface');
    });

    test(
        'no video SDK package in the UI surface (privacy-embed boundary '
        'holds in Task 9.3)', () {
      // Task 9.3 ships the REAL VideoRoomPlayer, but the privacy boundary
      // holds BY CONSTRUCTION: the Academy UI imports NO video SDK
      // (video_player/chewie/youtube_player/better_player/webview). The
      // embed URL is built only by PrivacyEmbedUrl.forSource from a
      // validated video id and played through the injected launcher seam.
      final videoImports = RegExp(
        "import\\s+['\"](package:video_player|package:chewie|package:youtube_player|package:better_player|package:webview_flutter)",
      );
      final offenders = <String>[];
      for (final f in uiFiles()) {
        if (videoImports.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no video SDK imports — the embed boundary is structural');
    });
    test('domain progress helper operates on UUID module ids only', () {
      final source =
          File('lib/academy/domain/academy_progress.dart').readAsStringSync();
      // API takes a syllabus + a SET of module ids — no identity-typed
      // parameters can even be expressed. Structural scan of DECLARED
      // identifiers (the doc comment may mention the words).
      expect(source, contains('Set<String> completedModuleIds'));
      final identifiers =
          RegExp(r'\b(final|var|String|int|double)\s+[\w<>?]+\s+(\w+)')
              .allMatches(source)
              .map((m) => m.group(2)!.toLowerCase())
              .toList();
      expect(identifiers, isNot(contains('phone')));
      expect(identifiers, isNot(contains('email')));
      expect(identifiers, isNot(contains('blindhash')));
      expect(identifiers, isNot(contains('name')));
    });
  });

  group('Task 9.2 Syllabus Tree SECURITY CHECKPOINT', () {
    /// The Task 9.2 data layer: the production repositories + the domain
    /// progress record.
    List<File> dataFiles() => [
          File('lib/academy/data/local_academy_syllabus_repository.dart'),
          File('lib/academy/data/local_academy_progress_store.dart'),
          File('lib/academy/domain/academy_progress_record.dart'),
        ];

    test('Academy data layer imports no networking packages', () {
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in dataFiles()) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the 9.2 data layer');
    });

    test('Academy data layer never prints', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in dataFiles()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the 9.2 data layer');
    });

    test('Academy data layer contains no PII-shaped literals', () {
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in dataFiles()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the 9.2 data layer');
    });

    test('academy schema tables declare zero identity columns', () {
      // Structural proof at the SCHEMA level: the v10 academy tables hold
      // only public course content / UUID module ids — no identity column
      // can ever be created (no users/devices/phones/hashes/timestamps).
      final schema = File('lib/database/domain/schema.dart').readAsStringSync();
      final academyTables = RegExp(
              r'static const DbTable (academyDomains|academyModules|academyProgress) = ')
          .allMatches(schema);
      expect(academyTables.length, 3,
          reason: 'all three academy tables must exist in the schema');
      for (final m in academyTables) {
        // Everything between the table name and its closing bracket must
        // avoid identity column names.
        final start = m.start;
        final end = schema.indexOf(']);', start);
        final block = schema.substring(start, end);
        final lower = block.toLowerCase();
        expect(lower, isNot(contains('hash')));
        expect(lower, isNot(contains('phone')));
        expect(lower, isNot(contains('email')));
        expect(lower, isNot(contains('user')));
        expect(lower, isNot(contains('device')));
        expect(lower, isNot(contains('author')));
      }
    });

    test('academy migration v10 creates no identity columns', () {
      final migration =
          File('lib/database/domain/migration.dart').readAsStringSync();
      // The v10 up statements create only the three academy tables with
      // public/UUID columns — no identity column names appear.
      final v10 = migration.indexOf('version: 10');
      expect(v10, greaterThan(0));
      final end = migration.indexOf('version: 11', v10);
      final block = migration.substring(
        v10,
        end == -1 ? migration.length : end,
      );
      final lower = block.toLowerCase();
      expect(lower, contains('academy_domains'));
      expect(lower, contains('academy_modules'));
      expect(lower, contains('academy_progress'));
      expect(lower, isNot(contains('phone')));
      expect(lower, isNot(contains('email')));
      expect(lower, isNot(contains('blind_hash')));
      expect(lower, isNot(contains('user_id')));
      expect(lower, isNot(contains('device_id')));
      expect(lower, isNot(contains('author')));
    });
    test('progress record declares a single UUID module id', () {
      final source = File('lib/academy/domain/academy_progress_record.dart')
          .readAsStringSync();
      final declared = RegExp(r'final\s+[\w<>]+\s+(\w+);')
          .allMatches(source)
          .map((m) => m.group(1)!.toLowerCase())
          .toList();
      expect(declared, ['moduleid'],
          reason: 'the record carries ONLY the module id — zero identity');
    });
  });

  group('Task 9.3 Video Room SECURITY CHECKPOINT', () {
    /// The Task 9.3 video surface: the domain URL builder, the resolver +
    /// launcher, and the player widget.
    List<File> videoFiles() => [
          File('lib/academy/domain/academy_video.dart'),
          File('lib/academy/data/in_memory_video_room_source_resolver.dart'),
          File('lib/state/ui/academy_video_room_player.dart'),
        ];

    test('video files import no networking or video SDK packages', () {
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|package:video_player|package:chewie|package:youtube_player|package:better_player|package:webview_flutter)",
      );
      final offenders = <String>[];
      for (final f in videoFiles()) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'the video surface is SDK-free and network-free by import');
    });

    test('video files never print', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in videoFiles()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the 9.3 video surface');
    });

    test('video files contain no PII-shaped literals', () {
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in videoFiles()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the 9.3 video surface');
    });

    test('the ONLY URL producer is the youtube-nocookie privacy builder', () {
      // Structural (declared string literals only — the doc comments may
      // mention the words, which is not a leak): the only http(s) string
      // literal in the whole video surface is the nocookie privacy host in
      // the URL builder, and no query-string literal can emit autoplay/
      // list/shorts params.
      final files = videoFiles();
      for (final f in files) {
        final source = f.readAsStringSync();
        // http(s) literals that are NOT inside a doc comment.
        final code = source
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('///'))
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        // URL literals in code: each must be the nocookie privacy host.
        final urlPattern = RegExp("['\"](https?://[^'\"]+)['\"]");
        for (final match in urlPattern.allMatches(code)) {
          final url = match.group(1)!;
          expect(
            url.startsWith('https://www.youtube-nocookie.com/embed/'),
            isTrue,
            reason: 'the only URL literal allowed is the nocookie embed host '
                '(found: $url in ${f.path})',
          );
        }
        // Query-param literals that would enable tracking/recommendations.
        expect(code, isNot(contains('autoplay=')));
        expect(code, isNot(contains('list=')));
        expect(code, isNot(contains('si=')));
      }
    });

    test('no recommendation surfaces exist in the player widget tree', () {
      final playerSource = File('lib/state/ui/academy_video_room_player.dart')
          .readAsStringSync();
      // Structural: the player tree is a single play frame — no list/
      // grid widget that could render a recommendation sidebar, no
      // channel/related labels.
      expect(playerSource, isNot(contains('ListView')));
      expect(playerSource, isNot(contains('GridView')));
      expect(playerSource, isNot(contains('PageView')));
      expect(playerSource, isNot(contains('Icons.thumb_up')));
      expect(playerSource, isNot(contains('Icons.subscriptions')));
      expect(playerSource, isNot(contains('Icons.sidebar')));
    });
  });

  group('Task 9.4 Offline Module Caching SECURITY CHECKPOINT', () {
    /// The Task 9.4 surface: the offline-cache domain/data/state/UI files
    /// (the academy data files are additionally covered by the recursive
    /// Phase-9 base scan above; this group also covers the state/UI files
    /// that live outside lib/academy).
    List<File> offlineFiles() => [
          File('lib/academy/domain/module_asset_manifest.dart'),
          File('lib/academy/domain/offline_module_cache.dart'),
          File('lib/academy/domain/module_cache_record.dart'),
          File('lib/academy/domain/offline_playback.dart'),
          File('lib/academy/data/academy_asset_catalog.dart'),
          File('lib/academy/data/in_memory_module_downloader.dart'),
          File('lib/academy/data/in_memory_module_download_dispatcher.dart'),
          File('lib/academy/data/in_memory_offline_module_cache.dart'),
          File('lib/academy/data/local_offline_module_cache.dart'),
          File('lib/state/domain/academy_offline_state.dart'),
          File('lib/state/domain/academy_offline_bloc.dart'),
          File('lib/state/data/local_academy_offline_bloc.dart'),
          File('lib/state/ui/academy_offline_section.dart'),
          File('lib/sync/data/workmanager_module_download_dispatcher.dart'),
        ];

    test('offline-cache code imports no networking packages', () {
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in offlineFiles()) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the 9.4 surface');
    });

    test('offline-cache code never prints', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in offlineFiles()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the 9.4 surface');
    });

    test('offline-cache code contains no PII-shaped literals', () {
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in offlineFiles()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the 9.4 surface');
    });

    test('module_cache schema declares zero identity columns', () {
      // Structural proof at the SCHEMA level: the v11 module_cache table
      // holds ONLY the UUID module-id key + status + sizes + the SEALED
      // payload — no identity column can ever be created.
      final schema = File('lib/database/domain/schema.dart').readAsStringSync();
      final blockStart = schema.indexOf('moduleCache = DbTable');
      expect(blockStart, greaterThan(-1));
      final blockEnd = schema.indexOf(']);', blockStart);
      final block = schema.substring(blockStart, blockEnd);
      expect(block, contains('module_id'));
      for (final forbidden in ['user', 'phone', 'email', 'author', 'hash']) {
        expect(block.toLowerCase(), isNot(contains(forbidden)),
            reason: '$forbidden must never be a module_cache column');
      }
    });

    test('sandbox wiki tables declare zero identity columns (9.5)', () {
      // Structural proof at the SCHEMA level: the v12 sandbox tables hold
      // ONLY UUID page/module keys + public titles + the SENSITIVE Markdown
      // body + the deterministic SA-#### author handle — no identity column.
      final schema = File('lib/database/domain/schema.dart').readAsStringSync();
      final pages = schema.substring(schema.indexOf('sandboxPages = DbTable'),
          schema.indexOf(']);', schema.indexOf('sandboxPages = DbTable')));
      expect(pages, contains('page_id'));
      expect(pages, isNot(contains('author')));
      final revisions = schema.substring(
          schema.indexOf('sandboxRevisions = DbTable'),
          schema.indexOf(']);', schema.indexOf('sandboxRevisions = DbTable')));
      expect(revisions, contains('body_markdown'));
      expect(revisions, contains('author_handle'));
      for (final forbidden in ['phone', 'email', 'user_id', 'device_id']) {
        expect(revisions.toLowerCase(), isNot(contains(forbidden)),
            reason: '$forbidden must never be a sandbox column');
      }
    });

    test('sandbox migration v12 creates no identity columns', () {
      final migration =
          File('lib/database/domain/migration.dart').readAsStringSync();
      final v12 = migration.indexOf('version: 12');
      expect(v12, greaterThan(0));
      final end = migration.indexOf('version: 13', v12);
      final block = migration.substring(
        v12,
        end == -1 ? migration.length : end,
      );
      final lower = block.toLowerCase();
      expect(lower, contains('sandbox_pages'));
      expect(lower, contains('sandbox_revisions'));
      expect(lower, isNot(contains('phone')));
      expect(lower, isNot(contains('email')));
      expect(lower, isNot(contains('user_id')));
      expect(lower, isNot(contains('device_id')));
    });

    test(
        'cache keys are validated UUID module ids only (no identity key '
        'type can be expressed)', () {
      // The offline-cache domain declares its key contract in ONE place:
      // every read/write path keys on a `moduleId` String validated by the
      // UuidV4 guard (academy_module.dart). Structural proof that the cache
      // API never accepts an identity-typed identifier.
      final cachePort = File('lib/academy/domain/offline_module_cache.dart')
          .readAsStringSync();
      final identifiers = RegExp(r'\b(final|var|String)\s+[\w<>?]+\s+(\w+)')
          .allMatches(cachePort)
          .map((m) => m.group(2)!.toLowerCase())
          .toList();
      expect(identifiers, isNot(contains('phone')));
      expect(identifiers, isNot(contains('email')));
      expect(identifiers, isNot(contains('blindhash')));
      // Exact match only — `wireName` legitimately contains the substring.
      expect(identifiers, isNot(contains('name')));
      expect(identifiers, isNot(contains('username')));
      // The entry carries moduleId + sizes + status + timestamp only.
      final entryDecl = cachePort.substring(
          cachePort.indexOf('class ModuleCacheEntry'),
          cachePort.indexOf('bool get isDownloaded'));
      expect(entryDecl, contains('moduleId'));
      expect(entryDecl.toLowerCase(), isNot(contains('payload')));
    });
  });

  group('Task 9.5 Sandbox Wiki SECURITY CHECKPOINT', () {
    /// The Task 9.5 surface: the wiki domain, the sync sink, the state/UI
    /// screens (the lib/academy data files are covered by the recursive
    /// Phase-9 base scan; the queue sink lives in lib/academy/data).
    List<File> wikiFiles() => [
          File('lib/academy/domain/sandbox_wiki.dart'),
          File('lib/academy/domain/sandbox_wiki_records.dart'),
          File('lib/academy/domain/sandbox_wiki_wire_codec.dart'),
          File('lib/academy/data/queue_sandbox_revision_sink.dart'),
          File('lib/state/domain/sandbox_wiki_state.dart'),
          File('lib/state/domain/sandbox_wiki_bloc.dart'),
          File('lib/state/data/local_sandbox_wiki_bloc.dart'),
          File('lib/state/ui/academy_sandbox_wiki_screen.dart'),
          File('lib/state/ui/academy_sandbox_page_screen.dart'),
          File('lib/state/ui/academy_sandbox_edit_screen.dart'),
        ];

    test('wiki code imports no networking packages', () {
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in wikiFiles()) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the 9.5 surface');
    });

    test('wiki code never prints', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in wikiFiles()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the 9.5 surface');
    });

    test('wiki code contains no PII-shaped literals', () {
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in wikiFiles()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the 9.5 surface');
    });

    test('the ONLY author shape in the wiki surface is SA-####', () {
      // Structural: the sandbox domain defines exactly ONE handle type
      // (SandboxAuthorHandle, deterministic `SA-####`) and the UI/state
      // render it directly — no raw identity field can be expressed.
      final domain =
          File('lib/academy/domain/sandbox_wiki.dart').readAsStringSync();
      expect(domain, contains('class SandboxAuthorHandle'));
      // The handle is built ONLY from the `SA-` prefix + a 4-hex FNV-1a
      // suffix derived from the module UUID — no identity input.
      expect(domain, contains("'SA-"));
      // No email/phone/name-shaped members on the handle type.
      final handleBlock = domain.substring(
          domain.indexOf('class SandboxAuthorHandle'),
          domain.indexOf('}', domain.indexOf('class SandboxAuthorHandle')));
      final lower = handleBlock.toLowerCase();
      expect(lower, isNot(contains('phone')));
      expect(lower, isNot(contains('email')));
      expect(lower, isNot(contains('name')));
    });

    test('wiki state carries only UUID page ids + SA handles', () {
      final stateFile =
          File('lib/state/domain/sandbox_wiki_state.dart').readAsStringSync();
      final declared = RegExp(r'final\s+[\w<>?]+\s+(\w+);')
          .allMatches(stateFile)
          .map((m) => m.group(1)!.toLowerCase())
          .toList();
      expect(declared, isNot(contains('phone')));
      expect(declared, isNot(contains('email')));
      expect(declared, isNot(contains('blindhash')));
      // Exact match only — `authorHandle` is the SA-#### pseudonym, which is
      // the ALLOWED blind shape; raw `name`/`username` never appear.
      expect(declared, isNot(contains('name')));
      expect(declared, isNot(contains('username')));
    });
  });

  group('Task 9.6 Cross-Pillar Study Groups SECURITY CHECKPOINT', () {
    /// The Task 9.6 surface: the study group domain, the sync sink, the
    /// state/UI screens (the lib/academy data files are covered by the
    /// recursive Phase-9 base scan; the queue sink lives in
    /// lib/academy/data).
    List<File> groupFiles() => [
          File('lib/academy/domain/study_group.dart'),
          File('lib/academy/domain/study_group_records.dart'),
          File('lib/academy/domain/study_group_wire_codec.dart'),
          File('lib/academy/data/queue_study_group_sink.dart'),
          File('lib/state/domain/study_group_state.dart'),
          File('lib/state/domain/study_group_bloc.dart'),
          File('lib/state/data/local_study_group_bloc.dart'),
          File('lib/state/ui/academy_study_group_screen.dart'),
        ];

    test('study group code imports no networking packages', () {
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in groupFiles()) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the 9.6 surface');
    });

    test('study group code never prints', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in groupFiles()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the 9.6 surface');
    });

    test('study group code contains no PII-shaped literals', () {
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in groupFiles()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the 9.6 surface');
    });

    test('the ONLY participant shape in the group surface is SG-####', () {
      // Structural: the domain defines exactly ONE handle type
      // (StudyGroupHandle, deterministic `SG-####`) and the UI/state render
      // it directly — no raw identity field can be expressed.
      final domain =
          File('lib/academy/domain/study_group.dart').readAsStringSync();
      expect(domain, contains('class StudyGroupHandle'));
      expect(domain, contains("'SG-"));
      final handleBlock = domain.substring(
          domain.indexOf('class StudyGroupHandle'),
          domain.indexOf('}', domain.indexOf('class StudyGroupHandle')));
      final lower = handleBlock.toLowerCase();
      expect(lower, isNot(contains('phone')));
      expect(lower, isNot(contains('email')));
      expect(lower, isNot(contains('name')));
    });

    test('study group state carries only UUID ids + SG handles', () {
      final stateFile =
          File('lib/state/domain/study_group_state.dart').readAsStringSync();
      final declared = RegExp(r'final\s+[\w<>?]+\s+(\w+);')
          .allMatches(stateFile)
          .map((m) => m.group(1)!.toLowerCase())
          .toList();
      expect(declared, isNot(contains('phone')));
      expect(declared, isNot(contains('email')));
      expect(declared, isNot(contains('blindhash')));
      expect(declared, isNot(contains('name')));
      expect(declared, isNot(contains('username')));
    });

    test('study group schema declares zero identity columns', () {
      // Structural proof at the SCHEMA level: the v13 study group tables
      // hold ONLY UUID keys + public title + coarse pin scope + topic refs
      // + blinded handles — no identity column can ever be created.
      final schema = File('lib/database/domain/schema.dart').readAsStringSync();
      final groups = schema.substring(schema.indexOf('studyGroups = DbTable'),
          schema.indexOf(']);', schema.indexOf('studyGroups = DbTable')));
      expect(groups, contains('group_id'));
      expect(groups, contains('pin_code'));
      expect(groups, isNot(contains('author')));
      expect(groups, isNot(contains('hash')));
      expect(groups, isNot(contains('user')));
      final members = schema.substring(
          schema.indexOf('studyGroupMembers = DbTable'),
          schema.indexOf(']);', schema.indexOf('studyGroupMembers = DbTable')));
      expect(members, contains('member_handle'));
      for (final forbidden in ['phone', 'email', 'user_id', 'device_id']) {
        expect(members.toLowerCase(), isNot(contains(forbidden)),
            reason: '$forbidden must never be a study-group column');
      }
    });

    test('study group migration v13 creates no identity columns', () {
      final migration =
          File('lib/database/domain/migration.dart').readAsStringSync();
      final v13 = migration.indexOf('version: 13');
      expect(v13, greaterThan(0));
      final end = migration.indexOf('version: 14', v13);
      final block = migration.substring(
        v13,
        end == -1 ? migration.length : end,
      );
      final lower = block.toLowerCase();
      expect(lower, contains('study_groups'));
      expect(lower, contains('study_group_members'));
      expect(lower, isNot(contains('phone')));
      expect(lower, isNot(contains('email')));
      expect(lower, isNot(contains('user_id')));
      expect(lower, isNot(contains('device_id')));
    });
  });
}
