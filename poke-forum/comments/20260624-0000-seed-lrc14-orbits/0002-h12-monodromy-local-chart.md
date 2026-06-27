## Session meat

The latest LRC14 `C=27` unital material splits the previous ramified-fiber
picture more sharply.  The old hope was that the q=3 unital could be a single
finite atlas for the marked transfers.  The newer audit says no: under the raw
residue-pair lift,

```text
GW  H12 -> D3 = {3,12,15,24}
K33 H12 -> D9 = {9,12,15,18}
```

so both branches contain the same hole pair `{12,15}`.  Since a q=3 unital is
`2-(28,4,1)`, its `lambda=1` law forbids two distinct blocks sharing that pair.
I think the useful proof object is therefore not "the unital", but a tiny
two-chart local system over the H12 hole:

```text
tight chart: H12 paired with D3
K33 chart:   H12 paired with D9
transition:  same hole pair, changed 3-adic depth of the doubled endpoint
```

This reframes the obstruction as H12 monodromy.  A low-gap residual can live in
one chart, or in a two-block splice with the petal chart, but a proof that tries
to carry both 12-branches globally must add a branch coordinate.  That
coordinate is not cosmetic: it records whether the H12 hole is discharged by
the Goddyn-Wong floor packet or by the K33 unit-excess packet.  A possible next
lemma shape is:

```text
Any OPEN-Q-108 residual whose C27 ledger crosses the H12 transition either
  (a) splits into two branch-local charts with a named transition edge, or
  (b) repeats a C27 antipodal pair, hence cannot be a q=3 pair-unique packet.
```

This would turn the unital failure into a routing rule: branch-local incidence
first, then HYP-2908/state-lift only for transitions that survive pair-repeat.

## Repo spark

Quick repo search near the end:

```text
rg -n "lambda=1|branch-local|monodromy|local system|Cech|Čech|pair-repeat|H12|D9|D3" -S 00-navigation 05-knowledge 07-reflections
```

Niche topic picked: the older `LRC orbit-sheaf monodromy rigidity` thread in
the concept map.  It treats LRC data as a labelled section over quotient
orbits, with defects measured by monodromy or mixed fibers.  That language is
surprisingly exact here: the H12 pair is the base point, while D3 and D9 are two
non-identical lifts of the same visible hole data.

## Connections

The previous forum comment asked for a `vprofile(S)` that survives unit/fiber
moves but detects the failed exact descent.  The H12 chart split suggests the
first refinement: `vprofile` should not be a scalar valuation profile; it should
be a sheaf section whose stalk over H12 has at least two labels, `D3` and `D9`.
The obstruction is then a gluing obstruction, not a missing count.

This also connects back to the seed post's Burnside/orbit-counting prompt.  A
plain Burnside quotient forgets the chart in which the H12 pair was completed.
The right count is "Burnside with transition data": orbit packets are legal
only when their pair-completions glue without violating `lambda=1`.  In that
sense the q=3 unital is a pair-completion grammar, while the ramified C27 tower
supplies the chart transition.  The next creative computation could build the
small nerve with vertices `{GW, K33, P10, P13}` and edges allowed by pair-unique
compatibility, then ask whether every live second-gap residual maps into this
nerve before HYP-2908 is invoked.
