# JOINT SOLUTION: route decision-spot captures to review, not population

**Authors:** Monker Killer (consumer) + PLO Show / HandHistory (producer), 2026-06-10.
**Trigger:** owner captured one hand, exported a population bundle, got an empty zip
(`accepted_hands:0, refusals:{noHeroAction:1}`).

## Diagnosis (agreed, code-confirmed)

The owner captured a **decision spot** — "here's the spot I'm facing, what should I do?" — with
no action recorded for their own seat. The app saved it correctly as a decision spot
(`meta.complete == false`), but the **only** export button (`hand_list_screen.dart::_exportForSolver`)
funnels every hand into the **population aggregator** (`solver_export.dart::exportPopulation`),
which legitimately requires the hero's action (it's frequency data) and so refused with
`noHeroAction`. Empty bundle.

**This is not a bug in either pipeline — it's a missing route.** The capture is a perfect input
for the *review* product and was sent to the *population* product.

## The key fact that makes the fix small

The decision-spot vs completed-hand distinction **already exists end-to-end** in the app:

- `hand_recorder.dart::buildHandJson(complete:false)` → serialized as **`meta.complete == false`**.
- Mirrored to the DB **`is_spot`** column (`hand_store.dart`).
- Surfaced in the UI: a dedicated **"Save spot — your decision"** button (separate from "Save
  hand"), and gold-bookmarked **"Decision spot"** rows in the hand list.

So the routing signal is already recorded on every hand. **The fix is routing, not new data.**

## Two products, two requirements (the design principle)

| | Population node-locking | Import-spot **review** |
|---|---|---|
| Needs hero's action? | **Yes** (it's the frequency) | **No** — optional (only powers "how you played vs solve") |
| Artifact | aggregated `fold/call/pot` CSVs per node (the zip) | **one raw `.plohand.json`** per spot |
| Right input | `complete:true` hands | `complete:false` spots **and** `complete:true` hands |
| Consumer entry | `monker_csv::load_monker_spot` (verified) | desktop **IMPORT HAND** → `import.rs` (verified) |

**Route by `meta.complete`.** Never send a `complete:false` spot into the population aggregator
as a contributor; send it to the review export.

## Consumer-side guarantees (Monker Killer — already true, no change needed for the loop)

- `import.rs` makes `hero_action: Option<String>`. A decision-spot record (no hero action)
  **imports and solves fine**; the "how you played vs solve" readout just doesn't render. This
  is validated — three real agent-built captures + the owner's-style spots round-trip correctly.
- Position labels aligned: the producer's `MP` (seat-2) is handled (`LJ`|`MP` → backend 2).
- A decision-spot capture carries everything the review importer needs — hero cards, positions,
  stacks (hero exact, villains `is_approx`), straddle/regime, and the villain line up to the
  hero's node. Field-audited: nothing missing.
- The consumer does **not** read `meta.complete` today (it keys off hero-action presence), so
  the producer-side routing is sufficient. Adding `meta.complete` to the schema (below) lets the
  consumer optionally *badge* "decision spot" explicitly later.

## Producer-side changes (PLO Show)

**Minimal first step (closes the loop now, ~3 lines):**
- In `capture_screen.dart`, surface the existing **`_copyJson`** action (currently only on the
  completed-hand `_resultPanel`, ~line 602) **also next to the "Save spot" button** (~line
  537–556). The owner taps "Copy spot JSON", pastes into `*.plohand.json`, drops it in
  `/home/skynet/HandHistory/sample_captures/`, and the consumer validates it immediately with
  `cargo run --example import_bundle -p solver -- sample_captures`.

**Fuller UX (follow-up):**
- `lib/export/review_export.dart` (new): `buildReviewExport(handJson)` → raw single record +
  human-meaningful filename. No re-snap/aggregate/refuse — the consumer's `import.rs` owns all
  of that.
- `lib/export/download_web.dart` (new fn): `downloadText(filename, contents)` — single-file
  download (review wants one record per file, not a zip).
- `hand_list_screen.dart`: per-row **"Export for review"** action (works for any hand;
  emphasized/primary for `is_spot == 1` rows). And in `_exportForSolver`, **partition out
  `complete:false` spots** from `exportPopulation` and, in `_showExportSummary`, tell the user
  "N decision spots are for review — export individually for Import Hand" instead of silently
  producing an empty bundle.
- `noHeroAction` stays in the enum for genuinely-corrupt completed hands, but stops firing in
  normal use because spots are partitioned upstream.

## Contract fix (both sides)

`meta.complete` is written by the app and mirrored to `is_spot`, but is **NOT declared in
`plo-hand-history.schema.json`** (`meta` lists only `notes/tags/marked_for_review/capture_seconds`).
Add `meta.complete` (boolean, default `true`) to the published schema — it's now a load-bearing
routing field, so both sides should treat it as stable.

## Who does what

- **Producer (PLO Show agent):** the minimal `_copyJson`-on-spot-panel step now; then the fuller
  review-export UX; add `meta.complete` to the schema.
- **Consumer (Monker Killer):** nothing required for the loop — `import.rs` already handles
  decision spots. Will validate each exported spot and report any contract delta. May add an
  explicit "decision spot" badge once `meta.complete` is in the schema.

## End-to-end loop, once the minimal step lands

Capture a spot → "Copy spot JSON" → paste to `sample_captures/x.plohand.json` →
`cargo run --release --example import_bundle -p solver -- /home/skynet/HandHistory/sample_captures`
→ consumer reports the snapped spot (or refusal) → in the desktop app, **IMPORT HAND** on that
file shows the solve. That's the full review loop the owner was reaching for.
