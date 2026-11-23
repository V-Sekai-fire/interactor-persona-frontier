<!-- SPDX-License-Identifier: MIT -->

# A solver for Party Saga: the clean-room specification

This page is the design for a solver of `entities/fixtures/minizinc/party-saga/party-saga.mzn`, written **only from
published papers**. The implementation is a later step and is written from this page, not from any solver's code.

**The clean-room rule.** No source code of CP-SAT, Chuffed or Gecode was opened, by the author of this page or in
any tool output shown while writing it. MiniZinc and the three solvers run as black-box oracles whose answers our
solver is compared with; running a program is not reading it. One web search listed the source file of a Rust solver
crate; it was not opened. Whatever is not in the source log below was not read, and the page says so.

## Source log

Text was extracted from the PDFs with a script, so the line ranges below are those of the extracted text, not page
numbers of the paper.

| Source | Read | What this page takes from it |
|--------|------|------------------------------|
| Schulte and Stuckey, *Efficient Constraint Propagation Engines* (arXiv cs/0611009) | sections 3 to 4.2 (propagation system, queue, fixpoint, idempotence, dynamic fixpoint) | the propagation loop (E1 to E4) |
| Schutt, Feydy, Stuckey and Wallace, *Solving the RCPSP with Generalized Precedences by Lazy Clause Generation* (arXiv 1009.0347) | the introduction and section 2 (finite domain propagation, cumulative and time-table, SAT, lazy clause generation, explanations, implication graph, 1UIP) | variable representation, explanations, nogoods (L1 to L5), the time-table propagator (P3) |
| Schutt, Feydy and Stuckey, *Explaining Time-Table-Edge-Finding Propagation for the Cumulative Resource Constraint* (arXiv 1208.3015) | the introduction, sections 2 and 3, and the start of 4 | explanations for cumulative, bound widening, branch and bound by `obj < o` (P3, S3) |
| Perron, Didier and Gay, *The CP-SAT-LP Solver*, invited talk, CP 2023 (LIPIcs 280, 3:1 to 3:2, CC BY 4.0) | the whole abstract | the shape of a CP-SAT-style solver and its workers (W1 to W3) |
| Talbot, Pinel and Bouvry, *A Variant of Concurrent Constraint Programming on GPU* (arXiv 2207.12116) | the abstract, the introduction, the lattice and PCCP definitions (extracted lines 1 to 210) | the GPU propagation model (G1 to G4) |
| Gent et al., *A Review of Literature on Parallel Constraint Solving* (arXiv 1803.10981; the author list was not checked) | the portfolio and clause-sharing passages in sections 4.1 and 5.5 (extracted lines 366 to 410 and 815 to 860) | portfolio and sharing limits (W2) |

**Not read.**
- Ohrimenko, Stuckey and Codish, *Propagation via lazy clause generation* (Constraints 2009) and its CP 2007
  version: the author's site refused automated downloads and the journal is paywalled. What this page says about
  lazy clause generation comes from the arXiv papers above, which describe it.
- Feydy and Stuckey, *Lazy clause generation reengineered* (CP 2009): not fetched.
- *Modeling and Programming with Gecode*: not read. Gecode is represented here only through the engine paper.
- Shaw, *Using constraint programming and local search methods to solve vehicle routing problems* (CP 1998), the
  source of large neighbourhood search: not fetched. W3 uses only the name and the one-sentence idea in the talk
  abstract; the neighbourhoods are this page's own.
- Talbot, *A GPU-based Constraint Programming Solver* (AAAI 2026): the download failed. Only a search-result
  summary was seen: no global constraints, no nogood learning, no lazy clause generation, and a reported
  comparison with OR-Tools (better on about 11% of instances, equal on 31%, worse on 58%). That summary is not a
  reading of the paper, and the numbers should be checked against it.
- The GPU all-different and compact-table papers (par.nsf.gov purl 10537139, arXiv 2507.18413): the second was
  downloaded but not read; the first was not fetched.
- Vilim's time-table-edge-finding paper, and the parts of the papers above not listed as read.

## What the solver has to decide

Taken from the model, not from a paper. Decision variables: `done[t]`, `part[c, t]`, `how[t]`, `arm[t]`, `start[t]`,
`held[k]`, `endtime`. Data fixed at load time: `dist[c, u, v]` (shortest leg times with the per-mode ramp, computed
once by Floyd-Warshall in the loader, so travel is a table of constants), role needs, element needs, zone
capacities, points, windows, prerequisite pairs. The objective is
`time_weight * endtime - bonus - point_weight * points`. Everything is integral.

## Core: propagation to a fixpoint

- **E1 Domains.** An integer variable has a domain `[lb, ub]` (bounds only). A Boolean is `{0, 1}`.
  Source: bounds domains in the engine paper and the interval lattice `IZ = ZInc x ZDec` in the Turbo paper.
- **E2 Propagators.** A propagator is a function that only shrinks domains and loses no solution, and that detects
  failure (RCPSP/LCG paper, section 2.1).
- **E3 Engine.** A queue of propagators. Take one, apply it, and add every propagator that subscribes to a variable
  whose domain changed and is not known to be at a fixpoint; stop when the queue is empty (engine paper, Figure 2
  and `newinput`).
- **E4 Idempotence.** A propagator marked idempotent is not re-queued by its own change; a propagator may also report
  at run time that its result is a fixpoint (engine paper, sections 4.1 and 4.2).

## Propagators for Party Saga

| Id | Constraint in the model | Propagation rule | Explanation (for learning) |
|----|-------------------------|------------------|----------------------------|
| P1 | difference constraints `start[j] >= start[i] + d`: prerequisites, release, deadline, `endtime >= start + dur` | bounds: raise the lower bound of `j`, lower the upper bound of `i` | the one-literal clauses of the precedence example, `[start_b <= v] -> [start_a <= v - d]` |
| P2 | two tasks of one character: in sequence with travel and cooldown, or the two-arm overlap exception | once `part[c, t1]` and `part[c, t2]` are true, each of the three disjuncts that the bounds already refute is dropped; if two are dropped, the third is enforced | the bounds literals that refute each dropped disjunct, plus the two `part` literals |
| P3 | per-zone cumulative, usage 1 or 2 (2 per member for a duty), capacity `zone_capacity[z]` | time-table: sum the compulsory parts into a usage profile; fail on overload; push a start past a full interval | the pointwise explanation, then widened bounds (RCPSP/LCG paper, Examples 3 and 7; explanation paper, sections 3.1 and 3.2); an energetic edge-finding step is optional |
| P4 | role counts per duty (`sum part = need`), slots per character, crystal held at most once | cardinality over Booleans: when the count is reached or unreachable, fix the rest | the true literals that make the count tight |
| P5 | a duty needs an element: some crystal of that element is held by a member | a clause over `held[k] = c` and `part[c, t]` | the clause itself |
| P6 | rank gate: points of tasks finished before `start[t]` reach `min_points` | a linear propagator on Booleans `before[u, t]` defined by `start[u] + dur[u] <= start[t]` | the Booleans that already count |
| P7 | the objective | a linear lower bound on the objective from the current bounds | the bounds that give the bound |

P1 and P3 follow the papers read. P2 and P4 to P7 are this page's own design, written in the same style (a
bounds propagator with a clausal explanation); no source describes them.

Zone capacity is the heaviest. The Turbo paper handles global constraints by decomposition on the GPU, which for
a cumulative means time-indexed Booleans; the explanation paper handles it with a global propagator. Both are on
the table for the GPU step (G3).

## Learning, search and optimisation

- **L1 Literals.** For an integer variable `x`, the literals `[x <= d]` and `[x = d]`, with the domain clauses
  that tie them, created lazily (RCPSP/LCG paper, section 2.3.1).
- **L2 Explanations.** Every domain change or failure is justified by a clause over literals that were true; the
  stronger the clause, the more it prunes (section 2.3.2).
- **L3 Unit propagation.** Explanation clauses go into a clause database; unit propagation then agrees with the
  propagator that produced them (section 2.3.2).
- **L4 Conflict analysis.** An implication graph with the reason of each literal; on a conflict, resolve back to the
  first unique implication point and learn that clause as a nogood (section 2.3.3).
- **L5 Bound widening.** Replace a bound literal in an explanation by the weakest one that still holds (the
  explanation paper's generalisation of the explanation for a resource overload).
- **S1 Branching.** On a start time, the choice `start = lb` or `start >= lb + 1`, the general scheme named in the
  engine paper; for Booleans, value order from the incumbent. Activity-based branching and restarts are named in
  the lazy clause generation papers as benefits of learning; their exact rules were **not read** and are chosen
  here: a conflict-driven score, geometric restarts, nogoods kept across restarts.
- **S2 Branch and bound.** After a solution with objective `o`, post `objective < o` and continue (explanation
  paper, section 2). The RCPSP/LCG paper writes the improving constraint as `o <= theta(o)` in one passage; this
  page uses the strict form, as the explanation paper does, and the discrepancy is noted here.
- **S3 Completeness.** The search is complete: it proves optimality when the queue and the branching are exhausted
  with the bound posted.

## Workers (a portfolio)

The CP-SAT-LP abstract describes a portfolio of diverse workers that find primal solutions by complete search,
local search or large neighbourhood search, improve dual bounds, or probe to shrink the problem, with information
shared between workers.

- **W1 Complete worker:** the core above with learning.
- **W2 Several complete workers** with different branching order and restart rules, sharing the incumbent
  objective and short learned clauses. The survey shows sharing short learned clauses is a known approach for SAT
  portfolios and that it needs a length limit; the limit here is a tunable and not from a source.
- **W3 Neighbourhood worker:** fix a subset of the incumbent's decisions and search the rest with a small time
  limit; neighbourhoods by character, by zone and by time window (this page's own).

## GPU

From the Turbo paper, as far as read:
- **G1** Propagation is a fixpoint over lattices, run without locks: propagators are monotone functions that join
  into shared variables, and the result is the same whether the fixpoint is computed in parallel or in sequence.
- **G2** The loop is "eventless": every propagator runs each round until nothing changes, in the manner of AC-1,
  because event queues do not suit the hardware.
- **G3** The paper has no global constraints and no learning, and says the solver is a proof of concept; it points to
  decomposition for globals. A search summary of the 2026 paper (not read) says lazy clause generation is harder on
  a GPU. A GPU worker for Party Saga would therefore be a propagation-only worker.
- **G4** The paper reports running a subproblem per thread is not efficient on a GPU, because the cache per thread is small.

P1, P4 and P6 are sums and differences over integers and Booleans and fit that model; P2 and P3 do not fit without decomposition.
A GPU worker is only worth building if CPU results show propagation, not learning, is the cost. That is a measurement for the
frontier loop, not an assumption.

## Implementation outline (Lean 4, not started)

Modules under `repositories/Frontier/Solver/`: `Domain`, `Engine` (E1 to E4), `Propagators` (P1 to P7), `Learn`
(L1 to L5), `Search` (S1 to S3), `Workers` (W1 to W3), `Instance` (read the JSON the generator emits; it must
agree with the `.dzn` byte for byte in meaning), and an executable `frontier_solve`. Acceptance: it reproduces
the objective and status of every oracle result for the 21 hand-checked cases and for every level the frontier
loop proved, and `party_saga.exs frontier --solver ours` places its frontier next to CP-SAT's.

## What this page does not claim

It does not claim the design will beat CP-SAT, Chuffed or Gecode; the expected first result is a lower frontier.
It does not claim the choices marked "chosen here" come from a paper. And it is only as complete as the sources
read: the lazy clause generation papers by Ohrimenko, Stuckey and Codish, and by Feydy and Stuckey, would be read
next if they can be obtained.
