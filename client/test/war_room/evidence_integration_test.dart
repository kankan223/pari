import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/aes_gcm_evidence_cipher.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/data/queue_evidence_sink.dart';
import 'package:civic_commons/war_room/domain/evidence_envelope.dart';
import 'package:civic_commons/war_room/domain/evidence_item.dart';
import 'package:civic_commons/war_room/domain/evidence_ports.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// Task 8.2 integration: the REAL AES-256-GCM evidence cipher + the REAL
/// queue (app-key sealed) + the REAL in-memory stores, with only the file
/// picker faked. Proves the sealed envelope reaches the queue with zero
/// plaintext and zero filename, and the intake UI renders only the
/// derived `mime · size` label.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _QueuedPicker implements EvidencePicker {
  int calls = 0;

  @override
  Future<PickedEvidence?> pick() async {
    calls++;
    return PickedEvidence(
      bytes: Uint8List.fromList(List.generate(4096, (i) => (i * 13) & 0xff)),
      displayName: 'harassment_screenshot_private.png',
      mimeType: 'image/png',
      sizeBytes: 4096,
    );
  }
}

void main() {
  testWidgets(
      'pick → encrypt → queue → file: sealed envelope lands with no plaintext',
      (tester) async {
    _setTallViewport(tester);
    final evidenceStore = InMemoryEntityStore<EvidenceRecord>((r) => r.id);
    final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
    final queueCipher = testCipher();
    final device = await X25519().newKeyPair();
    final cipher = AesGcmEvidenceCipher(
        crypto: CryptoServiceImpl(), deviceKeyPair: device);
    final sink = QueueEvidenceSink(
      cipher: cipher,
      evidenceStore: evidenceStore,
      syncQueue:
          LocalSyncQueueRepository(store: queueStore, cipher: queueCipher),
      recipientPublicKey: await device.extractPublicKey(),
    );
    final bloc = LocalWarRoomBloc(
      repository: InMemoryWarCaseRepository(),
      evidenceSink: sink,
    );
    final picker = _QueuedPicker();
    String? filedStamp;

    await tester.pumpWidget(MaterialApp(
      home: WarRoomIntakeScreen(
        bloc: bloc,
        picker: picker,
        onFiled: (s) => filedStamp = s,
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    // Step 1 — situation.
    await tester.tap(find.text('I am being blackmailed or extorted'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 2 — narrative.
    await tester.enterText(
        find.byType(TextField), 'They have my photos and want money.');
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 3 — evidence: attach the picked file.
    expect(find.text('STEP 3 OF 5 — EVIDENCE'), findsOneWidget);
    await tester.tap(find.text('Add evidence'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // The derived label renders; the raw filename NEVER does.
    expect(find.text('Photo · 4.0 KB'), findsOneWidget);
    expect(find.textContaining('screenshot'), findsNothing);
    expect(find.textContaining('harassment'), findsNothing);
    expect(find.text('ENCRYPTED'), findsOneWidget);

    // Step 4 — urgency.
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    await tester.tap(find.text('This needs attention soon (this week)'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 5 — consent + submit.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    await tester.tap(find.text('Submit case securely'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(filedStamp, 'CC-0001',
        reason: 'extortion + this-week → sequential stamp CC-0001');

    // The evidence row + queue item landed, keyed to the draft case.
    expect(evidenceStore.length, 1);
    final record = (await evidenceStore.getAll()).single;
    expect(record.caseNumber, startsWith('DRAFT-'));
    expect(record.sealedFile, isNotEmpty);
    expect(record.dekEnvelope, isNotEmpty);

    final pending =
        await LocalSyncQueueRepository(store: queueStore, cipher: queueCipher)
            .getPending();
    expect(pending, hasLength(1));
    final item = pending.single;
    expect(item.operationType, SyncOperationType.create);
    expect(item.id, record.id,
        reason: 'queue id doubles as the Idempotency-Key');

    // Open the app-key seal: the frame is the evidence envelope with the
    // wrapped DEK + sealed file, and the frame bytes contain NO plaintext
    // fragment and NO filename.
    final opened = await queueCipher.open(item.payload);
    final envelope = decodeEvidenceEnvelope(opened);
    expect(envelope.evidenceId, record.id);
    expect(envelope.sealedFile, record.sealedFile);
    expect(envelope.dekEnvelope, record.dekEnvelope);
    expect(String.fromCharCodes(opened), isNot(contains('screenshot')));
    expect(String.fromCharCodes(opened), isNot(contains('harassment')));

    await bloc.close();
  });
}
