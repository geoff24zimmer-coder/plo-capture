// The AI coach button's client and review screen (ai-hand-reviewer D30). The server is stood in for: no network,
// no cost.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plo_capture/coach/coach_client.dart';
import 'package:plo_capture/screens/coach_review_screen.dart';

const _review = {
  'decisions': [
    {
      'street': 'preflop',
      'action_ref': 'your pot 3-bet from the button',
      'label': 'Clear',
      'verdict': 'A good 3-bet with a strong double-suited hand in position.',
      'why': 'The cutoff opened and you had position.',
      'next_time': 'Re-raise your best double-suited hands on the button.',
      'deep_dive': [
        'Blockers: your A♠ makes aces less likely for the cutoff.',
        'Reverse implied odds: your heart flush is only queen-high.',
        'Sizing: the pot-sized raise keeps you heads-up in position.',
        'Your flop plan: bet high, connected flops; slow down on low ones.',
      ],
      'numbers_used': ['n1'],
    },
    {
      'street': 'preflop',
      'action_ref': 'raising the full pot instead of a smaller raise',
      'label': 'Judgment call',
      'verdict': 'It depends on how tight the cutoff is.',
      'why': 'Against a tight opener a smaller raise keeps worse hands in.',
      'next_time': 'Notice how often each player opens.',
      'numbers_used': [],
    },
  ],
  'assumptions': ['I assumed everyone started with \$500.'],
  'follow_up_suggestions': ['What if the cutoff had 4-bet?'],
};

final Map<String, dynamic> _hand = {'hand_id': 'hand-1', 'schema_version': '1.0'};

void main() {
  setUp(reviewCache.clear);

  group('CoachReview.fromJson', () {
    test('reads the decisions, labels and assumptions', () {
      final r = CoachReview.fromJson(_review)!;
      expect(r.decisions, hasLength(2));
      expect(r.decisions[0].label, CoachLabel.clear);
      expect(r.decisions[1].label, CoachLabel.judgment);
      expect(r.decisions[1].label.words, "It depends on reads we don't have.");
      expect(r.assumptions, ['I assumed everyone started with \$500.']);
      expect(r.decisions[0].deepDive, hasLength(4));
      expect(r.decisions[1].deepDive, isEmpty); // older reviews have none
    });

    test('a review in the wrong shape is refused whole, never half-shown', () {
      expect(CoachReview.fromJson(null), isNull);
      expect(CoachReview.fromJson({'decisions': [], 'assumptions': []}), isNull);
      final badLabel = jsonDecode(jsonEncode(_review)) as Map<String, dynamic>;
      (badLabel['decisions'] as List)[0]['label'] = 'Obvious';
      expect(CoachReview.fromJson(badLabel), isNull);
    });
  });

  group('coachCanReview: when "Hand saved" offers the coach', () {
    Map<String, dynamic> hand({String game = 'cash', List<Map<String, dynamic>>? actions}) => {
          'session': {'game_type': game},
          'hero': {'seat': 4, 'cards': []},
          'actions': actions ??
              [
                {'street': 'preflop', 'seat': 3, 'action': 'raise', 'amount': 2000},
                {'street': 'preflop', 'seat': 4, 'action': 'call'},
              ],
        };

    test('a cash hand where the hero acted before the flop', () {
      expect(coachCanReview(hand(), enabled: true), isTrue);
    });

    test('never when the coach is off in this build (the normal build)', () {
      expect(coachCanReview(hand(), enabled: false), isFalse);
      expect(coachCanReview(hand()), isFalse); // tests run without COACH_URL
    });

    test('not for a spot saved before the hero acted, or a hero who only acted after the flop', () {
      expect(coachCanReview(hand(actions: [{'street': 'preflop', 'seat': 3, 'action': 'raise', 'amount': 2000}]), enabled: true),
          isFalse);
      expect(coachCanReview(hand(actions: [{'street': 'flop', 'seat': 4, 'action': 'check'}]), enabled: true), isFalse);
    });

    test('not for tournaments, which the coach can\'t review yet', () {
      expect(coachCanReview(hand(game: 'mtt'), enabled: true), isFalse);
    });
  });

  group('requestReview', () {
    test('sends the stored hand as plohand, with the invite code', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        // As the server sends it: UTF-8 bytes (the review has suit symbols like ♠).
        return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'review': _review, 'ms': 30000})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final reply = await requestReview(_hand, client: client, url: 'https://coach.test', invite: 'abc');
      expect(reply.ok, isTrue);
      expect(reply.review!.decisions[0].deepDive[0], startsWith('Blockers: your A♠'));
      expect(sent.url.toString(), 'https://coach.test/api/review');
      expect(sent.headers['x-invite'], 'abc');
      expect(jsonDecode(sent.body), {'plohand': _hand});
    });

    test("the server's plain message reaches the player", () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({'ok': false, 'message': "Tournament hands can't be reviewed yet. Cash games only for now."}),
          422));
      final reply = await requestReview(_hand, client: client, url: 'https://coach.test');
      expect(reply.ok, isFalse);
      expect(reply.message, "Tournament hands can't be reviewed yet. Cash games only for now.");
    });

    test('no connection, or a garbled answer, says so plainly', () async {
      for (final client in [
        MockClient((_) async => throw const SocketLikeException()),
        MockClient((_) async => http.Response('<html>502</html>', 502)),
        MockClient((_) async => http.Response(jsonEncode({'ok': true, 'review': {'decisions': []}}), 200)),
      ]) {
        final reply = await requestReview(_hand, client: client, url: 'https://coach.test');
        expect(reply.message, contains("couldn't reach the coach"));
      }
    });
  });

  group('CoachReviewScreen', () {
    Future<void> pump(WidgetTester t, ReviewRequest request) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: CoachReviewScreen(hand: _hand, request: request),
      ));
    }

    testWidgets('waits with a plain message, then shows one card per decision', (t) async {
      final answer = Completer<CoachReply>();
      await pump(t, (_) => answer.future);
      expect(find.text('Looking at your hand…'), findsOneWidget);
      expect(find.text('The coach takes about a minute.'), findsOneWidget);
      expect(find.text(disclosure), findsOneWidget);

      answer.complete(CoachReply.ok(CoachReview.fromJson(_review)!));
      await t.pumpAndSettle();
      expect(find.text('Your pot 3-bet from the button'), findsOneWidget);
      expect(find.text('A good 3-bet with a strong double-suited hand in position.'), findsOneWidget);
      expect(find.text('VERDICT'), findsWidgets);
      await t.scrollUntilVisible(find.text('What I assumed'), 200);
      expect(find.text('It depends on how tight the cutoff is.'), findsOneWidget);
      // The follow-up questions wait for "Ask a question": nothing that looks tappable and isn't.
      expect(find.textContaining('What if the cutoff'), findsNothing);
    });

    testWidgets('"Go deeper" is closed until tapped, then shows every point at 20 px', (t) async {
      await pump(t, (_) async => CoachReply.ok(CoachReview.fromJson(_review)!));
      await t.pumpAndSettle();
      expect(find.text('Go deeper'), findsOneWidget); // only the decision that has points
      expect(find.textContaining('Blockers:'), findsNothing);
      expect(t.getSize(find.ancestor(of: find.text('Go deeper'), matching: find.byType(InkWell))).height,
          greaterThanOrEqualTo(56));
      await t.tap(find.text('Go deeper'));
      await t.pumpAndSettle();
      final point = find.text('• Blockers: your A♠ makes aces less likely for the cutoff.');
      expect(point, findsOneWidget);
      expect(t.widget<Text>(point).style?.fontSize, greaterThanOrEqualTo(20));
      expect(find.textContaining('Your flop plan:'), findsOneWidget);
    });

    testWidgets('a problem is said plainly, and Try again asks once more', (t) async {
      var calls = 0;
      await pump(t, (_) async {
        calls++;
        return calls == 1
            ? const CoachReply.failed("Sorry, I couldn't review that hand. Please try again.")
            : CoachReply.ok(CoachReview.fromJson(_review)!);
      });
      await t.pumpAndSettle();
      expect(find.text("Sorry, I couldn't review that hand. Please try again."), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Your pot 3-bet from the button'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('a hand already reviewed this session is shown again without asking (or paying) twice', (t) async {
      var calls = 0;
      Future<CoachReply> request(Map<String, dynamic> _) async {
        calls++;
        return CoachReply.ok(CoachReview.fromJson(_review)!);
      }

      await pump(t, request);
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox()); // the screen is closed…
      await pump(t, request); // …and opened again for the same hand
      await t.pumpAndSettle();
      expect(find.text('Your pot 3-bet from the button'), findsOneWidget);
      expect(calls, 1);
    });

    testWidgets('buttons are at least 56 px tall and review text at least 20 px', (t) async {
      await pump(t, (_) async => CoachReply.ok(CoachReview.fromJson(_review)!));
      await t.pumpAndSettle();
      for (final text in [
        'A good 3-bet with a strong double-suited hand in position.',
        'The cutoff opened and you had position.',
        'Re-raise your best double-suited hands on the button.',
      ]) {
        final w = t.widget<Text>(find.text(text));
        expect(w.style?.fontSize, greaterThanOrEqualTo(20), reason: text);
      }
      await t.scrollUntilVisible(find.text('Back to the hand'), 200);
      expect(t.getSize(find.ancestor(of: find.text('Back to the hand'), matching: find.byType(SizedBox)).first).height,
          greaterThanOrEqualTo(56));
    });
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
