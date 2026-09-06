# PLO Capture — project context

Mobile app (Flutter) for fast tap-based capture of live 4-card Pot Limit Omaha
hand histories. Cash and MTT. The long-term goal: the captured hands feed a
stats engine and eventually a custom high-speed PLO solver ("Monker killer"),
so data quality and game-tree fidelity matter more than anything else.

The owner is a live PLO player in Texas (8-max games, button/UTG straddles
common). Entry speed at the table is the UX north star: a logged hand should
take ~15 seconds of discreet tapping. `capture_seconds` is recorded per hand
to measure this.

## Architecture

- `lib/plo_engine.dart` — THE core. Pure-Dart action-order state machine +
  pot-limit math. No Flutter imports. The UI renders only what
  `legalActions()` returns; `apply()` advances state and emits log entries
  that map 1:1 onto the hand history schema. Tests in
  `test/hand_engine_test.dart`.
- `lib/hand_recorder.dart` — `HandConfig` (immutable hand setup; also the
  engine factory) + `buildHandJson()` serializing to the canonical schema.
- `lib/hand_loader.dart` — inverse of the recorder; parses stored JSON back
  to a replayable form.
- `lib/db/hand_store.dart` — sqflite. The full canonical JSON blob is the
  source of truth; a few columns (hero_net, pot, marked, timestamps) are
  duplicated for list queries. Never make the columns authoritative.
- `lib/screens/` — session_list → hand_list → capture / replayer.
- `lib/widgets/seat_ring.dart` — the signature UI: table-mirroring ring, hero
  anchored bottom, amber pointer on the actor. Reused by capture AND replayer.
- Canonical JSON Schema (v1.0, plo4-only, game_type cash|mtt) lives outside
  the app repo: `plo-hand-history.schema.json`. There is also a Python mirror
  of the engine (`reference_engine.py`) used to verify algorithm changes and
  intended as the seed of a future backend import validator. Keep Dart and
  Python engines in sync when touching game logic.

## Invariants — do not break

1. All amounts are integers in the smallest unit: cents (cash) or chips
   (MTT). Never floats.
2. Raise amounts are always RAISE-TO (total street commitment), never
   increments.
3. Pot-limit max: toCallInc = currentBet − actorStreetCommit;
   maxRaiseTo = currentBet + (pot + toCallInc), stack-capped.
4. The per-street action ring persists through raises. Under a button
   straddle with the utg_first_straddler_last rule, the order
   (UTG … CO, SB, BB, straddler) holds for the ENTIRE preflop round —
   rebuilding the queue in physical seat order after a raise is a bug we
   already fixed once.
5. Short all-ins (increment < last full raise) do NOT reopen raising for
   players who already acted.
6. Antes (MTT BB ante) are dead money: in the pot, never setting the facing
   bet.
7. Undo and the replayer are deterministic replays: rebuild the engine from
   `HandConfig`, re-apply actions. Never mutate engine state backwards.
8. Partial information is first-class: approximate stacks, partial
   showdowns. Don't "fix" unknown data by inventing values.
9. 4-card PLO only (no plo5/plo6, no SNG). Don't re-add variant plumbing.

## Verification habits used so far

- Engine changes are mirrored in `reference_engine.py` and exercised against
  the canonical example hand (2/5, $10 button straddle, two limpers, CO iso
  to exactly $57, river all-in stack-capped at $1,042 below the $1,175 pot
  max, final pot $2,554) plus: sb_first rule, UTG straddle option, short
  all-in lockout, illegal-action rejection, and replay-at-every-step.
- `flutter test` runs the Dart suite; keep it green.

## Roadmap (agreed order)

1. Stats engine over SQLite: PLO-adapted positional frequencies, straddle-pot
   vs non-straddle win rates, multiway vs HU, split cash/MTT from day one.
2. Per-seat stack editing on the seat ring (long-press). (Side-pot/split-pot
   math shipped: `engine.computePots()` layers totalCommit into main/side
   pots with uncalled-bet return; recorder serializes multi-pot + split
   winners; capture UI resolves pots by tap, chops by multi-tap.)
3. MTT depth: ICM context, bounties, payout structures (data already
   captured).
4. Export/aggregation layer: suit-isomorphism normalization, per-node
   population frequencies for solver node-locking.

## Known scaffold pragmatism

- `chipMode` in `lib/util.dart` is a global display toggle (cash $ vs MTT
  chips); a threaded formatter is the cleaner refactor.
- Results support side pots and split pots (chops); hi/lo `share_type` values
  exist in the schema but the UI never emits them (PLO high-only).
- Existing DBs from before the variant-column removal need a wipe (app is
  pre-release; no migration written).
