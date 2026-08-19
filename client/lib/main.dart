import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'academy/data/in_memory_academy_progress_store.dart';
import 'academy/data/in_memory_academy_syllabus_repository.dart';
import 'academy/data/in_memory_module_download_dispatcher.dart';
import 'academy/data/in_memory_module_downloader.dart';
import 'academy/data/in_memory_offline_module_cache.dart';
import 'academy/data/in_memory_sandbox_wiki_repository.dart';
import 'academy/data/in_memory_study_group_repository.dart';
import 'academy/domain/study_group.dart';
import 'state/data/local_academy_offline_bloc.dart';
import 'state/data/local_sandbox_wiki_bloc.dart';
import 'state/data/local_study_group_bloc.dart';
import 'crypto/crypto_service_impl.dart';
import 'geo/domain/geo_place.dart';
import 'crypto/secure_key_storage.dart';
import 'identity/identity_storage.dart';
import 'identity/local_unified_identity_service.dart';
import 'identity/pillar_claim_sources.dart';
import 'karma/data/karma_event_records.dart';
import 'karma/data/local_karma_repository.dart';
import 'karma/domain/karma_action.dart';
import 'notification/data/in_memory_notification_repository.dart';
import 'notification/domain/notification_record.dart';
import 'notification/domain/notification_type.dart';
import 'transparency/data/in_memory_transparency_repository.dart';

import 'geo/domain/pin_code.dart';
import 'geo/domain/pin_code_resolver.dart';
import 'geo/domain/pin_code_store.dart';
import 'ledger/data/in_memory_ledger_feed_repository.dart';
import 'ledger/data/queue_ledger_draft_sink.dart';
import 'ledger/data/queue_ledger_vote_sink.dart';
import 'ledger/domain/ledger_category.dart';
import 'ledger/domain/ledger_post.dart';
import 'pii/data/dictionary_pii_detector.dart';
import 'pii/data/local_pii_redaction_pipeline.dart';
import 'repository/data/aes_gcm_queue_payload_cipher.dart';
import 'repository/data/local_connection_request_repository.dart';
import 'repository/data/local_conversation_repository.dart';
import 'repository/data/local_message_repository.dart';
import 'repository/data/local_sync_queue_repository.dart';
import 'repository/data/memory_username_directory.dart';
import 'repository/domain/connection_request.dart';
import 'repository/domain/conversation.dart';
import 'repository/domain/entity_store.dart';
import 'repository/domain/message.dart';
import 'repository/domain/sync_queue_item.dart';
import 'repository/domain/sync_queue_repository.dart';
import 'repository/domain/sync_sink.dart';
import 'state/data/local_academy_bloc.dart';
import 'state/data/local_connection_requests_bloc.dart';
import 'state/data/local_conversation_bloc.dart';
import 'state/data/local_data_stream_controller.dart';
import 'state/data/local_ledger_compose_bloc.dart';
import 'state/data/local_ledger_feed_bloc.dart';
import 'state/data/local_ledger_geo_bloc.dart';
import 'state/data/local_identity_verification_bloc.dart';
import 'state/data/local_karma_bloc.dart';
import 'state/data/local_notification_bloc.dart';
import 'audit/data/in_memory_audit_repository.dart';
import 'rate_limit/data/in_memory_rate_limit_repository.dart';
import 'consent/data/in_memory_consent_repository.dart';
import 'state/data/local_audit_log_bloc.dart';
import 'state/data/local_rate_limit_bloc.dart';
import 'state/data/local_consent_bloc.dart';
import 'state/data/local_transparency_log_bloc.dart';
import 'state/data/local_ledger_review_bloc.dart';
import 'state/data/local_message_bloc.dart';
import 'state/data/local_war_room_bloc.dart';
import 'state/ui/academy_module_screen.dart';
import 'state/ui/academy_syllabus_screen.dart';
import 'state/ui/ledger_compose_screen.dart';
import 'state/ui/identity_verification_screen.dart';
import 'state/ui/karma_status_screen.dart';
import 'state/ui/notification_history_screen.dart';
import 'state/ui/audit_log_screen.dart';
import 'state/ui/rate_limit_screen.dart';
import 'state/ui/dpdp_consent_screen.dart';
import 'state/ui/transparency_log_screen.dart';
import 'state/ui/ledger_feed_screen.dart';
import 'state/ui/ledger_post_detail_screen.dart';
import 'state/ui/quick_exit_safe_screen.dart';
import 'state/ui/vault_conversation_detail_screen.dart';
import 'state/ui/vault_conversation_list_screen.dart';
import 'state/ui/verified_intel_report_sheet.dart';
import 'state/ui/war_case_detail_screen.dart';
import 'state/ui/war_room_case_list_screen.dart';
import 'state/ui/war_room_intake_screen.dart';
import 'state/ui/war_room_theme.dart';
import 'war_room/domain/case_severity.dart';
import 'war_room/domain/case_status.dart';
import 'war_room/domain/war_room_case.dart';
import 'war_room/data/encrypted_intake_draft_store.dart';
import 'war_room/data/in_memory_war_case_repository.dart';

/// Civic Commons — MANUAL TESTING HARNESS (entry point).
///
/// This is NOT the production app shell (that lands with Phase 9
/// integration). It is a local-only harness that wires every built screen
/// to in-memory stores + local BLoCs so developers/QA can drive all of
/// Phase 8 (War Room) and earlier-phase UI (Vault, Ledger, Academy)
/// immediately:
///
///   flutter run -d linux     (or -d chrome / -d macos / -d windows)
///
/// SECURITY CHECKPOINTS honored by the harness:
/// - Every screen keeps its [SecureScreenWrapper] (FLAG_SECURE) wrapper —
///   the harness adds NO unguarded shell around them.
/// - Demo data carries ONLY public dossier attributes (case stamps,
///   severity/status labels, category enums, pin codes, blinded handles) —
///   no phones, no names, no raw hashes, no payload content.
/// - Queued mutations (votes, drafts, evidence) go through the same sealed
///   [AesGcmQueuePayloadCipher] the production data layer uses.
/// - No networking, no logging of sensitive material anywhere in this file.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final harness = await HarnessDependencies.build();
  runApp(CivicCommonsHarness(harness: harness));
}

// ---------------------------------------------------------------------------
// In-memory data-layer stand-ins (the SQLCipher production stores land in
// Phase 9; these mirror the test fakes with the same contracts).
// ---------------------------------------------------------------------------

class _MemStore<T> implements EntityStore<T> {
  final String Function(T) _idOf;
  final Map<String, T> _items = {};

  _MemStore(this._idOf);

  @override
  Future<void> insert(T entity) async {
    _items[_idOf(entity)] = entity;
  }

  @override
  Future<void> update(T entity) async {
    _items[_idOf(entity)] = entity;
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
  }

  @override
  Future<T?> getById(String id) async => _items[id];

  @override
  Future<List<T>> getAll() async => _items.values.toList(growable: false);
}

/// No-op [SyncSink] — the harness is offline-first by design; the sealed
/// queue simply accumulates so the UI can observe the mutation flow.
class _NoopSyncSink implements SyncSink {
  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async =>
      const SyncPushOutcome.acknowledged();
}

/// Deterministic [PinCodeResolver] for the harness — no location plugins
/// (the production [GeolocatorPinCodeResolver] stays out of the desktop/web
/// harness). Resolves a fixed coarse civic scope.
class _FixedPinCodeResolver implements PinCodeResolver {
  final PinCode _pin;

  _FixedPinCodeResolver(this._pin);

  @override
  Future<PinCodeResolution> resolveCurrentPlace() async => PinCodeResolution(
        place: GeoPlace(pinCode: _pin, district: 'Patna', locality: 'Sadar'),
        source: PinCodeResolutionSource.manual,
      );
}

class _MemoryPinCodeStore implements PinCodeStore {
  GeoPlace? _place;

  @override
  Future<GeoPlace?> read() async => _place;

  @override
  Future<void> write(GeoPlace place) async {
    _place = place;
  }
}

// ---------------------------------------------------------------------------
// Dependency graph.
// ---------------------------------------------------------------------------

/// The full dependency graph for the testing harness (in-memory stores,
/// local BLoCs, seeded demo data). Built once in [main] and handed to
/// [CivicCommonsHarness].
class HarnessDependencies {
  // Shared crypto + sealed queue (one per harness).
  final AesGcmQueuePayloadCipher queueCipher;
  final SyncQueueRepository syncQueue;
  final MemoryUsernameDirectory usernameDirectory;

  // The peer hash of the single seeded Vault conversation.
  final String peerHash;

  // Seeded Ledger posts (postId → post) for the detail screen.
  final Map<String, LedgerPost> ledgerPosts;

  // War Room.
  final LocalWarRoomBloc warRoomBloc;
  final EncryptedIntakeDraftStore intakeDraftStore;
  final LocalPiiRedactionPipeline redactionPipeline;

  // Vault.
  final LocalConversationBloc conversationBloc;
  final LocalMessageBloc messageBloc;
  final LocalConnectionRequestsBloc connectionRequestsBloc;

  // Ledger.
  final LocalLedgerFeedBloc ledgerFeedBloc;
  final LocalLedgerGeoBloc ledgerGeoBloc;
  final LocalLedgerComposeBloc ledgerComposeBloc;
  final LocalLedgerReviewBloc ledgerReviewBloc;

  // Academy.
  final LocalAcademyBloc academyBloc;
  final LocalAcademyOfflineBloc academyOfflineBloc;
  final LocalSandboxWikiBloc sandboxWikiBloc;
  final LocalStudyGroupBloc studyGroupBloc;

  // Unified Identity (Task 10.1).
  final LocalIdentityVerificationBloc identityVerificationBloc;

  // Civic Karma Engine (Task 10.2).
  final LocalKarmaRepository karmaRepository;
  final LocalKarmaBloc karmaBloc;

  // Notification System (Task 10.4).
  final InMemoryNotificationRepository notificationRepository;
  final LocalNotificationBloc notificationBloc;

  // Transparency Log (Task 10.5).
  final InMemoryTransparencyRepository transparencyRepository;
  final LocalTransparencyLogBloc transparencyLogBloc;

  // DPDP Consent (Task 11.1).
  final InMemoryConsentRepository consentRepository;
  final LocalConsentBloc consentBloc;
  final InMemoryAuditRepository auditRepository;
  final LocalAuditLogBloc auditLogBloc;

  // Rate Limiting & Abuse Prevention (Task 11.3).
  final InMemoryRateLimitRepository rateLimitRepository;
  final LocalRateLimitBloc rateLimitBloc;

  const HarnessDependencies({
    required this.queueCipher,
    required this.syncQueue,
    required this.usernameDirectory,
    required this.peerHash,
    required this.ledgerPosts,
    required this.warRoomBloc,
    required this.intakeDraftStore,
    required this.redactionPipeline,
    required this.conversationBloc,
    required this.messageBloc,
    required this.connectionRequestsBloc,
    required this.ledgerFeedBloc,
    required this.ledgerGeoBloc,
    required this.ledgerComposeBloc,
    required this.ledgerReviewBloc,
    required this.academyBloc,
    required this.academyOfflineBloc,
    required this.sandboxWikiBloc,
    required this.studyGroupBloc,
    required this.identityVerificationBloc,
    required this.karmaRepository,
    required this.karmaBloc,
    required this.notificationRepository,
    required this.notificationBloc,
    required this.transparencyRepository,
    required this.transparencyLogBloc,
    required this.consentRepository,
    required this.consentBloc,
    required this.auditRepository,
    required this.auditLogBloc,
    required this.rateLimitRepository,
    required this.rateLimitBloc,
  });

  static Future<HarnessDependencies> build() async {
    final crypto = CryptoServiceImpl();

    // --- Sealed offline queue (shared by every mutation sink). --------
    final dbKey = await crypto.deriveKeyFromPin(
      '123456',
      Uint8List.fromList(List.generate(16, (i) => i + 1)),
    );
    final queueCipher = AesGcmQueuePayloadCipher(crypto: crypto, key: dbKey);
    final syncQueue = LocalSyncQueueRepository(
      store: _MemStore<SyncQueueItem>((i) => i.id),
      cipher: queueCipher,
    );

    // --- War Room ------------------------------------------------------
    final warCases = <WarRoomCase>[
      WarRoomCase(
        caseNumber: 'CC-0047',
        title: 'Digital extortion — photo leak threat',
        description:
            'Ongoing demands after a personal photo leak. Communications '
            'escalating. Device-compromise suspected.',
        severity: CaseSeverity.critical,
        status: CaseStatus.investigationOngoing,
        filedAt: DateTime.utc(2026, 8, 12, 9, 30),
        analystCount: 2,
        estReportHours: 12,
        timeline: const [
          CaseTimelineEntry(
              label: 'Case filed', at: null, done: true, detail: 'Extortion'),
          CaseTimelineEntry(
              label: 'Auto-triage complete',
              done: true,
              detail: 'CRITICAL · 12h SLA'),
          CaseTimelineEntry(
              label: 'Analysts assigned',
              done: true,
              detail: '2 vetted analyst — skill-matched'),
          CaseTimelineEntry(label: 'Investigation ongoing', done: true),
          CaseTimelineEntry(label: 'Report ready', done: false),
          CaseTimelineEntry(label: 'Choose next step', done: false),
        ],
      ),
      WarRoomCase(
        caseNumber: 'CC-0046',
        title: 'Fake social media profile — identity theft',
        description:
            'Impersonation account using the victim\'s photos. Reported '
            'twice; platform not acting.',
        severity: CaseSeverity.high,
        status: CaseStatus.underInvestigation,
        filedAt: DateTime.utc(2026, 8, 10, 18, 5),
        analystCount: 1,
        estReportHours: 24,
        timeline: const [
          CaseTimelineEntry(
              label: 'Case filed',
              at: null,
              done: true,
              detail: 'Impersonation'),
          CaseTimelineEntry(
              label: 'Auto-triage complete',
              done: true,
              detail: 'HIGH · 24h SLA'),
          CaseTimelineEntry(
              label: 'Analysts assigned',
              done: true,
              detail: '1 vetted analyst'),
          CaseTimelineEntry(label: 'Investigation ongoing', done: false),
          CaseTimelineEntry(label: 'Report ready', done: false),
          CaseTimelineEntry(label: 'Choose next step', done: false),
        ],
      ),
      WarRoomCase(
        caseNumber: 'CC-0045',
        title: 'Stalking & location tracking',
        description:
            'GPS tracker found on vehicle. Police complaint filed locally.',
        severity: CaseSeverity.medium,
        status: CaseStatus.reportReady,
        filedAt: DateTime.utc(2026, 8, 8, 12, 0),
        analystCount: 1,
        estReportHours: 6,
        timeline: const [
          CaseTimelineEntry(
              label: 'Case filed', at: null, done: true, detail: 'Stalking'),
          CaseTimelineEntry(
              label: 'Auto-triage complete',
              done: true,
              detail: 'MEDIUM · 36h SLA'),
          CaseTimelineEntry(
              label: 'Analysts assigned',
              done: true,
              detail: '1 vetted analyst'),
          CaseTimelineEntry(label: 'Investigation ongoing', done: true),
          CaseTimelineEntry(label: 'Report ready', done: true),
          CaseTimelineEntry(label: 'Choose next step', done: false),
        ],
      ),
    ];

    final warRoomRepository = InMemoryWarCaseRepository(
      seed: warCases,
      nextNumber: 48,
      // custodyLog defaults to InMemoryCustodyLog() inside the repository.
    );

    // Intake drafts sealed before persistence (Task 8.7).
    final intakeDraftStore = EncryptedIntakeDraftStore(
      store: _MemStore((r) => r.id),
      cipher: queueCipher,
    );

    // Local PII scrubbing for intake narratives (Task 8.3).
    final redactionPipeline = LocalPiiRedactionPipeline(
      localDetector: const DictionaryPiiDetector(),
    );

    final warRoomBloc = LocalWarRoomBloc(repository: warRoomRepository);
    await warRoomBloc.start();

    // --- Vault ---------------------------------------------------------
    final conversationStore = _MemStore<Conversation>((c) => c.id);
    final conversationDatabase = LocalDataStreamController<Conversation>();
    final conversationBloc = LocalConversationBloc(
      repository: LocalConversationRepository(
        store: conversationStore,
        syncQueue: syncQueue,
        sink: _NoopSyncSink(),
      ),
      database: conversationDatabase,
    );

    const peerHash =
        '3f9c2b8d1a4e7f0a6c5b9d2e8f1a4c7b0d3e5f8a2b6c9d1e4f7a0b3c6e9d2f5a';
    final usernameDirectory = MemoryUsernameDirectory({peerHash: 'savitri'});
    await conversationStore.insert(Conversation(
      id: 'conv-0001',
      participantHash: peerHash,
      encryptedSessionState: Uint8List.fromList([1, 2, 3, 4]),
    ));

    final messageStore = _MemStore<Message>((m) => m.id);
    final messageDatabase = LocalDataStreamController<Message>();
    final messageBloc = LocalMessageBloc(
      repository: LocalMessageRepository(
        store: messageStore,
        syncQueue: syncQueue,
        sink: _NoopSyncSink(),
      ),
      database: messageDatabase,
      conversationId: 'conv-0001',
      participantHash: peerHash,
      // No cipher wired → the detail view renders the fixed E2EE
      // placeholder for every bubble (offline harness, Task 6.3 seam).
    );
    await messageBloc.start();
    await messageBloc.refresh();

    final requestsDatabase = LocalDataStreamController<ConnectionRequest>();
    final connectionRequestsBloc = LocalConnectionRequestsBloc(
      repository: LocalConnectionRequestRepository(
        store: _MemStore<ConnectionRequest>((r) => r.id),
        syncQueue: syncQueue,
      ),
      database: requestsDatabase,
      myBlindHash: peerHash,
      directory: usernameDirectory,
    );
    await connectionRequestsBloc.start();

    // --- Ledger --------------------------------------------------------
    final now = DateTime.now();
    final ledgerPosts = <LedgerPost>[
      LedgerPost(
        id: 'post-1001',
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        district: 'Patna',
        headline: 'Drainage repair deadline slips again',
        body: 'Contractor misses the third deadline on the Bailey Road '
            'drainage project; residents cite monsoon risk.',
        authorHandle: 'neighbourhood-watch',
        voteCount: 42,
        commentCount: 7,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      LedgerPost(
        id: 'post-1002',
        category: LedgerCategory.studentRights,
        pinCode: '800001',
        district: 'Patna',
        headline: 'Exam schedule released without prior notice',
        body: 'University publishes the final timetable three days before '
            'the first paper.',
        authorHandle: 'campus-desk',
        voteCount: 31,
        commentCount: 12,
        createdAt: now.subtract(const Duration(hours: 9)),
      ),
      LedgerPost(
        id: 'post-1003',
        category: LedgerCategory.breakingLocal,
        pinCode: '800001',
        district: 'Patna',
        headline: 'Power outage across the old city',
        body: 'Substation trip reported; restoration estimate not yet '
            'published.',
        authorHandle: 'wire-alerts',
        voteCount: 18,
        commentCount: 4,
        createdAt: now.subtract(const Duration(minutes: 40)),
      ),
    ];
    final ledgerRepository = InMemoryLedgerFeedRepository(seed: ledgerPosts);
    final ledgerVoteSink = QueueLedgerVoteSink(
      voteStore: _MemStore((r) => r.postId),
      syncQueue: syncQueue,
    );
    final ledgerFeedBloc = LocalLedgerFeedBloc(
      repository: ledgerRepository,
      votes: ledgerVoteSink,
    );
    final ledgerGeoBloc = LocalLedgerGeoBloc(
      resolver: _FixedPinCodeResolver(PinCode.parse('800001')),
      store: _MemoryPinCodeStore(),
    );
    await ledgerFeedBloc.start('800001');
    await ledgerGeoBloc.start();

    final ledgerDraftSink = QueueLedgerDraftSink(
      draftStore: _MemStore((r) => r.id),
      syncQueue: syncQueue,
    );
    final ledgerComposeBloc = LocalLedgerComposeBloc(drafts: ledgerDraftSink);
    await ledgerComposeBloc.start();

    final ledgerReviewBloc =
        LocalLedgerReviewBloc(repository: ledgerRepository);
    await ledgerReviewBloc.start('800001');

    // --- Academy -------------------------------------------------------
    final academyBloc = LocalAcademyBloc(
      repository: InMemoryAcademySyllabusRepository(),
      store: InMemoryAcademyProgressStore(),
    );
    await academyBloc.start();

    // Offline module caching (Task 9.4): in-memory cache sealed with the
    // REAL AES-256-GCM queue cipher (same key hierarchy as the sync queue);
    // the in-process dispatcher runs the queued download immediately so the
    // harness stays plugin-free and deterministic.
    // `late final` so the dispatcher's handler can close over the cache it
    // drives (the handler only runs after construction completes).
    late final InMemoryOfflineModuleCache academyOfflineCache;
    academyOfflineCache = InMemoryOfflineModuleCache(
      downloader: SimulatedModuleDownloader(cipher: queueCipher),
      dispatcher: InProcessModuleDownloadDispatcher(
        handler: (id) => academyOfflineCache.processQueuedDownload(id),
        runImmediately: true,
      ),
    );
    final academyOfflineBloc =
        LocalAcademyOfflineBloc(cache: academyOfflineCache);
    await academyOfflineBloc.start();

    // Sandbox Wiki (Task 9.5): module-scoped community study notes over an
    // in-memory repository — the harness exercises the full browse → edit →
    // save → revision-history flow.
    final sandboxWikiBloc =
        LocalSandboxWikiBloc(repository: InMemorySandboxWikiRepository());

    // Cross-pillar study groups (Task 9.6): in-memory repository seeded with
    // one demo group per Academy module so the matching surface has data.
    final studyGroupRepository = InMemoryStudyGroupRepository();
    final seedModule = InMemoryAcademySyllabusRepository.seedSyllabus
        .modulesFor('civics')
        .first;
    await studyGroupRepository.seedGroup(
      moduleId: seedModule.moduleId,
      title: 'Civic Rights Study Circle',
      locale: 'en',
      pinCode: '800001',
      topics: [
        StudyTopicRef.parse(
          pillar: StudyPillar.academy,
          topicId: seedModule.moduleId,
        ),
        StudyTopicRef.parse(
          pillar: StudyPillar.ledger,
          topicId: 'civics',
        ),
      ],
      capacity: 6,
    );
    final studyGroupBloc =
        LocalStudyGroupBloc(repository: studyGroupRepository);

    // Unified Identity (Task 10.1): the shared blind hash lives in secure
    // storage; the per-pillar minimum claims are composed from the pillar
    // stores (Vault username, Ledger pin scope + karma) — the harness uses
    // the in-memory claim sources over the seeded peer hash.
    final identityStorage = IdentityStorage(
      secureStorage: SecureKeyStorage(),
    );
    await identityStorage.storeBlindHashId(peerHash);
    final unifiedIdentityService = LocalUnifiedIdentityService(
      identityStorage: identityStorage,
      sources: MemoryPillarClaimSources(
        usernames: {peerHash: 'savitri'},
        deviceKeys: {
          peerHash: ['device-pub-key-1']
        },
        pinCodes: {peerHash: '800001'},
        karma: {peerHash: '247'},
      ),
    );
    final identityVerificationBloc = LocalIdentityVerificationBloc(
      service: unifiedIdentityService,
      sources: MemoryPillarClaimSources(
        usernames: {peerHash: 'savitri'},
        deviceKeys: {
          peerHash: ['device-pub-key-1']
        },
        pinCodes: {peerHash: '800001'},
        karma: {peerHash: '247'},
      ),
    );

    // Civic Karma Engine (Task 10.2): the append-only ledger seeded to the
    // SAME 247 balance the identity screen's karma claim shows
    // (5× module +2, 1× vetting +20, 3× contribution +15, 35× verified +5,
    // 1× rejected −3 = 10+20+45+175−3 = 247). The blind-hash actor is the
    // shared peer hash — zero PII.
    final karmaRepository = LocalKarmaRepository(
      store: _MemStore<KarmaEventRecord>((r) => r.eventId),
      clock: () => DateTime.utc(2026, 8, 18, 12),
    );
    for (final (action, count) in const [
      (KarmaAction.ledgerPostRejected, 1), // −3 (oldest, bottom of feed)
      (KarmaAction.ledgerPostVerified, 35), // +175
      (KarmaAction.warRoomCaseContribution, 3), // +45
      (KarmaAction.academyModuleCompleted, 5), // +10
      (KarmaAction.warRoomAnalystVetted, 1), // +20 (newest, top of feed)
    ]) {
      for (var i = 0; i < count; i++) {
        await karmaRepository.record(action: action, actorHash: peerHash);
      }
    }
    final karmaBloc = LocalKarmaBloc(
      repository: karmaRepository,
      accountAgeDays: 120,
      localActorHash: () async => peerHash,
    );

    // Notification System (Task 10.4): seeded with demo notifications
    // covering all three types. Zero PII — public labels only.
    final notificationRepository = InMemoryNotificationRepository(
      seed: [
        NotificationRecord(
          id: 'notif-1001',
          type: NotificationType.karmaEvent,
          title: 'Karma +5',
          body: 'Your Ledger post was verified by a peer reviewer.',
          createdAt: DateTime.utc(2026, 8, 18, 10, 30),
        ),
        NotificationRecord(
          id: 'notif-1002',
          type: NotificationType.caseAssignment,
          title: 'Case CC-0047 assigned',
          body: 'Digital extortion case assigned to you for investigation.',
          createdAt: DateTime.utc(2026, 8, 18, 9, 15),
        ),
        NotificationRecord(
          id: 'notif-1003',
          type: NotificationType.ledgerReviewRequest,
          title: 'Review requested',
          body: 'Drainage repair deadline slips again — peer review needed.',
          createdAt: DateTime.utc(2026, 8, 18, 8, 0),
        ),
        NotificationRecord(
          id: 'notif-1004',
          type: NotificationType.karmaEvent,
          title: 'Karma −3',
          body: 'Your Ledger post was rejected.',
          createdAt: DateTime.utc(2026, 8, 17, 16, 45),
          isRead: true,
        ),
        NotificationRecord(
          id: 'notif-1005',
          type: NotificationType.caseAssignment,
          title: 'Case CC-0046 assigned',
          body: 'Fake social media profile case assigned to you.',
          createdAt: DateTime.utc(2026, 8, 17, 12, 0),
          isRead: true,
        ),
      ],
    );
    final notificationBloc = LocalNotificationBloc(
      repository: notificationRepository,
    );

    // Transparency Log (Task 10.5): seeded with demo audit records
    // for the 800001 pin-code board. Zero PII — public labels only.
    final transparencyRepository = InMemoryTransparencyRepository();
    final transparencyLogBloc = LocalTransparencyLogBloc(
      repository: transparencyRepository,
      pinCode: '800001',
    );

    // DPDP Consent (Task 11.1): starts with no consents granted.
    final consentRepository = InMemoryConsentRepository();
    final consentBloc = LocalConsentBloc(
      repository: consentRepository,
    );

    // Audit Log (Task 11.2): starts with a few seeded audit events.
    final auditRepository = InMemoryAuditRepository();
    final auditLogBloc = LocalAuditLogBloc(
      repository: auditRepository,
    );

    // Rate Limiting & Abuse Prevention (Task 11.3).
    final rateLimitRepository = InMemoryRateLimitRepository();
    final rateLimitBloc = LocalRateLimitBloc(
      repository: rateLimitRepository,
    );

    return HarnessDependencies(
      queueCipher: queueCipher,
      syncQueue: syncQueue,
      usernameDirectory: usernameDirectory,
      peerHash: peerHash,
      ledgerPosts: {
        for (final p in ledgerPosts) p.id: p,
      },
      warRoomBloc: warRoomBloc,
      intakeDraftStore: intakeDraftStore,
      redactionPipeline: redactionPipeline,
      conversationBloc: conversationBloc,
      messageBloc: messageBloc,
      connectionRequestsBloc: connectionRequestsBloc,
      ledgerFeedBloc: ledgerFeedBloc,
      ledgerGeoBloc: ledgerGeoBloc,
      ledgerComposeBloc: ledgerComposeBloc,
      ledgerReviewBloc: ledgerReviewBloc,
      academyBloc: academyBloc,
      academyOfflineBloc: academyOfflineBloc,
      sandboxWikiBloc: sandboxWikiBloc,
      studyGroupBloc: studyGroupBloc,
      identityVerificationBloc: identityVerificationBloc,
      karmaRepository: karmaRepository,
      karmaBloc: karmaBloc,
      notificationRepository: notificationRepository,
      notificationBloc: notificationBloc,
      transparencyRepository: transparencyRepository,
      transparencyLogBloc: transparencyLogBloc,
      consentRepository: consentRepository,
      consentBloc: consentBloc,
      auditRepository: auditRepository,
      auditLogBloc: auditLogBloc,
      rateLimitRepository: rateLimitRepository,
      rateLimitBloc: rateLimitBloc,
    );
  }
}

// ---------------------------------------------------------------------------
// App shell: a Material 3 scaffold with one destination per pillar, each with
// its own navigator so pushed screens stay scoped to their tab.
// ---------------------------------------------------------------------------

class CivicCommonsHarness extends StatefulWidget {
  final HarnessDependencies harness;

  const CivicCommonsHarness({super.key, required this.harness});

  @override
  State<CivicCommonsHarness> createState() => _CivicCommonsHarnessState();
}

class _CivicCommonsHarnessState extends State<CivicCommonsHarness> {
  int _tab = 0;

  late final _WarRoomTab _warRoomTab;
  late final _VaultTab _vaultTab;
  late final _LedgerTab _ledgerTab;
  late final _AcademyTab _academyTab;
  late final _IdentityTab _identityTab;
  late final _KarmaTab _karmaTab;
  late final _NotificationsTab _notificationsTab;
  late final _TransparencyTab _transparencyTab;
  late final _ConsentTab _consentTab;
  late final _AuditTab _auditTab;
  late final _RateLimitTab _rateLimitTab;

  @override
  void initState() {
    super.initState();
    final h = widget.harness;
    _warRoomTab = _WarRoomTab(h: h);
    _vaultTab = _VaultTab(h: h);
    _ledgerTab = _LedgerTab(h: h);
    _academyTab = _AcademyTab(h: h);
    _identityTab = _IdentityTab(h: h);
    _karmaTab = _KarmaTab(h: h);
    _notificationsTab = _NotificationsTab(h: h);
    _transparencyTab = _TransparencyTab(h: h);
    _consentTab = _ConsentTab(h: h);
    _auditTab = _AuditTab(h: h);
    _rateLimitTab = _RateLimitTab(h: h);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Civic Commons — Manual Testing Harness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4D3A),
        scaffoldBackgroundColor: WarRoomTheme.manilaPaper,
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            _warRoomTab,
            _vaultTab,
            _ledgerTab,
            _academyTab,
            _identityTab,
            _karmaTab,
            _notificationsTab,
            _transparencyTab,
            _consentTab,
            _auditTab,
            _rateLimitTab,
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: 'War Room',
            ),
            NavigationDestination(
              icon: Icon(Icons.lock_outline),
              selectedIcon: Icon(Icons.lock),
              label: 'Vault',
            ),
            NavigationDestination(
              icon: Icon(Icons.newspaper_outlined),
              selectedIcon: Icon(Icons.newspaper),
              label: 'Ledger',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Academy',
            ),
            NavigationDestination(
              icon: Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge),
              label: 'Identity',
            ),
            NavigationDestination(
              icon: Icon(Icons.star_outline),
              selectedIcon: Icon(Icons.star),
              label: 'Karma',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications),
              label: 'Alerts',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Log',
            ),
            NavigationDestination(
              icon: Icon(Icons.privacy_tip_outlined),
              selectedIcon: Icon(Icons.privacy_tip),
              label: 'Consent',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Audit',
            ),
            NavigationDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: 'Limits',
            ),
          ],
        ),
      ),
    );
  }
}

// --- War Room tab ----------------------------------------------------------

class _WarRoomTab extends StatelessWidget {
  final HarnessDependencies h;

  const _WarRoomTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: const PageStorageKey('war-room-tab'),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/intake':
            return MaterialPageRoute(
              builder: (_) => WarRoomIntakeScreen(
                bloc: h.warRoomBloc,
                redactionPipeline: h.redactionPipeline,
                draftStore: h.intakeDraftStore,
                onFiled: (stamp) {
                  h.warRoomBloc.refresh();
                },
                onQuickExit: () {
                  _push(context, const QuickExitSafeScreen());
                },
              ),
            );
          default:
            return MaterialPageRoute(
              builder: (_) => WarRoomCaseListScreen(
                bloc: h.warRoomBloc,
                onCaseTap: (caseNumber) {
                  h.warRoomBloc.openCase(caseNumber);
                  _push(context, _WarCaseDetail(h: h, caseNumber: caseNumber));
                },
                onFileNewCase: () => Navigator.of(context).pushNamed('/intake'),
              ),
            );
        }
      },
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _WarCaseDetail extends StatelessWidget {
  final HarnessDependencies h;
  final String caseNumber;

  const _WarCaseDetail({required this.h, required this.caseNumber});

  @override
  Widget build(BuildContext context) {
    return WarCaseDetailScreen(
      bloc: h.warRoomBloc,
      caseNumber: caseNumber,
      onReport: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => VerifiedIntelReportSheet(
            bloc: h.warRoomBloc,
            caseNumber: caseNumber,
          ),
        );
      },
      onQuickExit: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const QuickExitSafeScreen()),
        );
      },
    );
  }
}

// --- Vault tab -------------------------------------------------------------

class _VaultTab extends StatelessWidget {
  final HarnessDependencies h;

  const _VaultTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: const PageStorageKey('vault-tab'),
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => VaultConversationListScreen(
          bloc: h.conversationBloc,
          requestsBloc: h.connectionRequestsBloc,
          usernameDirectory: h.usernameDirectory,
          contextMeta: 'civic-commons',
          onConversationTap: (id) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VaultConversationDetailScreen(
                  bloc: h.messageBloc,
                  participantHash: h.peerHash,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- Ledger tab ------------------------------------------------------------

class _LedgerTab extends StatelessWidget {
  final HarnessDependencies h;

  const _LedgerTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: const PageStorageKey('ledger-tab'),
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => LedgerFeedScreen(
          bloc: h.ledgerFeedBloc,
          pinCode: '800001',
          geoBloc: h.ledgerGeoBloc,
          reviewBloc: h.ledgerReviewBloc,
          onPostTap: (postId) {
            final post = h.ledgerPosts[postId];
            if (post == null) {
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LedgerPostDetailScreen(
                  bloc: h.ledgerFeedBloc,
                  post: post,
                ),
              ),
            );
          },
          onCompose: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LedgerComposeScreen(
                  bloc: h.ledgerComposeBloc,
                  defaultPinCode: '800001',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- Academy tab -----------------------------------------------------------

class _AcademyTab extends StatelessWidget {
  final HarnessDependencies h;

  const _AcademyTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: const PageStorageKey('academy-tab'),
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => AcademySyllabusScreen(
          bloc: h.academyBloc,
          onModuleTap: (moduleId) {
            final state = h.academyBloc.current;
            final module = state.syllabus?.modules
                .where((m) => m.moduleId == moduleId)
                .firstOrNull;
            if (module == null) {
              return;
            }
            final domainTitle = state.syllabus?.domains
                .where((d) => d.domainId == module.domainId)
                .firstOrNull
                ?.title;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AcademyModuleScreen(
                  bloc: h.academyBloc,
                  module: module,
                  domainTitle: domainTitle,
                  offlineBloc: h.academyOfflineBloc,
                  sandboxWikiBloc: h.sandboxWikiBloc,
                  studyGroupBloc: h.studyGroupBloc,
                  studyGroupPinCode: '800001',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- Unified Identity tab (Task 10.1) ---------------------------------------

class _IdentityTab extends StatelessWidget {
  final HarnessDependencies h;

  const _IdentityTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return IdentityVerificationScreen(bloc: h.identityVerificationBloc);
  }
}

// --- Karma tab (Task 10.2) ------------------------------------------------

class _KarmaTab extends StatelessWidget {
  final HarnessDependencies h;

  const _KarmaTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return KarmaStatusScreen(bloc: h.karmaBloc);
  }
}

// --- Notifications tab (Task 10.4) ----------------------------------------

class _NotificationsTab extends StatelessWidget {
  final HarnessDependencies h;

  const _NotificationsTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return NotificationHistoryScreen(bloc: h.notificationBloc);
  }
}

// --- Transparency Log tab (Task 10.5) ------------------------------------

class _TransparencyTab extends StatelessWidget {
  final HarnessDependencies h;

  const _TransparencyTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return TransparencyLogScreen(bloc: h.transparencyLogBloc);
  }
}

// --- DPDP Consent tab (Task 11.1) ----------------------------------------

class _ConsentTab extends StatelessWidget {
  final HarnessDependencies h;

  const _ConsentTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return DpdpConsentScreen(bloc: h.consentBloc);
  }
}

class _AuditTab extends StatelessWidget {
  final HarnessDependencies h;

  const _AuditTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return AuditLogScreen(bloc: h.auditLogBloc);
  }
}

class _RateLimitTab extends StatelessWidget {
  final HarnessDependencies h;

  const _RateLimitTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return RateLimitScreen(bloc: h.rateLimitBloc);
  }
}
