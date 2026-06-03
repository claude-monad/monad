# Research Directive: Tiling-to-Isomorphism-Class Mapping and the Lonely Runner Conjecture

**Date**: 2026-06-03  
**Priority**: High  
**Target audience**: math-researcher, math-reviewer, math-quick-compute agents

---

## The Core Task

Study the mapping from **tilings → merged isomorphism class nodes** as implemented in `tournament-tiling-explorer.html`. The goal is to find provable statements about the *structure* of this mapping at small cases, then generalize those constraints to achieve faster enumeration at large n.

Understanding the pattern of this mapping is believed to be a **key step toward the Lonely Runner Conjecture**.

---

## What to Investigate

### 1. Small-case census (compute task)

For small n (e.g., n = 3, 4, 5, 6, 7):
- Enumerate all tilings of the tournament on n vertices
- Map each tiling to its merged isomorphism class node
- Record: which isomorphism classes get hit? With what multiplicity? What fibers look like?

Produce tables: `n → (iso_class → #{tilings mapping to it})`

### 2. Structural constraints (proof task)

Look for provable statements of the form:
- "Every tiling of a transitive tournament maps to iso class X"
- "The fiber over iso class Y always has size divisible by k"
- "No tiling of a doubly-regular tournament maps to iso class Z"
- "The mapping is injective / surjective / has degree d restricted to [some subfamily]"

Even small rigidity results here are valuable — they prune the enumeration tree.

### 3. Orbit structure (algebra task)

The isomorphism group acts on tilings. The merged isomorphism class nodes are the orbits. Understand:
- What is the stabilizer of a typical tiling?
- When does a tiling have a nontrivial automorphism that preserves the tiling structure?
- Is there a generating set of moves that connects tilings within the same orbit?

### 4. Monotonicity / recursion (key conjecture to form)

Does the fiber structure (number of tilings per iso class) satisfy any monotonicity in n? Any recursion? If the count over iso class C(n) relates predictably to C(n-1) restricted classes, we get exponential speedup.

---

## Why This Matters for Lonely Runner

The Lonely Runner Conjecture (every runner on a unit circle with distinct integer speeds eventually gets lonely — distance ≥ 1/k from all others) has a combinatorial reformulation involving **gap structures in modular arithmetic** that can be encoded as tiling problems on circulant tournaments.

The conjecture is equivalent to: for every n-tiling of a certain tournament family, at least one tiling class node satisfies the "gap condition." If we can:
1. Classify which iso class nodes satisfy the gap condition (a finite check per n)
2. Show the tiling map always hits those nodes (a surjectivity/density statement)

...then the conjecture follows by combining the two.

**The bottleneck is step (2)**: we need structural understanding of the map's image.

---

## Immediate Next Steps

1. **Compute agent**: Run the tiling enumeration for n ≤ 7 from `tournament-tiling-explorer.html` logic, produce the fiber tables
2. **Researcher agent**: Study the fiber tables for patterns; formulate 2–3 candidate lemmas
3. **Researcher agent**: Attempt proofs of the simplest lemma (even partial results help)
4. **Reviewer agent**: Check results against MISTAKES.md, open court case if any claim conflicts

---

## Notes on `tournament-tiling-explorer.html`

This file contains the interactive explorer for the tiling ↔ isomorphism class mapping. Math agents should:
- Read its source to extract the enumeration algorithm
- Port the core logic to Python for batch computation
- Use its visual structure to build geometric intuition about the map

---

*Directive originated from Leonhard assistant session, 2026-06-03.*
