# HANDOFF: Population-read export for Monker node-locking

**From:** Monker Killer side (owns the canonicalization + the reverse-engineered Monker CSV bridge).
**To:** the PLO Show / HandHistory exporter author.
**Goal:** let you produce solver-ready population output from captured live hands without reading our code.

---

## ⚠️ READ THIS FIRST — the premise needs one correction

You wrote "you own the Monker tree/range format." **I half-own it, and the half you're
asking about is the half I don't.** Being straight about this up front saves us both a
debugging nightmare later, because a confidently-wrong sizing-code or notation spec is the
worst possible thing to ship into a node-lock.

There are **two different "Monkers"** in play, and your eight questions are all aimed at the
*first* one:

| | **(A) MonkerSolver (the commercial tool)** | **(B) Monker Killer (our solver)** |
|---|---|---|
| Native files | `*.tree`, `ranges/.../*.rng`, node paths like `0.0.40100.rng`, hand notation `(KA)A2` | our own packed artifacts; no `.tree`/`.rng` at all |
| Node id | dotted action+sizing path | `history_hash` (u64) → `node_id` (u32) |
| Hand class | `(KA)A2` parenthesis-suit notation | `CanonicalHand(u32)` → `"AAKK ds"`-style label |

**What our codebase demonstrably knows** (with proof, can spec byte-for-byte):
- The **suit-isomorphism canonical form** (the 16,432-class reduction) — §5.
- Monker's **CSV *export*** format and EV units — reverse-engineered and *verified against
  Monker's own status display* — §6. **Note this is Monker's EXPORT (read), the inverse of the
  range-file IMPORT you need.**
- The combo-weighted **aggregation math** for collapsing physical hands → classes — §6/§7.

**What our codebase does NOT contain** (no parser, no sample, no doc — verified by an
exhaustive sweep of both repos):
- The `.tree` format, the `.rng` *write* format, the `ranges/Omaha/8-way/100bb/` layout,
  the dotted **node-path encoding** and the `40100` **sizing code**, and the `(KA)A2`
  **notation rules**.

So below, every answer is tagged:

- ✅ **AUTHORITATIVE** — from our code; mirror it byte-for-byte.
- ⚠️ **UNVERIFIED** — my general knowledge of MonkerSolver conventions; *plausible but
  must be confirmed empirically before you wire it.*
- ❌ **NOT OWNED** — get it from MonkerSolver docs, or reverse-engineer it (protocol in §9).

**The single most important recommendation** (see §9): do **not** hand-author Monker's
`.rng`/node-path/`(KA)A2` strings from a spec you can't verify. Instead, **export one known
range out of MonkerSolver, let *it* tell you its own node paths and class strings, and join
on physical hands.** That is exactly how we nailed the CSV format, and it's the only way to
be byte-exact against a closed format.

---

## 1. Consumption model

⚠️ **UNVERIFIED for MonkerSolver / ✅ for our pipeline.**

Your stated target — *writing observed population frequencies into `.rng` weight fields for
node-locking* — is the right *shape* of the goal, and nothing in the realization-b2 or solve3
work changed it. Those are separate efforts:

- **realization-b2** consumes Monker **EV exports** (postflop root-node EV) to calibrate a
  realization discount; it does **not** produce or consume range weights. Not relevant to your
  exporter.
- **solve3** is an external equity baseline served from a bundled CSV; also not a node-lock sink.

So node-locking is still "frequencies → weights." **But** the concrete artifact depends on
which sink you actually feed:

- **If the sink is MonkerSolver itself** (you load the `.rng` into Monker and lock the node):
  the artifact is a native `.rng` whose per-class **weight** field carries your observed
  frequency. The weight scale, EV placeholder, sparse-vs-full rules, and node-path are all
  MonkerSolver's — see §3/§6, flagged ❌/⚠️, and confirm via §9.
- **If the sink is Monker Killer's vault** (recommended interim — we own it, it's lossless,
  and we can consume it tomorrow): emit the **3-file CSV** we already parse (§6, ✅). Our
  `monker_csv::load_monker_spot` ingests it directly and our `monker_vault.db` can store it.

My strong advice: **build the CSV path first** (fully specified here, zero guesswork), and
treat the native-`.rng` path as a fast-follow once you've round-tripped one real Monker file
through §9.

---

## 2. Target tree(s)

❌ **NOT OWNED** (MonkerSolver filenames/layout) / ✅ for the game definitions.

I cannot confirm the canonical `.tree` filenames (`8max_100bb_btn_Str.tree`, etc.) or the
`ranges/Omaha/8-way/100bb/<path>.rng` directory layout — those are MonkerSolver's filesystem
conventions and are not in our repos. **Confirm by inspecting your MonkerSolver install's
`trees/` and `ranges/` directories directly.**

What I *can* pin authoritatively is the **game definitions** you must target, because they
must match what we solve (so cross-checks line up):

- **8-max, 100bb effective, pot-limit, no ante, no rake.**
- Three straddle regimes, each its own tree: **no-straddle**, **button straddle** (2× bb,
  SB acts first, button straddler closes), **UTG straddle** (2× bb, UTG+1 acts first, UTG
  straddler closes).
- Backend seat order (action order, 0..7): `UTG=0, UTG1=1, LJ=2, HJ=3, CO=4, BTN=5, SB=6, BB=7`.

You need (at least) a non-straddle 8-max tree and a button-straddle 8-max tree. Their exact
MonkerSolver filenames: **read them off the install.**

---

## 3. Node-path encoding (`0.0.40100.rng`)

❌ **NOT OWNED.** This is the single biggest "do not guess" item.

Our internal node id is **not** Monker's dotted path. For the record (✅, in case it helps you
reason), ours is a packed history hash:

```
// pack_history (solver/src/persist.rs): Fold=0, Call=1, Raise=2
h = Σ_i action_i << (2*i)   |   (history_len << 56)
```

Monker's `0.0.40100.rng` dotted path — segment meanings and especially the `40100` **sizing
code** — is **MonkerSolver-internal and not present anywhere in our code.** ⚠️ My *general*
understanding is that such codes encode an action class plus a pot-fraction/size bucket, but I
do **not** have a verified action→code mapping and will not invent one — a wrong sizing code
silently writes your weights onto the wrong node.

**How to get it for real (§9):** in MonkerSolver, build/open the target tree, navigate to a
node whose action sequence you *know* (e.g. SB-open → BB-3bet), export/inspect its `.rng`, and
read the path MonkerSolver assigns. Map a handful of known lines → observed paths; the sizing
code's structure falls out immediately. Send me 3–4 `(line, path)` pairs and I'll help you
decode the scheme precisely.

---

## 4. Line → node mapping (real bet sizes → discrete tree node)

✅ **AUTHORITATIVE for the snapping principle** / ❌ for the final node-path string.

This is exactly the problem we just solved on our side (`solver/src/import.rs`), and the
principle transfers directly:

- **Snap by ACTION TYPE, not amount.** Walk the line in action order; classify each voluntary
  action by its **bet level**, not its chip size:
  - first voluntary raise = **open** (bet level 1)
  - raise over an open = **3-bet** (level 2)
  - raise over a 3-bet = **4-bet** (level 3)
  - raise over a 4-bet = **5-bet / get-in** (level 4 = cap)
  - a non-raise that matches the current bet = **call**; `fold` = fold.
- **The exact RAISE-TO amount only *scores fidelity*; it never picks the node.** A min-3-bet
  and a 3.5×-pot 3-bet both map to the level-2 node.
- **Reject, don't fake**, anything that can't form a legal line: a *limp* (a call at bet
  level 0 — our trees are no-limp), a 5th raise (past the get-in cap), or sizes/positions that
  don't replay legally. (Our importer has 15 such refusal codes; mirror the spirit.)

**Positions / dead blinds / button-straddle onto the root:**

- The tree root's first-to-act is fixed per straddle regime (§2): no-straddle → UTG; button
  straddle → **SB first, button straddler closes**; UTG straddle → UTG+1 first.
- **Re-key by seat, then replay in the tree's action order.** Do **not** assume your capture's
  temporal order equals the tree's action order — under a button straddle a room that runs
  "UTG-first" records actions in a different order than the SB-first tree consumes them.
  Bucket each seat's actions, then walk the tree's order popping each seat's next action.
  (This is the verified fix from our strategist review; both `utg_first_straddler_last` and
  `sb_first` capture rules map faithfully because both put the button last.)
- **Dead/missed blinds:** they change the *pot*, not the *action node*. For node identity
  they're irrelevant; for the size-fidelity score they affect the pot baseline. If a dead
  blind makes the line illegal in the clean tree, refuse the hand rather than approximate it.
- The **final node** is the state right *before* the hero's first voluntary decision.

The action→tree-action mapping above is ✅. Turning the resulting (regime, level-sequence)
into Monker's dotted `.rng` filename is ❌ — resolve via §9.

---

## 5. Hand-class canonicalization

✅ **AUTHORITATIVE for the orbit / suit-isomorphism** (paste-and-mirror below).
⚠️ **for emitting Monker's `(KA)A2` *string*** (the formatting is Monker's, not ours).

Two distinct things hide inside "canonicalization," and conflating them is a trap:

**(a) The orbit reduction (which hands are the same class) — OURS, exact, mirror this:**

The four suits are interchangeable preflop; S₄ acting on C(52,4)=270,725 hands yields exactly
**16,432 orbits** (Burnside, verified in code). Algorithm (`solver/src/iso.rs::canonicalize`,
verbatim — ranks `2..A` = `0..12`, suits `h,c,d,s` = `0,1,2,3`, card = `suit*13 + rank`):

```rust
pub fn canonicalize(hand: &[u8; 4]) -> CanonicalHand {
    // 1. Per physical suit, a 13-bit mask of present ranks.
    let mut suit_masks: [u16; 4] = [0; 4];
    for &card in hand {
        let rank = (card % 13) as u32;
        let suit = (card / 13) as usize;
        suit_masks[suit] |= 1u16 << rank;
    }
    // 2. Sort masks DESCENDING — most-loaded suit becomes canonical label 0.
    //    (Ties are safe: identical masks produce identical output.)
    suit_masks.sort_unstable_by(|a, b| b.cmp(a));
    // 3. Emit ranks per canonical suit label, high rank first, one byte/card:
    //    byte = label*13 + rank, packed big-endian into a u32.
    let mut bytes = [0u8; 4];
    let mut idx = 0;
    for (label, &mask) in suit_masks.iter().enumerate() {
        let mut m = mask;
        while m != 0 {
            let rank = 15 - m.leading_zeros() as u8;
            bytes[idx] = label as u8 * 13 + rank;
            idx += 1;
            m &= !(1u16 << rank);
        }
    }
    CanonicalHand(u32::from_be_bytes(bytes))   // the orbit key
}
```

Worked example for `Ah Kh As 2d`:
- masks: hearts `{A,K}`, spades `{A}`, diamonds `{2}`, clubs `{}`.
- sort desc: `{A,K}` (label 0), `{A}` (label 1), `{2}` (label 2), `{}` (label 3).
- emit: `A,K` (label 0), `A` (label 1), `2` (label 2) → canonical, one ace+king of the
  top suit, an ace of a second suit, a deuce of a third. **This is the same orbit Monker
  writes as `(KA)A2`** — two cards sharing a suit (the parenthesized pair), then two
  off-suit singles.

The **dense index** `0..16_432` is `enumerate_canonical_hands()` sorted ascending by the u32
packing — **stable across machines**, so it's a safe join key.

**(b) Emitting Monker's `(KA)A2` string — ⚠️ formatting is Monker's:** the *grouping* logic
(parenthesize cards that share a suit; singles are mutually off-suit) matches the orbit above,
but Monker's exact rank ordering inside/across groups and its tie-breaks are **its** convention,
not ours, and I won't assert them blind. **Don't hand-format these.** Instead (see §9): export
a *full* range from MonkerSolver once — it enumerates every class in *its own* `(…)` string —
then build a one-time join table `Monker-string ↔ physical-hand ↔ our canonical u32 index` by
canonicalizing the physical hands. After that you map by table lookup, byte-exact, forever.

---

## 6. `.rng` contents

❌ **NOT OWNED for native `.rng`** / ✅ **for the CSV bridge we already consume.**

I can't confirm native-`.rng` line format, the `-1000.0` EV placeholder, weight scale, or
sparse-vs-full enumeration — those are MonkerSolver's. ⚠️ A `weight;EV` line with a sentinel
EV is consistent with what I'd expect, and `-1000.0` as a "no-EV/placeholder" sentinel is
plausible — **but verify via §9** (`-1000` also shows up as a *real* milli-chip EV in exports,
see below, so don't assume a literal `-1000.0` is always a placeholder).

What is ✅ **fully specified** is the Monker **CSV** schema we parse and have verified against
Monker's UI — emit this and we ingest it with zero guesswork:

- **Three files per node**, one per action: fold-range, call-range, pot-range.
- Each row: `HAND,FREQ,EV`
  - `HAND` = **8-char physical hand**, `<rank><suit>×4`, ranks `2-9TJQKA`, suits `hcds`
    (e.g. `AhAs3s2s`). Physical, suit-explicit — **not** the `(…)` notation.
  - `FREQ` ∈ `[0,1]` for that file's action; a mixed hand appears in multiple files and its
    freqs sum to ~1.0 across the three.
  - `EV` in **milli-chips**, where **1 chip = 0.5 BB** (Monker normalizes SB=1, BB=2 chips).
    Convert with `BB = EV_mchip × 0.0005`. (Verified: Monker's `-357 mchip` SB display =
    −17.9 bb/100. ✓)
- A full preflop-root 8-max spot has **270,725** distinct physical hands; deeper nodes fewer
  (blockers). Header line starts with `HAND` (case-insensitive) and is skipped.

For node-locking you want **weights**, not EV — so in the CSV path, put your **observed
population frequency** in the `FREQ` column and set `EV` to `0` (or carry a real EV if you
have one). We aggregate physical→canonical combo-weighted; see §7.

---

## 7. Bucketing knobs

✅ **AUTHORITATIVE.**

- **Normalize to BB (stake-independent): YES, always.** Everything keys off 100bb effective.
  Convert chips→bb with the table's big blind; under a straddle measure depth in
  **straddle-corrected bb** = `min(hero, largest-still-in-villain)/bb × (2.0 / straddle_ratio)`
  where `straddle_ratio = straddle_amount/bb`. (A $10 straddle on a $5 bb = exactly 2× → no
  rescale; the canonical 2/5 $10 / $500-stack spot computes to 100bb.)
- **Stack-depth band** (a hand only belongs in a 100bb node if it's near 100bb):
  faithful `[85,115]`, accept-with-disclosure `[60,140]`, **refuse outside `[60,140]`**.
  Straddle-ratio tolerance: faithful `[1.90,2.10]`, accept `[1.75,2.25]`, refuse outside.
- **Approximate villain stacks:** when the band-defining stack is an estimate, **tighten the
  refuse edges by ±10% and round toward refuse** at the 60/140 boundaries. (These two tunables
  — the ±10% guard and the straddle-ratio band — are population reads; instrument near-edge
  refusals and retune after ~50.)
- **Min sample size per node before emitting:** ❌ not a number our code sets — it's a
  statistical-confidence call for *your* node-lock. My recommendation: **don't emit a node
  weight set below ~50–100 observed hands at that node**, and **carry the observed count `N`
  in your artifact** (a sidecar `count` column or a per-node manifest) so the consumer can
  weight or threshold. A node-lock on 6 hands is noise dressed as signal.
- **Partial "decision-spot" hands:** if the capture stops at the hero's decision (no showdown,
  no later streets), that's *fine* — preflop node-locking only needs the line up to the node
  and the hand class. A hand with no recorded action at the node it should reach → **drop it**
  (don't fabricate the missing action).

---

## 8. Packaging

⚠️/✅ mixed.

- **For native MonkerSolver:** ❌ loose-`.rng`-in-tree-dir vs bundle is Monker's convention —
  confirm on the install. **Critical merge hazard (⚠️):** writing population weights into the
  *same* `.rng` files that hold solved strategy will **overwrite** the solve. Never write your
  population data over a solved range in place. Keep population output in a **separate,
  clearly-named tree/range directory** (e.g. `ranges/.../pop_observed/`), and let the node-lock
  step in Monker pull from it — don't clobber `ranges/.../solved/`.
- **For the CSV bridge (recommended):** a **directory per node** containing the 3 action CSVs,
  named by a stable node id you control (your line encoding), plus a **manifest** mapping
  `node_dir → (regime, action-line, observed N, bb-band)`. That manifest is what lets us
  (or Monker, post-conversion) place each node correctly without trusting filename parsing.
- **Naming to distinguish population vs solved:** prefix/segregate by directory and stamp the
  artifact (`source: "population_observed"`, `captured_through: <date>`, `n_hands`). Make it
  impossible to confuse an observed-frequency file with a solved-strategy file at a glance.

---

## 9. ⭐ The verification protocol (do this before wiring anything ❌/⚠️)

This is how the CSV format above got nailed, and it's the only way to be byte-exact against a
closed format. One afternoon here de-risks the entire export:

1. In **MonkerSolver**, open your target tree (e.g. button-straddle 8-max 100bb).
2. Navigate to **one node whose action line you know exactly** (e.g. folds-to-CO open).
3. **Export / inspect** that node's range file. Capture: the **node-path filename**
   (`0.0.40100.rng`-style), the **full file contents** (a few lines), and the **class strings**
   it uses (`(KA)A2`-style).
4. Repeat for ~4 nodes spanning open / 3-bet / 4-bet so the sizing-code structure is visible.
5. Export **one full range** so you have MonkerSolver's complete class-string enumeration.
6. Send me those artifacts. I will: decode the node-path + sizing code precisely, confirm the
   `.rng` line format / weight scale / EV sentinel, and generate the
   `Monker-class-string ↔ canonical-index` join table (§5b) so your exporter maps by lookup,
   not by guesswork.

Until step 6 is done, **build the CSV path (§6, fully specified) — it needs none of the
unverified pieces and we can consume it immediately.**

---

## TL;DR

- I own the **orbit canonicalization** (§5a, paste it) and the **Monker CSV bridge** (§6,
  verified) — build against those today with zero guesswork.
- I do **not** own Monker's native `.tree`/`.rng`/node-path/`(KA)A2` formats — and I won't
  fake them. Get them via the §9 export-and-diff protocol; send me 4 known-line `.rng`
  exports + one full range and I'll spec them exactly.
- Snap by **action type not amount**, **re-key by seat then replay in tree order**, normalize
  to **bb**, refuse off-band/limped/over-cap lines, carry **observed N per node**, and **never
  overwrite solved ranges** with population weights.
