import 'package:flutter/material.dart';

import '../models/hand_session.dart';
import '../tracker/format.dart';

/// The hand-session form as a bottom sheet: PLO or PLO5, venue, cash stakes,
/// table size — no money (results belong to the session tracker). With
/// [initial] null it starts a new session now; otherwise it edits [initial],
/// including when it ran. [lockGame] freezes PLO/PLO5 once hands are logged,
/// so 4- and 5-card hands never mix in one session. Returns the session, or
/// null if cancelled.
Future<HandSession?> handSessionSheet(
  BuildContext context, {
  required String gameType,
  HandSession? initial,
  bool lockGame = false,
}) async {
  final isMtt = gameType == 'mtt';
  final editing = initial != null;
  final venueCtrl = TextEditingController(text: initial?.venue ?? '');
  final sbCtrl = TextEditingController(
      text: initial == null ? '2' : dollarsField(initial.smallBlind));
  final bbCtrl = TextEditingController(
      text: initial == null ? '5' : dollarsField(initial.bigBlind));
  var seats = initial?.maxSeats ?? 8;
  var game = initial?.game ?? 'plo4';
  var start = initial?.createdAt ?? DateTime.now();
  var end = initial?.endedAt;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> pickDate() async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: start,
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (d == null) return;
          final len = end?.difference(start);
          setSheet(() {
            start = DateTime(d.year, d.month, d.day, start.hour, start.minute);
            if (len != null) end = start.add(len);
          });
        }

        Future<void> pickTime({required bool isStart}) async {
          final t = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay.fromDateTime(isStart ? start : end!));
          if (t == null) return;
          setSheet(() {
            if (isStart) {
              final len = end?.difference(start);
              start = DateTime(
                  start.year, start.month, start.day, t.hour, t.minute);
              if (len != null && !len.isNegative) end = start.add(len);
            } else {
              // An end "before" the start means the session ran past midnight.
              var e = DateTime(
                  start.year, start.month, start.day, t.hour, t.minute);
              if (!e.isAfter(start)) e = e.add(const Duration(days: 1));
              end = e;
            }
          });
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  editing
                      ? 'Edit session'
                      : isMtt
                          ? 'New tournament'
                          : 'New cash game',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'plo4', label: Text('PLO')),
                  ButtonSegment(value: 'plo5', label: Text('PLO5')),
                ],
                selected: {game},
                onSelectionChanged: lockGame
                    ? null
                    : (v) => setSheet(() => game = v.first),
              ),
              if (lockGame)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Fixed once hands are logged.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.55))),
                ),
              const SizedBox(height: 4),
              TextField(
                controller: venueCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: isMtt ? 'Tournament / venue' : 'Venue'),
              ),
              if (!isMtt) ...[
                const SizedBox(height: 12),
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
              ],
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
              if (editing) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                        avatar: const Icon(Icons.event, size: 18),
                        label: Text('${shortDate(start)}, ${start.year}'),
                        onPressed: pickDate),
                    ActionChip(
                        label: Text('Start ${clock(start)}'),
                        onPressed: () => pickTime(isStart: true)),
                    if (end != null)
                      ActionChip(
                          label: Text('End ${clock(end!)}'),
                          onPressed: () => pickTime(isStart: false)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(editing
                    ? 'Save'
                    : isMtt
                        ? 'Start tournament'
                        : 'Start cash game'),
              ),
            ],
          ),
        );
      },
    ),
  );

  if (ok != true) return null;
  final venue = venueCtrl.text.trim();
  return HandSession(
    id: initial?.id ?? 'session-${DateTime.now().microsecondsSinceEpoch}',
    createdAt: start,
    gameType: gameType,
    smallBlind:
        isMtt ? 0 : parseDollars(sbCtrl.text) ?? initial?.smallBlind ?? 200,
    bigBlind: isMtt ? 0 : parseDollars(bbCtrl.text) ?? initial?.bigBlind ?? 500,
    venue: venue.isEmpty ? (isMtt ? 'Tournament' : 'Cash game') : venue,
    maxSeats: seats,
    endedAt: end,
    game: game,
  );
}
