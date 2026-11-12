// The AI coach (The Green Room, ai-hand-reviewer DECISIONS.md D30): a logged hand goes to the coach server, which
// reviews the player's decisions before the flop and sends back a review.
//
// Where the server is and its invite code are set when the app is built:
//   flutter build web --dart-define=COACH_URL=https://… --dart-define=COACH_INVITE=…
// Without COACH_URL the coach is switched off and no button shows, so a normal build is unchanged.
//
// Every number in a review was produced by the server's calculators and checked there; this file only carries the
// hand and the answer.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String coachUrl = String.fromEnvironment('COACH_URL');
const String coachInvite = String.fromEnvironment('COACH_INVITE');

/// True when this build can ask the coach.
const bool coachEnabled = coachUrl != '';

/// Whether to offer the coach for this stored hand. The coach reviews what the player did before the flop, in cash
/// games: so the coach must be on in this build, and the hero must have a preflop action (a spot saved before the
/// hero acted has nothing to review).
bool coachCanReview(Map<String, dynamic> hand, {bool enabled = coachEnabled}) {
  if (!enabled || hand['session']?['game_type'] != 'cash') return false;
  final hero = hand['hero']?['seat'];
  final actions = (hand['actions'] as List?) ?? const [];
  return actions.any((a) => a is Map && a['street'] == 'preflop' && a['seat'] == hero);
}

/// The three labels, and what each means in plain words (the coach contract).
enum CoachLabel {
  clear('Clear', 'Most strong players would agree.'),
  close('Close', 'Good players could go either way.'),
  judgment('Judgment call', "It depends on reads we don't have.");

  const CoachLabel(this.name_, this.words);
  final String name_;
  final String words;

  static CoachLabel? parse(Object? s) {
    for (final l in values) {
      if (l.name_ == s) return l;
    }
    return null;
  }
}

class CoachDecision {
  final String actionRef;
  final CoachLabel label;
  final String verdict;
  final String why;
  final String nextTime;
  const CoachDecision({
    required this.actionRef,
    required this.label,
    required this.verdict,
    required this.why,
    required this.nextTime,
  });
}

class CoachReview {
  final List<CoachDecision> decisions;
  final List<String> assumptions;
  const CoachReview(this.decisions, this.assumptions);

  /// Reads the server's `review`. Returns null if it isn't the expected shape, so a bad answer is never half-shown.
  static CoachReview? fromJson(Object? json) {
    if (json is! Map) return null;
    final ds = json['decisions'];
    final as = json['assumptions'];
    if (ds is! List || ds.isEmpty || as is! List) return null;
    final decisions = <CoachDecision>[];
    for (final d in ds) {
      if (d is! Map) return null;
      final label = CoachLabel.parse(d['label']);
      final parts = [d['action_ref'], d['verdict'], d['why'], d['next_time']];
      if (label == null || parts.any((p) => p is! String)) return null;
      decisions.add(CoachDecision(
        actionRef: d['action_ref'] as String,
        label: label,
        verdict: d['verdict'] as String,
        why: d['why'] as String,
        nextTime: d['next_time'] as String,
      ));
    }
    return CoachReview(decisions, [for (final a in as) if (a is String) a]);
  }
}

/// A review, or the plain-English reason there isn't one.
class CoachReply {
  final CoachReview? review;
  final String? message;
  const CoachReply.ok(CoachReview this.review) : message = null;
  const CoachReply.failed(String this.message) : review = null;
  bool get ok => review != null;
}

const _sorry = "Sorry, I couldn't reach the coach. Please check your connection and try again.";

/// Asks the coach to review [hand], the hand exactly as the app stores it (plo-hand-history.schema.json).
/// The coach takes about half a minute; this waits up to three minutes.
Future<CoachReply> requestReview(
  Map<String, dynamic> hand, {
  http.Client? client,
  String url = coachUrl,
  String invite = coachInvite,
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .post(
          Uri.parse('$url/api/review'),
          headers: {'content-type': 'application/json', 'x-invite': invite},
          body: jsonEncode({'plohand': hand}),
        )
        .timeout(const Duration(minutes: 3));
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      return const CoachReply.failed(_sorry);
    }
    if (body is Map && body['ok'] == true) {
      final review = CoachReview.fromJson(body['review']);
      return review == null ? const CoachReply.failed(_sorry) : CoachReply.ok(review);
    }
    if (body is Map && body['message'] is String) return CoachReply.failed(body['message'] as String);
    return const CoachReply.failed(_sorry);
  } on TimeoutException {
    return const CoachReply.failed('The coach took too long. Please try again.');
  } catch (_) {
    return const CoachReply.failed(_sorry);
  } finally {
    if (client == null) c.close();
  }
}

/// Reviews already received this session, by hand id, so going back and forth never pays for one twice.
final Map<String, CoachReview> reviewCache = {};
