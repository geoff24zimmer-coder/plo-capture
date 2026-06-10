import 'package:flutter/material.dart';
import '../db/hand_store.dart';
import '../models/session.dart';
import '../util.dart';
import 'hand_list_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});
  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  late Future<List<({Session session, int handCount, int net})>> _future;

  @override
  void initState() {
    super.initState();
    _future = HandStore.instance.listSessions();
  }

  void _refresh() =>
      setState(() => _future = HandStore.instance.listSessions());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSession,
        icon: const Icon(Icons.add),
        label: const Text('New session'),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load sessions:\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE24B4A))),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return Center(
              child: Text('No sessions yet.\nStart one to log hands.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = rows[i];
              final s = r.session;
              final net = r.net;
              return ListTile(
                title: Text('${s.stakesLabel} · ${s.venue}'),
                subtitle: Text(
                    '${_dateLabel(s.createdAt)} · ${r.handCount} hands'),
                trailing: Text(
                  moneyFor(net, s.gameType),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: net >= 0
                        ? const Color(0xFF5DCAA5)
                        : const Color(0xFFE24B4A),
                  ),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => HandListScreen(session: s)),
                  );
                  _refresh();
                },
              );
            },
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _newSession() async {
    final sbCtrl = TextEditingController(text: '2');
    final bbCtrl = TextEditingController(text: '5');
    final venueCtrl = TextEditingController();
    var gameType = 'cash';
    var seats = 8;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New session',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final (g, label) in [('cash', 'Cash'), ('mtt', 'MTT')])
                  ChoiceChip(
                    label: Text(label),
                    selected: gameType == g,
                    onSelected: (_) => setSheet(() => gameType = g),
                  ),
              ]),
              const SizedBox(height: 12),
              if (gameType == 'cash')
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: sbCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'SB \$'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: bbCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'BB \$'))),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: venueCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Venue / tournament')),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Table size'),
                Expanded(
                  child: Slider(
                    min: 2,
                    max: 10,
                    divisions: 8,
                    value: seats.toDouble(),
                    label: '$seats',
                    onChanged: (v) => setSheet(() => seats = v.round()),
                  ),
                ),
                Text('$seats-max'),
              ]),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Start session'),
              ),
            ],
          ),
        ),
      ),
    );

    if (created != true) return;
    final isMtt = gameType == 'mtt';
    final session = Session(
      id: 'session-${DateTime.now().microsecondsSinceEpoch}',
      createdAt: DateTime.now(),
      gameType: gameType,
      // MTT blinds are per-level and entered at hand time, not here.
      smallBlind:
          isMtt ? 0 : ((double.tryParse(sbCtrl.text) ?? 2) * 100).round(),
      bigBlind:
          isMtt ? 0 : ((double.tryParse(bbCtrl.text) ?? 5) * 100).round(),
      venue: venueCtrl.text.isEmpty ? 'Live game' : venueCtrl.text,
      maxSeats: seats,
    );
    await HandStore.instance.createSession(session);
    _refresh();
  }
}
