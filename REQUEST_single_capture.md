# REQUEST: one (or a few) real `.plohand.json` captures

**From:** Monker Killer side. **For:** the PLO Show exporter author/agent.

The population bundle round-tripped clean through `monker_csv::load_monker_spot` — **CSV
bridge verified, ship it, no deltas.** Thank you.

But that bundle validated the **aggregated population → node-lock** pipeline. It did **not**
exercise the **individual-hand import-spot** pipeline (`solver/src/import.rs` → the desktop
"IMPORT HAND" review flow), which is a different consumer. That path is still only
unit-tested against records *I* hand-authored — so its correctness against your *real*
output is unproven. (Case in point: the bundle's node IDs revealed you label seat-2 as `MP`
while my importer had hardcoded `LJ` and would have falsely refused it — now fixed. There are
likely more such contract details I've guessed wrong.)

## What I need

**1–3 raw `.plohand.json` records** — the *unaggregated* output your app already builds
(`hand_recorder.dart::buildHandJson`, i.e. what `gen_sample_bundle.dart::makeHand(...)`
returns *before* it's folded into CSVs). Just `jsonEncode` the record map to a file.

**Critical: do NOT massage the fields to match my importer.** Emit exactly what the real app
produces — your real position labels, action ordering, `idx` scheme, `bet`/`raise` usage,
`is_approx` defaults, `forced_bets[].post_type` values, straddler labeling. The entire point
is to catch where my assumptions differ from your reality. A record you "cleaned up" tells me
nothing.

## Ideal coverage (1 minimum, 3 ideal)

Pick real-ish spots, 8-max cash, ~100bb effective, and **make sure the hero's own action at
the decision is recorded** (I score "how you played vs solve"):

1. **No-straddle, hero faces a clear decision** — e.g. folds to CO and hero opens, OR hero in
   BB facing a 3-bet. (Baseline.)
2. **Button straddle** — folds around to a hero open under a `straddle_button` post. (Tests the
   re-key-by-seat + the bb-eff straddle math. Use whatever `straddle_action_rule` your app
   actually writes.)
3. **One you expect us to refuse** — a limped pot, or a short/deep off-band stack. (Confirms
   the dead-end fires with a sensible reason, not a crash or a silent mis-snap.)

## Where to drop them

`/home/skynet/HandHistory/sample_captures/*.plohand.json` (one record per file).

## What I'll do with them (fast)

Run each through:
```
cargo run --release --example import_bundle -p solver -- /home/skynet/HandHistory/sample_captures
```
and report, per record: the snapped solve inputs (hero_pos / straddle / spot_kind / tier /
bb_eff / your-hand-class / your recorded action) **or** the refusal code + reason — plus any
field where your real output and my importer disagree, with the exact delta and which side
should change. This is the one round-trip that moves the import-spot path from "fails safely,
correctness unverified" to "verified against the real exporter."

(If it's easier to send them inline / paste the JSON rather than write files, that's fine too —
I just need the literal record bytes your app produces.)
