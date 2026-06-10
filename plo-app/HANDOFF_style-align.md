# Handoff: align PLO Capture's color + motion tokens to the Monker Killer solver

**Source:** Monker Killer solver team (desktop PLO solver, the import target for this app's captures).
**Goal:** unify the visual DNA so a hand captured here reads as the same product family when it
imports into the solver. Do **not** match desktop density / fonts / keyboard patterns —
mobile-native wins there. This task is *only* the color + motion token alignment below.

---

## Color tokens

These are the solver's canonical values — make ours match.

| Semantic | Current (approx) | Target |
|---|---|---|
| Primary gold (mid) | `#B8862F` | **`#C9A536`** |
| Light / hot gold | `#EBCE7A` | **`#F0C75A`** |
| Actor / seat-ring / EV-positive accent | `#21D6A6` and/or `#1D9E75` (cyan-teal) | **`#10B981`** (emerald) |
| **POT / aggressive-action button** | forest/teal green | **`#7FE000`** (electric lime) |

**The signature move:** in the solver the POT button is electric lime — making it lime here too is
the single clearest "these are one product" read. Keep **CALL** on the emerald `#10B981`, **FOLD**
neutral.

Find every `Color(0x..)` literal carrying these semantics (likely `seat_ring.dart`, the ActionBar,
and any landing / CTA screen) and point them at the values above. Prefer centralizing into a single
theme / tokens source if one exists; if not, leave a `// TODO: extract to theme tokens` where you
touch scattered literals.

## Motion

- Bet-chip slide-out animation (currently `Duration(milliseconds: 300)`) → **`200ms`**, keep
  `Curves.easeOutCubic`. This is the one motion delta that registers consciously against the
  solver's snappier feel.

## Explicitly do NOT change

- Scaffold background (`#0C0F0E`) — the slight luminance lift over the solver's `#050606` is
  correct for mobile.
- Fonts — keep system fonts; mono numerics read as "developer UI" on a phone.
- No actor-pulse animation port, no density changes, no keyboard affordances.

## Acceptance

- POT button is lime `#7FE000`; gold and actor-emerald match the hex above.
- Bet-chip slide is 200ms.
- `flutter analyze` clean.
- Nothing else visually changed.
