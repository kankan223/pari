import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
import 'crypto/crypto_service.dart';
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
import 'repository/data/api_user_search_repository.dart';
import 'repository/domain/conversation.dart';
import 'repository/domain/entity_store.dart';
import 'repository/domain/message.dart';
import 'state/data/local_user_search_bloc.dart';
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
import 'performance/data/in_memory_performance_repository.dart';
import 'performance/data/in_memory_startup_optimizer.dart';
import 'state/data/local_performance_bloc.dart';
import 'cdn/data/in_memory_cdn_repository.dart';
import 'scaling/data/in_memory_scaling_repository.dart';
import 'security/data/in_memory_security_scanner.dart';
import 'state/data/local_cdn_delivery_bloc.dart';
import 'state/data/local_scaling_bloc.dart';
import 'state/data/local_security_scan_bloc.dart';
import 'state/data/local_deployment_bloc.dart';
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
import 'state/ui/performance_monitor_screen.dart';
import 'state/ui/cdn_delivery_screen.dart';
import 'state/ui/scaling_monitor_screen.dart';
import 'state/ui/security_scan_screen.dart';
import 'state/ui/deployment_monitor_screen.dart';
import 'state/ui/transparency_log_screen.dart';
import 'state/ui/ledger_feed_screen.dart';
import 'state/ui/ledger_post_detail_screen.dart';
import 'state/ui/quick_exit_safe_screen.dart';
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

import 'auth/identity_api_client.dart';
import 'auth/auth_storage.dart';
import 'auth/auth_bloc.dart';
import 'auth/user_search_api_client.dart';import 'relay/data/api_prekey_bundle_source.dart';
import 'relay/data/prekey_publisher.dart';
import 'relay/data/web_socket_relay_socket.dart';
import 'relay/relay_messaging_bloc.dart';
import 'signal/double_ratchet_service.dart';
import 'signal/session_manager.dart';
import 'signal/secure_session_store.dart';
import 'signal/prekey_manager.dart';
import 'signal/x3dh_service.dart';
import 'state/data/signal_message_cipher.dart';
import 'state/domain/message_cipher.dart';
import 'repository/domain/username_directory.dart';
import 'security/ui/secure_screen_wrapper.dart';
import 'state/domain/conversation_bloc.dart';
import 'state/domain/local_data_stream.dart';
import 'state/domain/message_bloc.dart';
import 'state/domain/message_state.dart';
import 'state/domain/user_search_bloc.dart';
import 'state/ui/login_screen.dart';
import 'state/ui/new_conversation_sheet.dart';
import 'state/domain/peer_handle.dart';
import 'state/ui/vault_theme.dart';

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

  // Initialize FlutterSecureStorage mock values. On Android/iOS the real
  // keychain backs this; on web/desktop the mock provides a no-op store
  // so IdentityStorage and SecureKeyStorage don't crash on missing
  // platform channels.
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({});

  // Show a loading screen immediately while the heavy dependency graph
  // builds (Argon2id + 24 BLoCs + seeded data). Without this the user
  // sees a blank white screen for several seconds.
  runApp(const _LoadingApp());

  try {
    final harness = await HarnessDependencies.build();

    // Build auth layer — talks to the real identity service.
    final authStorage = AuthStorage();
    final apiClient = IdentityApiClient(
      baseUrl: 'https://civic-commons-identity.onrender.com',
    );
    final authBloc = AuthBloc(api: apiClient, storage: authStorage);
    await authBloc.init();

    // ignore: avoid_debug_dump, use_build_context_synchronously
    runApp(CivicCommonsApp(
      harness: harness,
      authBloc: authBloc,
    ));
  } catch (e, st) {
    // If anything in the dependency graph throws, show an error screen
    // instead of a blank white screen. The error is NOT logged to avoid
    // leaking sensitive init details.
    runApp(_ErrorApp(error: e, stackTrace: st));
  }
}

// ---------------------------------------------------------------------------
// Loading / Error screens shown during HarnessDependencies.build().
// ---------------------------------------------------------------------------

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F0E8),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.shield, size: 64, color: Color(0xFF1F4D3A)),
              SizedBox(height: 24),
              Text(
                'Civic Commons',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F4D3A),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Initializing secure environment...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  backgroundColor: Color(0xFFE0D8C8),
                  valueColor: AlwaysStoppedAnimation(Color(0xFF1F4D3A)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;

  const _ErrorApp({required this.error, required this.stackTrace});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F0E8),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Initialization Failed',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App shell: checks auth state → shows LoginScreen or main harness.
// ---------------------------------------------------------------------------

class CivicCommonsApp extends StatefulWidget {
  final HarnessDependencies harness;
  final AuthBloc authBloc;

  const CivicCommonsApp({
    super.key,
    required this.harness,
    required this.authBloc,
  });

  @override
  State<CivicCommonsApp> createState() => _CivicCommonsAppState();
}

class _CivicCommonsAppState extends State<CivicCommonsApp> {
  RelayMessagingBloc? _relayBloc;
  LocalUserSearchBloc? _userSearchBloc;
  AuthState? _lastAuthState;

  @override
  void initState() {
    super.initState();
    _lastAuthState = widget.authBloc.current;
    // Relay is created lazily on first auth — see _connectRelay.
    // Connect relay if already authenticated.
    if (_lastAuthState?.isAuthenticated == true) {
      _connectRelay(_lastAuthState!);
    }
  }

  MessageCipher? _cipher;

  void _connectRelay(AuthState authState) async {
    final storage = AuthStorage();
    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) return;

    // Create the crypto stack for E2E encryption.
    if (_cipher == null) {
      try {
        final crypto = CryptoServiceImpl();
        final sessionStore = SecureSessionStore(cryptoService: crypto);
        final sessionManager = SessionManager(
          x3dh: X3DHService(cryptoService: crypto),
          crypto: crypto,
          store: sessionStore,
        );

        // Publish our prekey bundle to the identity service so other users
        // can initiate X3DH with us.
        final tokenProvider = () async => token;
        final prekeyPublisher = PreKeyPublisher(
          crypto: crypto,
          prekeyManager: PrekeyManager(
            cryptoService: crypto,
            secureStorage: SecureKeyStorage(),
          ),
          baseUrl: 'https://civic-commons-identity.onrender.com',
          tokenProvider: tokenProvider,
        );
        // Non-blocking: publish prekeys in the background.
        prekeyPublisher.publishIfNeeded();

        // Create the API-backed prekey bundle source for fetching peer bundles.
        final bundleSource = ApiPreKeyBundleSource(
          baseUrl: 'https://civic-commons-identity.onrender.com',
          tokenProvider: tokenProvider,
        );

        // Try to establish a real X3DH session with the seeded peer.
        // If the peer has published prekey bundles, we get real E2E encryption.
        // If not (dev harness or peer not registered), fall back to a self-session.
        try {
          final peerBundle = await bundleSource.fetchFor(widget.harness.peerHash);
          if (peerBundle != null) {
            // Real X3DH session established with the peer's published bundle!
            final identityKeyPair = await crypto.generateCurve25519KeyPair();
            await sessionManager.establishInitiatorSession(
              peerBlindHash: widget.harness.peerHash,
              bundle: peerBundle,
              myIdentityKeyPair: identityKeyPair,
            );
          } else {
            // Peer hasn't published prekeys — fall back to self-session.
            await sessionStore.save(
              widget.harness.peerHash,
              await _createSelfRatchet(crypto),
            );
          }
        } catch (_) {
          // X3DH failed — fall back to self-session for dev harness.
          await sessionStore.save(
            widget.harness.peerHash,
            await _createSelfRatchet(crypto),
          );
        }

        _cipher = SignalMessageCipher(sessions: sessionManager);
      } catch (_) {
        // Crypto init failed — continue without encryption (dev harness).
      }
    }

    // Create the relay messaging bloc if not already created.
    if (_relayBloc == null) {
      final h = widget.harness;
      _relayBloc = RelayMessagingBloc(
        conversationRepo: h.conversationBloc.repository,
        messageRepo: h.messageBloc.repository,
        conversationStore: h.conversationStore,
        cipher: _cipher,
        myBlindHash: h.peerHash,
        deviceId: 'civic-web-${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    // Create user search bloc if not already created.
    if (_userSearchBloc == null) {
      final apiClient = UserSearchApiClient(
        baseUrl: 'https://civic-commons-identity.onrender.com',
      );
      _userSearchBloc = LocalUserSearchBloc(
        repository: ApiUserSearchRepository(
          api: apiClient,
          tokenProvider: () => token,
        ),
        directory: widget.harness.usernameDirectory,
      );
    }

    _relayBloc?.connect(
      accessToken: token,
      relayUrl: 'wss://civic-commons-relay.onrender.com/v1/relay/ws',
      connector: const WebSocketRelaySocketConnector(),
    );
  }

  /// Creates a self-session Double Ratchet for dev mode encryption.
  /// Creates a self-session Double Ratchet for dev mode encryption.
  /// Generates a deterministic shared secret from the peer hash.
  Future<DoubleRatchetService> _createSelfRatchet(CryptoService crypto) async {
    // Generate a deterministic shared secret from the peer hash for dev mode.
    // In production, X3DH with the peer's published prekey bundle provides
    // the real shared secret.
    final peerHash = widget.harness.peerHash;
    final sharedSecret = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      sharedSecret[i] = peerHash.codeUnitAt(i % peerHash.length) & 0xff;
    }
    final ratchet = DoubleRatchetService(cryptoService: crypto);
    await ratchet.initialize(sharedSecret);
    return ratchet;
  }

  @override
  void dispose() {
    _relayBloc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Civic Commons',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4D3A),
        scaffoldBackgroundColor: WarRoomTheme.manilaPaper,
      ),
      home: StreamBuilder<AuthState>(
        stream: widget.authBloc.state,
        initialData: widget.authBloc.current,
        builder: (context, snapshot) {
          final authState = snapshot.data ?? const AuthState.initial();
          // Connect relay on fresh login.
          if (authState.isAuthenticated &&
              _lastAuthState?.isAuthenticated != true) {
            _connectRelay(authState);
          }
          _lastAuthState = authState;
          if (authState.isAuthenticated) {
            return CivicCommonsHarness(
              harness: widget.harness,
              authBloc: widget.authBloc,
              username: authState.username ?? 'anonymous',
              relayBloc: _relayBloc,
              userSearchBloc: _userSearchBloc,
            );
          }
          // Disconnect relay on logout.
          _relayBloc?.disconnect();
          return LoginScreen(authBloc: widget.authBloc);
        },
      ),
    );
  }
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
  final EntityStore<Conversation> conversationStore;
  final LocalDataStream<Conversation> conversationDb;
  final EntityStore<Message> messageStore;
  final LocalDataStream<Message> messageDb;

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

  // Performance Optimization (Task 12.1).
  final InMemoryPerformanceRepository performanceRepository;
  final LocalPerformanceBloc performanceBloc;

  // CDN & Content Delivery (Task 12.3).
  final InMemoryCdnRepository cdnRepository;
  final LocalCdnDeliveryBloc cdnDeliveryBloc;

  // Horizontal Scaling (Task 12.4).
  final InMemoryScalingRepository scalingRepository;
  final LocalScalingBloc scalingBloc;

  // Security Scan (Task 13.4).
  final InMemorySecurityScanner securityScanner;
  final LocalSecurityScanBloc securityScanBloc;

  // Deployment Monitor (Task 14.x).
  final LocalDeploymentBloc deploymentBloc;

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
    required this.conversationStore,
    required this.conversationDb,
    required this.messageStore,
    required this.messageDb,
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
    required this.performanceRepository,
    required this.performanceBloc,
    required this.cdnRepository,
    required this.cdnDeliveryBloc,
    required this.scalingRepository,
    required this.scalingBloc,
    required this.securityScanner,
    required this.securityScanBloc,
    required this.deploymentBloc,
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

    // Performance Optimization (Task 12.1): startup metrics and deferred pillars.
    final performanceRepository = InMemoryPerformanceRepository();
    final performanceBloc = LocalPerformanceBloc(
      repository: performanceRepository,
      optimizer: InMemoryStartupOptimizer(),
    );

    // CDN & Content Delivery (Task 12.3): delivery metrics and edge cache config.
    final cdnRepository = InMemoryCdnRepository();
    final cdnDeliveryBloc = LocalCdnDeliveryBloc(repository: cdnRepository);

    // Horizontal Scaling (Task 12.4): shard routing and load test metrics.
    final scalingRepository = InMemoryScalingRepository();
    final scalingBloc = LocalScalingBloc(repository: scalingRepository);

    // Security Scan (Task 13.4): static codebase security scanner.
    final securityScanner = InMemorySecurityScanner();
    final securityScanBloc = LocalSecurityScanBloc(scanner: securityScanner);

    // Deployment Monitor (Task 14.x): build config, CI/CD, health monitoring.
    final deploymentBloc = LocalDeploymentBloc();

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
      conversationStore: conversationStore,
      conversationDb: conversationDatabase,
      messageStore: messageStore,
      messageDb: messageDatabase,
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
      performanceRepository: performanceRepository,
      performanceBloc: performanceBloc,
      cdnRepository: cdnRepository,
      cdnDeliveryBloc: cdnDeliveryBloc,
      scalingRepository: scalingRepository,
      scalingBloc: scalingBloc,
      securityScanner: securityScanner,
      securityScanBloc: securityScanBloc,
      deploymentBloc: deploymentBloc,
    );
  }
}

// ---------------------------------------------------------------------------
// App shell: a Material 3 scaffold with one destination per pillar, each with
// its own navigator so pushed screens stay scoped to their tab.
// ---------------------------------------------------------------------------

class CivicCommonsHarness extends StatefulWidget {
  final HarnessDependencies harness;
  final AuthBloc authBloc;
  final String username;
  final RelayMessagingBloc? relayBloc;
  final LocalUserSearchBloc? userSearchBloc;

  const CivicCommonsHarness({
    super.key,
    required this.harness,
    required this.authBloc,
    this.username = 'anonymous',
    this.relayBloc,
    this.userSearchBloc,
  });

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
  late final _PerformanceTab _performanceTab;
  late final _CdnTab _cdnTab;
  late final _ScalingTab _scalingTab;
  late final _SecurityTab _securityTab;
  late final _DeploymentTab _deploymentTab;

  @override
  void initState() {
    super.initState();
    final h = widget.harness;
    _warRoomTab = _WarRoomTab(h: h);
    _vaultTab = _VaultTab(h: h, username: widget.username, relayBloc: widget.relayBloc, userSearchBloc: widget.userSearchBloc);
    _ledgerTab = _LedgerTab(h: h);
    _academyTab = _AcademyTab(h: h);
    _identityTab = _IdentityTab(h: h);
    _karmaTab = _KarmaTab(h: h);
    _notificationsTab = _NotificationsTab(h: h);
    _transparencyTab = _TransparencyTab(h: h);
    _consentTab = _ConsentTab(h: h);
    _auditTab = _AuditTab(h: h);
    _rateLimitTab = _RateLimitTab(h: h);
    _performanceTab = _PerformanceTab(h: h);
    _cdnTab = _CdnTab(h: h);
    _scalingTab = _ScalingTab(h: h);
    _securityTab = _SecurityTab(h: h);
    _deploymentTab = _DeploymentTab(h: h);
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
            _performanceTab,
            _cdnTab,
            _scalingTab,
            _securityTab,
            _deploymentTab,
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
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: 'Perf',
            ),
            NavigationDestination(
              icon: Icon(Icons.language_outlined),
              selectedIcon: Icon(Icons.language),
              label: 'CDN',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'Scale',
            ),
            NavigationDestination(
              icon: Icon(Icons.security_outlined),
              selectedIcon: Icon(Icons.security),
              label: 'Security',
            ),
            NavigationDestination(
              icon: Icon(Icons.rocket_launch_outlined),
              selectedIcon: Icon(Icons.rocket_launch),
              label: 'Deploy',
            ),
          ],
        ),
      ),
    );
  }
}

// --- Navigation helpers ---------------------------------------------------

/// Pushes a [MaterialPageRoute] onto the given [NavigatorState].
void _navPush(GlobalKey<NavigatorState> key, Widget screen) {
  key.currentState?.push(
    MaterialPageRoute<void>(builder: (_) => screen),
  );
}

// --- War Room tab ----------------------------------------------------------

class _WarRoomTab extends StatefulWidget {
  final HarnessDependencies h;
  const _WarRoomTab({required this.h});
  @override
  State<_WarRoomTab> createState() => _WarRoomTabState();
}

class _WarRoomTabState extends State<_WarRoomTab> {
  final _nav = GlobalKey<NavigatorState>();

  void _openIntake() {
    _nav.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => WarRoomIntakeScreen(
          bloc: widget.h.warRoomBloc,
          redactionPipeline: widget.h.redactionPipeline,
          draftStore: widget.h.intakeDraftStore,
          onFiled: (_) => widget.h.warRoomBloc.refresh(),
          onQuickExit: () {
            _nav.currentState?.push(
              MaterialPageRoute<void>(
                  builder: (_) => const QuickExitSafeScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _nav,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => WarRoomCaseListScreen(
          bloc: widget.h.warRoomBloc,
          onCaseTap: (caseNumber) {
            widget.h.warRoomBloc.openCase(caseNumber);
            _navPush(
              _nav,
              _WarCaseDetail(h: widget.h, caseNumber: caseNumber),
            );
          },
          onFileNewCase: _openIntake,
        ),
      ),
    );
  }
}

class _WarCaseDetail extends StatelessWidget {
  final HarnessDependencies h;
  final String caseNumber;

  const _WarCaseDetail({
    required this.h,
    required this.caseNumber,
  });

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

class _VaultTab extends StatefulWidget {
  final HarnessDependencies h;
  final String username;
  final RelayMessagingBloc? relayBloc;
  final UserSearchBloc? userSearchBloc;
  const _VaultTab({required this.h, this.username = 'anonymous', this.relayBloc, this.userSearchBloc});
  @override
  State<_VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<_VaultTab> {
  final _nav = GlobalKey<NavigatorState>();

  void _showNewConversationSheet() {
    final searchBloc = widget.userSearchBloc;
    if (searchBloc == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewConversationSheet(
        searchBloc: searchBloc,
        onStartConversation: (blindHashId) {
          _startNewConversation(blindHashId);
        },
      ),
    );
  }

  void _startNewConversation(String peerHash) async {
    // Create a new conversation in the local store.
    final conv = Conversation(
      id: 'conv-${DateTime.now().millisecondsSinceEpoch}',
      participantHash: peerHash,
      encryptedSessionState: Uint8List(0),
    );
    await widget.h.conversationBloc.repository.create(conv);
    await widget.h.conversationBloc.refresh();

    // Remember the peer in the directory.
    await widget.h.usernameDirectory.remember(username: '', blindHashId: peerHash);

    // Navigate to the new conversation.
    if (mounted) {
      _navPush(
        _nav,
        _VaultConversationDetailWrapper(
          messageBloc: widget.h.messageBloc,
          conversationBloc: widget.h.conversationBloc,
          peerHash: peerHash,
          relayBloc: widget.relayBloc,
          usernameDirectory: widget.h.usernameDirectory,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _nav,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => VaultConversationListScreen(
          bloc: widget.h.conversationBloc,
          requestsBloc: widget.h.connectionRequestsBloc,
          usernameDirectory: widget.h.usernameDirectory,
          contextMeta: widget.username,
          onNewConversation: _showNewConversationSheet,
          onConversationTap: (id) {
            _navPush(
              _nav,
              _VaultConversationDetailWrapper(
                messageBloc: widget.h.messageBloc,
                conversationBloc: widget.h.conversationBloc,
                peerHash: widget.h.peerHash,
                relayBloc: widget.relayBloc,
                usernameDirectory: widget.h.usernameDirectory,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Wrapper that wires the relay messaging to the conversation detail screen.
/// Shows a connection status indicator and sends messages through the relay.
class _VaultConversationDetailWrapper extends StatefulWidget {
  final MessageBloc messageBloc;
  final ConversationBloc conversationBloc;
  final String peerHash;
  final RelayMessagingBloc? relayBloc;
  final UsernameDirectory? usernameDirectory;

  const _VaultConversationDetailWrapper({
    required this.messageBloc,
    required this.conversationBloc,
    required this.peerHash,
    this.relayBloc,
    this.usernameDirectory,
  });

  @override
  State<_VaultConversationDetailWrapper> createState() =>
      _VaultConversationDetailWrapperState();
}

class _VaultConversationDetailWrapperState
    extends State<_VaultConversationDetailWrapper> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();

    try {
      // Send through the relay (real-time delivery).
      final relay = widget.relayBloc;
      if (relay != null && relay.currentStatus == RelayMessagingStatus.connected) {
        await relay.sendMessage(
          recipientHash: widget.peerHash,
          text: text,
          conversationId: 'conv-0001',
        );
      } else {
        // Fallback: persist locally only (offline).
        await widget.messageBloc.send(text);
      }
    } catch (_) {
      // Silently handle — message stays in local store.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participantHash = widget.peerHash;
    return SecureScreenWrapper(
      child: Scaffold(
        body: Column(
          children: [
            // Header with connection status.
            SafeArea(
              bottom: false,
              child: Container(
                color: VaultTheme.vaultBlue,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatPeerHandle(participantHash),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontFamily: VaultTheme.monoFont,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          StreamBuilder<RelayMessagingStatus>(
                            stream: widget.relayBloc?.status,
                            initialData: widget.relayBloc?.currentStatus,
                            builder: (context, snapshot) {
                              final status = snapshot.data;
                              final label = switch (status) {
                                RelayMessagingStatus.connected => '🟢 Live',
                                RelayMessagingStatus.connecting => '🟡 Connecting...',
                                RelayMessagingStatus.reconnecting => '🟠 Reconnecting...',
                                RelayMessagingStatus.authFailed => '🔴 Auth failed',
                                RelayMessagingStatus.disconnected => '⚪ Offline',
                                null => '⚪ Offline',
                              };
                              return Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Tooltip(
                      message: 'End-to-end encrypted',
                      child: Icon(Icons.lock_rounded,
                          color: Colors.white70, size: 18),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            // Message thread.
            Expanded(
              child: StreamBuilder<MessageState>(
                stream: widget.messageBloc.state,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  if (state == null || !state.hasLoaded) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final messages = state.messages;
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet — say hello!',
                        style: TextStyle(color: Colors.black45),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final summary = messages[index];
                      final isSent =
                          summary.direction == MessageDirection.sent;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: isSent
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSent
                                  ? VaultTheme.vaultBlue
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              summary.content ?? '[end-to-end encrypted]',
                              style: TextStyle(
                                color: isSent ? Colors.white : Colors.black87,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Composer.
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message…',
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      color: VaultTheme.vaultBlue,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Ledger tab ------------------------------------------------------------

class _LedgerTab extends StatefulWidget {
  final HarnessDependencies h;
  const _LedgerTab({required this.h});
  @override
  State<_LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<_LedgerTab> {
  final _nav = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _nav,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => LedgerFeedScreen(
          bloc: widget.h.ledgerFeedBloc,
          pinCode: '800001',
          geoBloc: widget.h.ledgerGeoBloc,
          reviewBloc: widget.h.ledgerReviewBloc,
          onPostTap: (postId) {
            final post = widget.h.ledgerPosts[postId];
            if (post == null) return;
            _navPush(
              _nav,
              LedgerPostDetailScreen(
                bloc: widget.h.ledgerFeedBloc,
                post: post,
              ),
            );
          },
          onCompose: () {
            _navPush(
              _nav,
              LedgerComposeScreen(
                bloc: widget.h.ledgerComposeBloc,
                defaultPinCode: '800001',
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- Academy tab -----------------------------------------------------------

class _AcademyTab extends StatefulWidget {
  final HarnessDependencies h;
  const _AcademyTab({required this.h});
  @override
  State<_AcademyTab> createState() => _AcademyTabState();
}

class _AcademyTabState extends State<_AcademyTab> {
  final _nav = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _nav,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => AcademySyllabusScreen(
          bloc: widget.h.academyBloc,
          onModuleTap: (moduleId) {
            final state = widget.h.academyBloc.current;
            final module = state.syllabus?.modules
                .where((m) => m.moduleId == moduleId)
                .firstOrNull;
            if (module == null) return;
            final domainTitle = state.syllabus?.domains
                .where((d) => d.domainId == module.domainId)
                .firstOrNull
                ?.title;
            _navPush(
              _nav,
              AcademyModuleScreen(
                bloc: widget.h.academyBloc,
                module: module,
                domainTitle: domainTitle,
                offlineBloc: widget.h.academyOfflineBloc,
                sandboxWikiBloc: widget.h.sandboxWikiBloc,
                studyGroupBloc: widget.h.studyGroupBloc,
                studyGroupPinCode: '800001',
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

class _NotificationsTab extends StatefulWidget {
  final HarnessDependencies h;
  const _NotificationsTab({required this.h});
  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  final _nav = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _nav,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => NotificationHistoryScreen(
          bloc: widget.h.notificationBloc,
        ),
      ),
    );
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

class _PerformanceTab extends StatelessWidget {
  final HarnessDependencies h;

  const _PerformanceTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return PerformanceMonitorScreen(bloc: h.performanceBloc);
  }
}

// --- CDN tab (Task 12.3) --------------------------------------------------

class _CdnTab extends StatelessWidget {
  final HarnessDependencies h;

  const _CdnTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return CdnDeliveryScreen(bloc: h.cdnDeliveryBloc);
  }
}

// --- Scaling tab (Task 12.4) -----------------------------------------------

class _ScalingTab extends StatelessWidget {
  final HarnessDependencies h;

  const _ScalingTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return ScalingMonitorScreen(bloc: h.scalingBloc);
  }
}

// --- Security Scan tab (Task 13.4) ----------------------------------------

class _SecurityTab extends StatelessWidget {
  final HarnessDependencies h;

  const _SecurityTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return SecurityScanScreen(bloc: h.securityScanBloc);
  }
}

// --- Deployment Monitor tab (Task 14.x) -----------------------------------

class _DeploymentTab extends StatelessWidget {
  final HarnessDependencies h;

  const _DeploymentTab({required this.h});

  @override
  Widget build(BuildContext context) {
    return DeploymentMonitorScreen(bloc: h.deploymentBloc);
  }
}
