import 'dart:async';

import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/domain/device_pairing_bloc.dart';
import 'package:civic_commons/state/domain/device_pairing_state.dart';
import 'package:civic_commons/state/ui/pairing_scan_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFlag implements SecureFlagService {
  int enableCalls = 0;

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

class _ScriptedPairingBloc implements DevicePairingBloc {
  final _controller =
      StreamController<DevicePairingState>.broadcast(sync: true);
  final List<String> authorized = [];
  final DevicePairingPhase result;

  _ScriptedPairingBloc({this.result = DevicePairingPhase.paired});

  @override
  Stream<DevicePairingState> get state => _controller.stream;

  @override
  Future<void> start() async {
    _controller.add(const DevicePairingState());
  }

  @override
  Future<void> generatePairingCode() async {}

  @override
  Future<void> authorizeCode(String payloadText) async {
    authorized.add(payloadText);
    _controller.add(DevicePairingState(phase: result));
  }

  @override
  Future<void> reset() async {
    _controller.add(const DevicePairingState());
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  testWidgets('submits the entered code to the bloc', (tester) async {
    final bloc = _ScriptedPairingBloc();
    var popped = false;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await PairingScanSheet.show(context,
                    pairingBloc: bloc, secureFlagService: _FakeFlag());
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'civic-commons://pair?v=1');
    await tester.tap(find.text('Authorize'));
    await tester.pumpAndSettle();

    expect(bloc.authorized, ['civic-commons://pair?v=1']);
    expect(popped, isTrue,
        reason: 'a successful authorization closes the sheet with true');
    await bloc.close();
  });

  testWidgets('a failed code shows the inline error', (tester) async {
    final bloc = _ScriptedPairingBloc(result: DevicePairingPhase.scanFailed);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PairingScanSheet(
          pairingBloc: bloc,
          secureFlagService: _FakeFlag(),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), '+919876543210');
    await tester.tap(find.text('Authorize'));
    await tester.pump();

    expect(
      find.text('That code could not be authorized. Check it and try again.'),
      findsOneWidget,
    );
    expect(bloc.authorized, ['+919876543210']);
    await bloc.close();
  });

  testWidgets('FLAG_SECURE is enabled on mount (runtime)', (tester) async {
    final flag = _FakeFlag();
    final bloc = _ScriptedPairingBloc();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PairingScanSheet(
          pairingBloc: bloc,
          secureFlagService: flag,
        ),
      ),
    ));
    await tester.pump();

    expect(flag.enableCalls, 1,
        reason: 'mounting the pairing scan sheet must enable FLAG_SECURE');
    await bloc.close();
  });
}
