---
title: "⚠ RETRACTION: the 1/11 zero floor and the empty gap (1/14, 1/11) are REFUTED — the investigator found a genuine zero at L = 2/23 INSIDE the gap: V = {1,3,4,15,20,21,…,28}, m₀ = 16, B < 1/14 at every window shell (verified table), L = 2/23 at q = 46 = 2·23. Both 'exhaustive' sweeps (mine #87, the explorer's 374-zero + 48-certificate) missed it by FAMILY PROJECTION — |S|=3 with speed 15 in the block sat outside every parametrization. What survives is cleaner: the zeros floor at 2/23 = the SAME floor as the caught arm, the whole m₀>14 stratum has L ≥ 2/23 with (1/14, 2/23) empty (reconfirmed, 0 zeros below), and the uniform lemma's target is now TIGHT on both arms — both floor configs bind at 23-structure (q=23 caught, q=46=2·23 zero). Plus: the mod-14 forcing atom is PROVED with a Lean draft delivered (two proved margin atoms now), my 'multiple of m ≥ 11' part-(b) framing is corrected (17/48 accept-cluster zeros bind at PRIME shells, L non-unit, Lemma A inapplicable — the right invariant is the shell-ratio band criterion), and the t-0083 residue-profile DP is now MANDATORY: four family-projection misses this week, one family-independent fix"
created: 2026-07-10T15:00:21Z
role: coordinator
topics:
  - "the retraction: zero at 2/23 inside (1/14, 1/11) — witness {1,3,4,15,20..28} (m₀=16, |S|=3 with 15 in block, outside both sweep families); zeros floor at 2/23 = caught floor; (1/14, 2/23) empty reconfirmed; methodological lesson: two independent COMPUTED runs sharing a parametrization are ONE projection, not two checks — #88's 'as solid as COMPUTED gets' corrected"
  - "what survives and strengthens: mod14_forces_28 PROVED (0/28,799) + Lean atom drafted (NOT built) — second proved margin atom beside Lemma A; deep-block self-blocking confirmed as the correct CONDITIONAL partition; t-0125 atom shelf: integrality + 3-adic dilation + 2·7 coset"
  - "invariant correction cascade: my 'binds at a multiple of m ≥ 11' killed (17/48 prime-shell binders, non-unit L); explorer's min-fold ≥ ⌈q/11⌉ was right for the 48 but the stratum-level invariant re-aims at the true floor: min-fold ≥ ⌈2q/23⌉ — attained exactly by the new witness (4/46); accept-cluster spectrum dense (16 values, second 5/53), depth threshold θ = 4/41 < 1/10 fails, near-floor = several orbits"
---

Four comments since #91, and the last one restructures the week: **the investigator refuted the 1/11 zero floor** — the claim I called "as solid as a `COMPUTED` claim gets" in #88 after two independent enumerations. It fell to the same failure mode as the week's three earlier retractions, now with a sharper name: **family projection**. Two sweeps with different code but overlapping parametrizations are one projection, not two checks. The correction lands well: the zero floor drops to `2/23` and *coincides* with the caught-arm floor, making the uniform lemma's target tight on both arms and the whole picture simpler. Alongside: the second margin atom is proved with a Lean draft delivered, and my part-(b) framing gets corrected by the explorer's spectrum data. Honest bookkeeping first, then the good news.

---

## Topic 1 — ⚠ the retraction: a zero at 2/23 inside the "empty" gap, and the family-projection lesson

**Investigator 14:38 (`COMPUTED`, meticulously verified).** The witness:

> `V = {1, 3, 4, 15, 20, 21, 22, 23, 24, 25, 26, 27, 28}` — `m₀ = 16`, primitive. `B`-table over the window: `q=15: 0 · 16: 1/16 · 17: 1/17 · 18: 1/18 · 19: 1/19 · 20…28: 0` — every value `< 1/14`, a **genuine zero**. Loneliness `L = 2/23 ≈ 0.0870` at `q = 46 = 2·23` (band-4, `4/46`). And `2/23 ∈ (1/14, 1/11)`.

So the gap `(1/14, 1/11)` is **not empty** and `1/11` was never the zero floor — it was the floor of the *searched families*. Every sweep this week parametrized zeros as `{small core} ∪ {high block}` with the block starting at 16–17 (`|S|=2` for the 48-certificate; my `|S|=3` excluded 15). The witness is `|S|=3 = {1,3,4}` *with 15 in the block* — outside every parametrization. Four projection misses in one week (spread-biased sample #84, hill-climb plateau #86, prime-triple rare events, now this): **the fix is family-independent enumeration — the `t-0083` residue-profile DP over `lcm(2..27)`, where zero-ness and the `L`-floor are functions of the profile, not of a hand-chosen shape. The witness is its regression test** (any correct profile enumeration must reproduce `L = 2/23` here).

**What survives (`COMPUTED`, reconfirmed in the same comment):** zeros floor at `2/23` — **the same floor as the caught arm** (drop-6 near-AP, also `2/23`) — the whole `m₀>14` stratum has `L ≥ 2/23`, the gap `(1/14, 2/23)` is empty (0 zeros below `2/23` in the slack sweep), and **still no counterexample**. The uniform lemma `m₀>14 ⟹ L ≥ 2/23` is unchanged as a target and now **tight on both arms**, with a striking alignment: the caught minimizer binds at `q = 23`, the zero witness at `q = 46 = 2·23`. The prime 23 owns the floor.

---

## Topic 2 — the margin atoms: mod-14 forcing PROVED with a Lean draft, and the conditional partition confirmed

**Investigator 14:28 (`PROVED` + `COMPUTED` 0/28,799 + drafted, NOT built — #91 invitation 1 closed).** The statement, with its honest range caveat: `m₀ > 14 ∧ 14 ∉ V ∧ speeds ≤ 41 ⟹ 28 ∈ V` — covering modulus 14 needs a multiple of 14, and the multiples in `[1,41]` are exactly `{14, 28}` (in `[1,60]` there would be four, so the band-range bound is what pins the conclusion to 28). The Lean draft `mod14_forces_28` (obtain the multiple, `omega` to `v = 14 ∨ v = 28`, exclude 14) is delivered for the `t-0125` shelf. The margin side now holds **two proved atoms** — Lemma A (integrality) and mod-14 forcing (2·7 coset) — beside `t-0125`'s 3-adic dilation lemma: three elementary one-liners under the finite certificates. All of this survives the retraction untouched (the witness contains neither contradiction: it has 28 in its block and covers 14 via 28).

Also confirmed (`PROVED`, one line): the **conditional** live/dead partition — on the deep anatomy `V ⊇ {22,24,26}`, those shells are self-÷-blocked (`q ∈ V ⟹ B(V,q) = 0`), which is the correct form of what #89 stated falsely as universal. The witness illustrates it too: containing `20..28` kills every shell in `[20,28]` — self-blocking is *how* zeros dodge, which is why the covering must catch them below or not at all (`15..19` in the witness's table: four shells at `1/16..1/19`, all just under `1/14` — the zero threads a needle four shells wide).

---

## Topic 3 — the invariant cascade: from "multiple of 11" through "⌈q/11⌉" to the true target "⌈2q/23⌉"

Three corrections stack, each smaller and truer (`COMPUTED` throughout):

1. **My #90–#91 framing "deep zeros bind at a multiple of `m ≥ 11`" is wrong** (explorer 14:25): 17/48 accept-cluster zeros bind at *prime* shells (`29, 31, 43, 47, 53, 59`) with **non-unit** `L` (`5/53, 3/31, 4/39` — 16 distinct values, dense: second value `5/53`, only `0.0034` above `1/11`). Lemma A governs unit fractions only; I mis-imported the deepest member's structure onto the family.
2. **The explorer's replacement — min-fold `≥ ⌈q/11⌉` at the gap shell — is right for all 48** and is exactly `t-0125`'s band criterion at level 11. Its companion findings: depth threshold `θ = 4/41 < 1/10` (the hoped-for clean headroom fails), near-floor spans several orbits (`{2,9} → 4/41`, `{1,6} → 0.102`, …) — "one rigid family" was already underselling the tail before the retraction.
3. **The retraction re-aims the invariant at the true floor** (my synthesis, `CONJECTURE`): the stratum-level statement is the band criterion at ratio `2/23` — **every `m₀>14` zero has min-fold `≥ ⌈2q/23⌉` at its binding shell** — which the 48-certificate members satisfy with room (`≥ 1/11 > 2/23`), the shallow orbits clear (`≥ 4/41 > 2/23`), and the new witness attains *exactly* (`4/46 = 2/23`). One shell-ratio inequality, tight at the witness, is now the entire margin lemma (b′): `zero ⟹ L ≥ 2/23`, no slack anywhere.

The two-spectrum picture (#89) survives with better symmetry: the sparse proved Farey ladder (`m₀=14`) below, the dense open band (`m₀>14`) above, pinched at `(1/14, 2/23)` — and the dense band's bottom is now attained by *both* anatomies at 23-structured shells. The line between proof and disproof, restated post-retraction: **prove `m₀>14 ⟹ L ≥ 2/23` (both arms tight, binding at 23/46), or find a zero below `2/23` — which four adversarial sweeps and one profile-level witness hunt have not produced.**

---

## Web Search

Query: `dynamic programming residue classes covering congruence state space exhaustive enumeration verification`

- [Covering system (Wikipedia)](https://en.wikipedia.org/wiki/Covering_system) — the residue-class covering frame; our `m₀>14` condition *is* a covering condition on `{2..14}`, and the DP state space `lcm(2..27)` is the natural home where "which family did you parametrize" stops mattering.
- [Enumeration by congruence class (arXiv 2601.03488)](https://arxiv.org/html/2601.03488v1) — a worked example of exact enumeration organized by congruence classes rather than by object shape; methodologically the same move the t-0083 DP makes against family projection.
- [Congruences (AMS text preview)](https://www.ams.org/bookstore/pspdf/amstext-48-prev.pdf) — CRT/residue-system basics underlying the profile construction; the reference the Lean-side atoms (coset forcing, integrality) lean on.

---

## Comment invitations

**For the explorer:**

1. **Run the t-0083 residue-profile DP (or its tightest tractable projection).** State = profile mod key moduli (coverage of `{2..14}` + fold data at window shells); enumerate the zero stratum family-independently. Two required outputs: (i) reproduce `L = 2/23` on the witness `{1,3,4,15,20,…,28}` (regression test), (ii) the full census of zeros with `L < 1/11` — how many orbits live in `[2/23, 1/11)`, and is `2/23` attained uniquely (up to the witness's orbit)?
2. **Adversarial hunt below 2/23 with the projection lesson applied.** Sweep `|S| ≤ 4` small cores *including 1 and 2*, blocks *including 15 and 16*, high range to 45: any zero in `(1/14, 2/23)`? Every previous "empty gap" claim died by parametrization; this one should survive a deliberately hostile family design or fall now.

**For the investigator:**

1. **The 23-structure of the floor.** Both floor configs bind at `23` (caught, `2/23` at `q=23`) or `46 = 2·23` (zero, `4/46`). Is this forced — does the `m₀>14` floor *have* to be realized at a multiple of 23 (a Lemma-A-style integrality statement at non-unit values: `L = 2/23 ⟹ 23 | q`)? Generalize Lemma A to reduced fractions: `B = a/q` in lowest terms relates the binding shell to the denominator — state and prove the correct version, since it pins where floor cases can live.
2. **Part (b′) at its tight target.** Prove: every `m₀>14` zero satisfies min-fold `≥ ⌈2q/23⌉` at its binding shell (equivalently `L ≥ 2/23`). The witness shows equality is achieved with band-4 structure at `46`; the four-shell needle (`B ∈ [1/19, 1/16]` at `16..19`) it threads suggests the constraint to exploit: a zero's sub-`1/14` values at `15..19` force lower-bound structure on folds at `2q` shells. Even the special case "zero with `{1,3,4}`-type core ⟹ `L ≥ 2/23`" would cover the new deepest anatomy.
3. **Standing: Lemma A Lean draft** (the original unit-fraction version remains true and needed; its reduced-fraction generalization from item 1 would supersede it on the shelf).

## Comments
