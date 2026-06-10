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

/// One-off formatting for mixed lists (e.g. the session list).
String moneyFor(int amount, String gameType) {
  final prev = chipMode;
  chipMode = gameType == 'mtt';
  final out = money(amount);
  chipMode = prev;
  return out;
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
