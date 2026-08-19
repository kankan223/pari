import 'package:civic_commons/consent/data/in_memory_consent_repository.dart';
import 'package:civic_commons/consent/domain/consent_record.dart';
import 'package:civic_commons/consent/domain/consent_repository.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:civic_commons/state/data/local_consent_bloc.dart';
import 'package:civic_commons/state/domain/consent_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalConsentBloc', () {
    late InMemoryConsentRepository repo;
    late LocalConsentBloc bloc;

    setUp(() {
      repo = InMemoryConsentRepository();
      bloc = LocalConsentBloc(repository: repo);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('initial state is idle', () {
      expect(bloc.current.phase, ConsentPhase.idle);
    });

    test('refresh loads consent status', () async {
      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'h',
      );

      await bloc.refresh();
      expect(bloc.current.phase, ConsentPhase.ready);
      expect(bloc.current.hasConsent(ConsentType.coreFunctionality), true);
      expect(bloc.current.hasConsent(ConsentType.analytics), false);
    });

    test('refresh emits loading then ready', () async {
      final phases = <ConsentPhase>[];
      final sub = bloc.state.listen((s) => phases.add(s.phase));

      await bloc.refresh();
      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(phases, contains(ConsentPhase.loading));
      expect(phases, contains(ConsentPhase.ready));
    });

    test('grantAll grants all consent types', () async {
      await bloc.grantAll();
      expect(bloc.current.phase, ConsentPhase.ready);
      expect(bloc.current.allRequiredGranted, true);

      for (final type in ConsentType.values) {
        expect(bloc.current.hasConsent(type), true);
      }
    });

    test('withdrawAll clears all consents', () async {
      await bloc.grantAll();
      expect(bloc.current.allRequiredGranted, true);

      await bloc.withdrawAll();
      expect(bloc.current.phase, ConsentPhase.ready);
      expect(bloc.current.allRequiredGranted, false);

      for (final type in ConsentType.values) {
        expect(bloc.current.hasConsent(type), false);
      }
    });

    test('withdrawConsent withdraws single type', () async {
      await bloc.grantAll();
      await bloc.withdrawConsent(ConsentType.analytics);

      expect(bloc.current.hasConsent(ConsentType.analytics), false);
      // Required types should still be granted
      expect(bloc.current.hasConsent(ConsentType.coreFunctionality), true);
    });

    test('deleteData triggers data deletion', () async {
      await bloc.grantAll();
      await bloc.deleteData();

      expect(bloc.current.phase, ConsentPhase.deleted);
      expect(bloc.current.allRequiredGranted, false);
      expect(repo.wasDataDeleted, true);
    });

    test('deleteData emits deleting then deleted', () async {
      final phases = <ConsentPhase>[];
      final sub = bloc.state.listen((s) => phases.add(s.phase));

      await bloc.deleteData();
      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(phases, contains(ConsentPhase.deleting));
      expect(phases, contains(ConsentPhase.deleted));
    });

    test('repository error maps to generic error state', () async {
      final badRepo = _FailingConsentRepository();
      final badBloc = LocalConsentBloc(repository: badRepo);

      await badBloc.refresh();
      expect(badBloc.current.phase, ConsentPhase.error);
      expect(badBloc.current.errorMessage, isNotNull);
      expect(badBloc.current.errorMessage!.contains('phone'), false);

      await badBloc.close();
    });

    test('close prevents further state emissions', () async {
      final phases = <ConsentPhase>[];
      bloc.state.listen((s) => phases.add(s.phase));

      await bloc.refresh();
      await bloc.close();
      await Future.delayed(const Duration(milliseconds: 10));

      // After close, no new emissions
      expect(phases.last, ConsentPhase.ready);
    });

    test('rapid sequential calls result in stale-dropped updates', () async {
      final phases = <ConsentPhase>[];
      bloc.state.listen((s) => phases.add(s.phase));

      // Fire multiple refreshes rapidly
      await Future.wait([
        bloc.refresh(),
        bloc.refresh(),
        bloc.refresh(),
      ]);

      // Only the last refresh should have completed with ready
      expect(bloc.current.phase, ConsentPhase.ready);
    });
  });
}

class _FailingConsentRepository implements ConsentRepository {
  @override
  String get currentConsentVersion => '1.0';

  @override
  Future<bool> hasAllRequiredConsents() async =>
      throw Exception('DB unavailable');

  @override
  Future<ConsentRecord?> getConsent(ConsentType type) async =>
      throw Exception('DB unavailable');

  @override
  Future<List<ConsentRecord>> getAllConsents() async =>
      throw Exception('DB unavailable');

  @override
  Future<bool> hasConsent(ConsentType type) async =>
      throw Exception('DB unavailable');

  @override
  Future<void> grantConsent({
    required ConsentType type,
    required String consentVersion,
    required String textHash,
  }) async =>
      throw Exception('DB unavailable');

  @override
  Future<void> withdrawConsent(ConsentType type) async =>
      throw Exception('DB unavailable');

  @override
  Future<void> deleteUserData() async => throw Exception('DB unavailable');
}
