import 'package:flutter_test/flutter_test.dart';
import 'package:plo_capture/util.dart';

/// Minimal stored-record shape that [handLabel] reads: hero seat + cards and a
/// players list carrying each seat's position.
Map<String, dynamic> rec(String pos, List<String> cards, {int heroSeat = 6}) => {
      'hero': {'seat': heroSeat, 'cards': cards},
      'players': [
        {'seat': 1, 'position': 'BTN'},
        {'seat': heroSeat, 'position': pos},
      ],
    };

void main() {
  test('double-suited (2-2), ranks high to low', () {
    expect(handLabel(rec('MP', ['Ah', 'As', 'Kh', 'Ks'])), 'MP · AAKK ds');
  });

  test('single-suited (2-1-1)', () {
    expect(handLabel(rec('BTN', ['Ah', 'Kh', 'Qs', 'Jd'])), 'BTN · AKQJ ss');
  });

  test('rainbow (1-1-1-1)', () {
    expect(handLabel(rec('CO', ['Ah', 'Ks', 'Qd', 'Jc'])), 'CO · AKQJ r');
  });

  test('three of a suit (3-1)', () {
    expect(handLabel(rec('SB', ['Ah', 'Kh', 'Qh', 'Js'])), 'SB · AKQJ ts');
  });

  test('monotone (4)', () {
    expect(handLabel(rec('BB', ['Ah', 'Kh', 'Qh', 'Jh'])), 'BB · AKQJ mono');
  });

  test('ten renders as T and sorts correctly', () {
    expect(handLabel(rec('HJ', ['7d', 'Tc', '9c', '8d'])), 'HJ · T987 ds');
  });

  test('no cards (defensive) → position only', () {
    expect(handLabel(rec('UTG', const [])), 'UTG');
  });
}
