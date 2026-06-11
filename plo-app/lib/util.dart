/// Shared formatting and table-geometry helpers.

/// When true (MTT), amounts are tournament chips: plain numbers, no \$,
/// no cent division. Screens set this from their session's game type.
/// (Scaffold pragmatism — a per-context formatter is the cleaner long-term.)
bool chipMode = false;

String _group(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// Cash: cents → "\$1,240" (or "\$12.50"). MTT: chips → "20,000".
String money(int amount) {
  final sign = amount < 0 ? '-' : '';
  final v = amount.abs();
  if (chipMode) return '$sign${_group(v)}';
  final rem = v % 100;
  return rem == 0
      ? '$sign\$${_group(v ~/ 100)}'
      : '$sign\$${_group(v ~/ 100)}.${rem.toString().padLeft(2, '0')}';
}

/// Table display denomination. `money` follows [chipMode] ($ cash / chips MTT);
/// `bb` expresses amounts in big blinds (the solver's convention). Toggled on
/// the capture/replayer table; the list screens always use money.
enum TableUnit { money, bb }

TableUnit tableUnit = TableUnit.money;
int tableBigBlind = 100; // current hand's BB in the smallest unit; set per hand

/// Format an amount for the table, honoring [tableUnit].
String fmtAmt(int amount) {
  if (tableUnit == TableUnit.bb) {
    final bb = tableBigBlind == 0 ? 1 : tableBigBlind;
    var s = (amount / bb).toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }
  return money(amount);
}

/// Short label for the current table unit (for the toggle + pot suffix).
String get tableUnitLabel =>
    tableUnit == TableUnit.bb ? 'BB' : (chipMode ? 'chips' : '\$');

/// One-off formatting for mixed lists (e.g. the session list).
String moneyFor(int amount, String gameType) {
  final prev = chipMode;
  chipMode = gameType == 'mtt';
  final out = money(amount);
  chipMode = prev;
  return out;
}

/// Compact, scannable label for a saved hand: hero position, the four
/// hole-card ranks (high→low, `T` for ten) and the PLO suit shape —
/// e.g. `MP · AAKK ds`. Suit shapes: `ds` double-suited (2-2),
/// `ss` single-suited (2-1-1), `r` rainbow (1-1-1-1), `ts` three of a suit
/// (3-1), `mono` four of a suit. Derived from the stored canonical JSON, so it
/// labels hands captured before this label existed too.
String handLabel(Map<String, dynamic> json) {
  final hero = json['hero'] as Map<String, dynamic>?;
  final heroSeat = hero?['seat'] as int?;
  final players = (json['players'] as List?) ?? const [];
  var pos = '?';
  for (final p in players) {
    if ((p as Map)['seat'] == heroSeat) {
      pos = (p['position'] as String?) ?? '?';
      break;
    }
  }
  final cards = (hero?['cards'] as List?)?.cast<String>() ?? const <String>[];
  if (cards.isEmpty) return pos;
  const order = 'AKQJT98765432';
  final ranks = [for (final c in cards) c[0]]
    ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  final counts = <String, int>{};
  for (final c in cards) {
    counts[c[1]] = (counts[c[1]] ?? 0) + 1;
  }
  final desc = counts.values.toList()..sort((a, b) => b - a);
  final shape = (desc.length >= 2 && desc[0] == 2 && desc[1] == 2)
      ? 'ds'
      : switch (desc.first) { 4 => 'mono', 3 => 'ts', 2 => 'ss', _ => 'r' };
  return '$pos · ${ranks.join()} $shape';
}

/// Position label for every occupied seat, derived from the button.
/// [seats] must be sorted clockwise (ascending seat number).
Map<int, String> positionNames(List<int> seats, int buttonSeat) {
  final n = seats.length;
  final i = seats.indexOf(buttonSeat);
  final afterButton = [...seats.sublist(i + 1), ...seats.sublist(0, i)];

  if (n == 2) return {buttonSeat: 'BTN/SB', afterButton[0]: 'BB'};

  const middlesByCount = <int, List<String>>{
    0: [],
    1: ['UTG'],
    2: ['UTG', 'CO'],
    3: ['UTG', 'HJ', 'CO'],
    4: ['UTG', 'MP', 'HJ', 'CO'],
    5: ['UTG', 'UTG1', 'MP', 'HJ', 'CO'],
    6: ['UTG', 'UTG1', 'MP', 'LJ', 'HJ', 'CO'],
    7: ['UTG', 'UTG1', 'UTG2', 'MP', 'LJ', 'HJ', 'CO'],
  };

  final map = <int, String>{
    buttonSeat: 'BTN',
    afterButton[0]: 'SB',
    afterButton[1]: 'BB',
  };
  final middles = middlesByCount[n - 3]!;
  for (var k = 0; k < middles.length; k++) {
    map[afterButton[2 + k]] = middles[k];
  }
  return map;
}
