import 'package:civic_commons/ledger/data/in_memory_ledger_draft_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_draft_sink.dart';
import 'package:civic_commons/state/data/local_ledger_compose_bloc.dart';
import 'package:civic_commons/state/domain/ledger_compose_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LedgerComposeBloc', () {
    test('start() emits an idle empty state', () async {
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      final states = <LedgerComposeState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start();
      expect(states.last.status, LedgerComposeStatus.idle);
      expect(states.last.hasError, isFalse);
      await sub.cancel();
      await bloc.close();
    });

    test('setters compose partial updates', () async {
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      final states = <LedgerComposeState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start();
      await bloc.setCategory(LedgerCategory.consumerWatch);
      await bloc.setPinCode('800001');
      await bloc.setHeadline('H');
      await bloc.setBody('B');

      final last = states.last;
      expect(last.category, LedgerCategory.consumerWatch);
      expect(last.pinCode, '800001');
      expect(last.headline, 'H');
      expect(last.body, 'B');
      await sub.cancel();
      await bloc.close();
    });

    test('submit() persists a valid draft and emits submitted', () async {
      final sink = InMemoryLedgerDraftSink();
      final bloc = LocalLedgerComposeBloc(drafts: sink);
      final states = <LedgerComposeState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start();
      await bloc.setCategory(LedgerCategory.civicInfrastructure);
      await bloc.setPinCode('800001');
      await bloc.setHeadline('Boring Road drainage');
      await bloc.setBody('Third week stopped.');
      await bloc.submit();

      expect(bloc.current.isSubmitted, isTrue);
      expect(sink.saved, hasLength(1));
      expect(sink.saved.first.headline, 'Boring Road drainage');
      expect(sink.saved.first.category, LedgerCategory.civicInfrastructure);
      await sub.cancel();
      await bloc.close();
    });

    test('submit() rejects a missing category', () async {
      final sink = InMemoryLedgerDraftSink();
      final bloc = LocalLedgerComposeBloc(drafts: sink);
      await bloc.start();
      await bloc.setPinCode('800001');
      await bloc.setHeadline('H');
      await bloc.submit();
      expect(bloc.current.hasError, isTrue);
      expect(bloc.current.isSubmitted, isFalse);
      expect(sink.saved, isEmpty);
      await bloc.close();
    });

    test('submit() rejects a malformed pin code', () async {
      final sink = InMemoryLedgerDraftSink();
      final bloc = LocalLedgerComposeBloc(drafts: sink);
      await bloc.start();
      await bloc.setCategory(LedgerCategory.breakingLocal);
      await bloc.setPinCode('80'); // not 6 digits
      await bloc.setHeadline('H');
      await bloc.submit();
      expect(bloc.current.hasError, isTrue);
      expect(sink.saved, isEmpty);
      await bloc.close();
    });

    test('submit() rejects a blank headline', () async {
      final sink = InMemoryLedgerDraftSink();
      final bloc = LocalLedgerComposeBloc(drafts: sink);
      await bloc.start();
      await bloc.setCategory(LedgerCategory.satireAndCulture);
      await bloc.setPinCode('800001');
      await bloc.setHeadline('   ');
      await bloc.submit();
      expect(bloc.current.hasError, isTrue);
      expect(sink.saved, isEmpty);
      await bloc.close();
    });

    test('error state is generic — no reason-specific detail', () async {
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      await bloc.start();
      await bloc.submit();
      final state = bloc.current;
      // Only a boolean flag + status — nothing about WHICH field failed.
      expect(state.hasError, isTrue);
      expect(state.status, LedgerComposeStatus.idle);
      expect(state.headline, isEmpty);
      await bloc.close();
    });

    test('reset() clears the draft back to idle', () async {
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      await bloc.start();
      await bloc.setCategory(LedgerCategory.studentRights);
      await bloc.setHeadline('H');
      await bloc.reset();
      final state = bloc.current;
      expect(state.status, LedgerComposeStatus.idle);
      expect(state.category, isNull);
      expect(state.headline, isEmpty);
      await bloc.close();
    });

    test('draft sink is a port — compose works against any implementation',
        () async {
      final bloc = LocalLedgerComposeBloc(drafts: _RecordingSink());
      await bloc.start();
      await bloc.setCategory(LedgerCategory.civicInfrastructure);
      await bloc.setPinCode('800001');
      await bloc.setHeadline('H');
      await bloc.submit();
      expect(bloc.current.isSubmitted, isTrue);
      await bloc.close();
    });

    test('a failing sink degrades to the generic error — never a crash',
        () async {
      final bloc = LocalLedgerComposeBloc(drafts: _ThrowingSink());
      await bloc.start();
      await bloc.setCategory(LedgerCategory.consumerWatch);
      await bloc.setPinCode('800001');
      await bloc.setHeadline('H');
      await bloc.submit();

      final state = bloc.current;
      expect(state.status, LedgerComposeStatus.error);
      expect(state.hasError, isTrue);
      expect(state.isSubmitted, isFalse);
      await bloc.close();
    });
  });
}

class _ThrowingSink implements LedgerDraftSink {
  @override
  Future<String> save(LedgerDraft draft) async {
    throw Exception('sink down');
  }
}

class _RecordingSink implements LedgerDraftSink {
  final saved = <LedgerDraft>[];

  @override
  Future<String> save(LedgerDraft draft) async {
    saved.add(draft);
    return 'draft_x';
  }
}
