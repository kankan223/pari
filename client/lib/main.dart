import 'package:flutter/material.dart';

import 'state/data/local_war_room_bloc.dart';
import 'state/ui/war_room_case_list_screen.dart';
import 'war_room/data/in_memory_war_case_repository.dart';

/// Civic Commons app shell (RUN.md §5 bootstrap).
///
/// The War Room pillar is the first wired screen: the [LocalWarRoomBloc]
/// reads cases ONLY from the local [InMemoryWarCaseRepository] (offline-first
/// — no network in the read path). The repository is the in-memory
/// implementation until the SQLCipher-backed store lands with the Phase 9
/// data work.
///
/// SECURITY CHECKPOINT (Task 8.1): the screen wraps itself in
/// [SecureScreenWrapper] (FLAG_SECURE). No identity data is constructed or
/// rendered here.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final warRoomBloc = LocalWarRoomBloc(
    repository: InMemoryWarCaseRepository(),
  );

  runApp(CivicCommonsApp(bloc: warRoomBloc));
}

class CivicCommonsApp extends StatelessWidget {
  final LocalWarRoomBloc bloc;

  const CivicCommonsApp({super.key, required this.bloc});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Civic Commons',
      theme: ThemeData(useMaterial3: true),
      home: WarRoomCaseListScreen(bloc: bloc),
    );
  }
}
