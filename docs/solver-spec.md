<!-- SPDX-License-Identifier: MIT -->

# A solver for Party Saga: the clean-room specification

This page is the design for a solver of `entities/fixtures/minizinc/party-saga/party-saga.mzn`, written **only from
published papers**. The implementation is a later step and is written from this page, not from any solver's code.

**How the sources were obtained.** Only open or documented copies. Pages that served a bot check or an invalid
certificate were not bypassed. Text was extracted with a script (`pypdf` in a throwaway environment).

**Turbo's licence.** Turbo (github.com/ptal/turbo) is Apache-2.0: the repository's `LICENSE` is the Apache License 2.0 and
GitHub reports it. That permits reading and reusing its source with the notices the licence requires. The clean-room rule below is
about CP-SAT, Chuffed and Gecode, not Turbo, but nothing of Turbo's source has been opened for this page either; it is
described here from the paper and slides. Any later reuse of Turbo code is logged here.

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
| Schulte, Tack and Lagerkvist, *Modeling and Programming with Gecode*, version 6.2.0 (user documentation, not source code) | section 9.3 (search engines DFS, LDS, BAB; options), 9.4 to 9.4.2 and 9.4.5 (restart-based search, cutoff generators, large neighbourhood search through restarts), the start of 9.5 (portfolio of assets) | restarts and cutoffs (S1), branch and bound through `constrain` (S2), the portfolio and neighbourhood workers (W2, W3) |
| Pisinger and Røpke, *Large Neighborhood Search*, Handbook of Metaheuristics, 2010 (DTU Orbit open copy) | the introduction and section 2 up to the destroy method (extracted lines 1 to 230 and 486 to 565): destroy and repair, Algorithm 1, acceptance rules, degree of destruction | the neighbourhood worker (W3) |
| Talbot, *A GPU-based Constraint Programming Solver*, AAAI 2026, author's copy at ptal.github.io/papers/aaai2026.pdf (11 pages), and the author's 32 slides of the talk | the whole paper to the conclusion, and all the slides | the 2026 GPU design, its measured costs and results (G1 to G6, G10 to G14). Turbo's source (Apache-2.0, github.com/ptal/turbo) was **not opened** |
| Talbot, slides *Turbo: Design of a Constraint Programming Solver on GPU*, LERIA talk (81 slides; the title slide says 9 January 2024, the file name says 2025), `/mnt/fire/talbot-leria-2025-slides.pdf` | all slides; one slide (Turbo versus Choco 4.15) is a chart image, so its numbers were not read | the parallel-propagation model and the ternary form with its measured cost (G1, G2, G5 to G9) |
| Bit-Monnot, *Revisiting Optional Variables in Lazy Clause Generation Solvers for Flexible Scheduling*, CP 2026 (LIPIcs 379, CC BY 4.0) | the abstract, the introduction, and sections 2.1 to 2.3 (domains, presence literals, domain operations) | optional variables for tasks that may be absent (O1 to O3) |
| Dekker, Ignatiev, Stuckey and Zhong, *Towards Modern and Modular SAT for LCG*, CP 2025 (LIPIcs 340) | the abstract only | that an LCG solver can sit on a replaceable SAT engine through the IPASIR-UP interface; nothing else is used |

**Not read.**
- Ohrimenko, Stuckey and Codish, *Propagation via lazy clause generation* (Constraints 2009) and its CP 2007
  version: the author's site refused automated downloads (a bot check, not bypassed) and the journal is paywalled;
  OpenAlex lists it as closed access. The 2026 retrospective on lazy clause generation (Constraints, hybrid open
  access) returned a bot-check page instead of the PDF. What this page says about lazy clause generation comes
  from the arXiv papers above, which describe it.
- Feydy and Stuckey, *Lazy clause generation reengineered* (CP 2009): closed access.
- Shaw, *Using constraint programming and local search methods to solve vehicle routing problems* (CP 1998), the
  source of large neighbourhood search: closed access. LNS is taken from Pisinger and Røpke, who describe it, and
  from the Gecode documentation.
- Chu's 2011 thesis (the design of Chuffed): the repository page did not load.
- The GPU all-different paper (par.nsf.gov purl 10537139) and the GPU compact-table paper (arXiv 2507.18413, downloaded and
  not read), and Vilim's time-table-edge-finding paper.
- *From Literals to Atomic Constraints* (CP 2026, LIPIcs.CP.2026.42): only its first lines were opened. Its abstract says the
  analysis of Chuffed and OR-Tools in it rests on source inspection by its authors, which is one more reason not
  to build on it here.
- The parts of the papers above not listed as read, and the Gecode book outside the sections listed.

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
  here: a conflict-driven score and nogoods kept across restarts. **Restarts** follow the Gecode documentation:
  search is stopped when a cutoff counted in failures is reached and restarted on a re-configured problem, with a
  geometric cutoff sequence `s * b^i` or a Luby sequence (1, 1, 2, 1, 1, 2, 4, ...) scaled by `s`; the same
  documentation names AFC and action as branching heuristics whose statistics a restart can use (their definitions
  were not read).
- **S2 Branch and bound.** After a solution with objective `o`, post `objective < o` and continue (explanation
  paper, section 2). The RCPSP/LCG paper writes the improving constraint as `o <= theta(o)` in one passage; this
  page uses the strict form, as the explanation paper does, and the discrepancy is noted here.
- **S2b Branch and bound with restarts.** Gecode's `BAB` engine adds the better-solution constraint (`constrain`) to the
  remaining search, and the restart meta engine runs a `BAB` engine for each restart; the documentation says this is the
  combination to use for a best solution (sections 9.3 and 9.4.1).
- **S3 Completeness.** The search is complete: it proves optimality when the queue and the branching are exhausted
  with the bound posted.

## Workers (a portfolio)

The CP-SAT-LP abstract describes a portfolio of diverse workers that find primal solutions by complete search,
local search or large neighbourhood search, improve dual bounds, or probe to shrink the problem, with information
shared between workers.

- **W1 Complete worker:** the core above with learning.
- **W2 Several complete workers** with different branching order and restart rules. The Gecode documentation
  describes a portfolio as several copies of the same problem, each an asset, usually with a different branching
  heuristic, run to make finding a solution more likely and the search more robust (section 9.5). They share the
  incumbent objective; sharing short learned clauses is a known approach for SAT portfolios and needs a length limit
  (survey, section 4.1), and the limit here is a tunable and not from a source.
- **W3 Neighbourhood worker (large neighbourhood search).** Pisinger and Røpke: an incumbent is improved by
  alternately destroying part of it and repairing it, `x' = repair(destroy(x))`, accepting `x'` by a rule (only
  improving, or a simulated-annealing rule with a falling temperature), keeping the best, and stopping on a limit;
  the destroy step is random and has a degree of destruction (their example removes 15% of the customers). Gecode
  documents the same idea through restarts: keep part of the best solution, search for a better one within a cutoff,
  and either stop or retry at random when the cutoff is reached (section 9.4.5). For Party Saga, destroy means
  releasing the decisions of some tasks and leaving the rest fixed to the incumbent; the neighbourhoods are **this
  page's own**: the tasks of one character, of one zone, or of one time window.

## Optional tasks

In Party Saga a task may be absent (`done[t]` false) and then has no start, duration or arms. The MiniZinc model
encodes that as "start 0, duration 0". Bit-Monnot's formalism is the better fit for a solver built from this page:
- **O1** Every variable has a presence literal; a variable with the literal true is mandatory. A variable's domain
  is its bounds plus the value "absent" (section 2.2).
- **O2** Entailment of a bound literal `[y <= v]` means that **if** the variable is present then it is at most `v`;
  it does not rule out absence (section 2.3).
- **O3** Tightening a bound of an absent variable is a no-op; tightening the bound of a present variable past its
  other bound makes it absent when it is optional, and fails when it is mandatory (the `SetUB` operation).
Chosen here: the start, duration and arm of task `t` get the presence literal `done[t]`, and `part[c, t]` is a
mandatory Boolean. The paper's own solver (Aries, on GitHub) was not opened.

## GPU

From the Turbo papers as far as read (the 2022 paper in full where listed, the 2026 work through its slides):
- **G1** Propagation is a fixpoint over lattices, run without locks: propagators are monotone functions that join
  into shared variables, and the result is the same whether the fixpoint is computed in parallel or in sequence. The
  slides add: strict updates (a bound changes only if the new value is tighter) and fair scheduling keep it deterministic.
- **G2** The loop is "eventless": every propagator runs each round until nothing changes, in the manner of AC-1
  (slides: a block-wide loop with a changed flag and barriers).
- **G3** No global constraints, no learning, no lazy clause generation, no restarts, no event-based propagation
  (slides, conclusion). A GPU worker for Party Saga would therefore be a propagation-only worker.
- **G4** One subproblem per thread takes too much memory (the slides: a 1 MB problem times 135 168 threads); search
  is split into subproblems with one per GPU block, and more subproblems than multiprocessors for load balance
  (embarrassingly parallel search).
- **G5** Constraints are stored as a **ternary network** `x = y op z` with `op` in `+`, `/`, `*`, `mod`, `min`, `max`,
  `<=`, `=`, one constraint per thread, sorted by operator to reduce divergence; the slides report a 10-fold speed-up
  from this form.
- **G6** The cost of that form, from the paper's Table 1 against the constraint networks Choco gets: on 96 instances the
  median growth is 4.74 times the variables and 4.46 times the constraints (the mean is 64.8 and 152, the maximum 1316 and
  3912); without the `yumi-dynamic` instances (92 left) the median is 4.45 and 4.34 and the maximum 336 and 731. Those
  instances are the worst case, because they use many global constraints. Result on the 100 instances of the 2024
  Challenge, 20-minute limit, one H100: against Choco, the same objective on 48%, better on 23%, worse on 29%; against
  OR-Tools, equal on 31%, better on 11%, worse on 58%. MiniZinc scores (Table 5): OR-Tools 266.7 with 64 threads and
  119.9 sequential, Choco 190.8 and 49.3, Turbo 45.8; the parallel CPU versions outperform Turbo, and Turbo does better
  on problems with few or no global constraints. The slides give the number of instances unsatisfiable at the root as 81 on one slide and
  91 on another; the paper does not repeat that number, and says one instance was removed as unsatisfiable during the
  conversion to FlatZinc and one `yumi-dynamic` instance as too large (15 of the 41 solver configurations in the Challenge
  crashed on it and only 4 found a solution). (An earlier version of this page wrongly called the 11 / 31 / 58 percent figures unsupported; the paper states them.)
- **G10** Representation (paper section 3): ternary constraints `x = y op z` with `op` in `+`, `*`, `/`, `mod`, `min`, `max`, `=`,
  `<=`; subtraction is dropped because `x = y - z` is `y = x + z`; constants are variables, so every constraint is 16 bytes
  (loaded as one `int4`); bytecodes are sorted on (operator, y, x, z) to reduce divergence, and there are 13 divergence
  points because `=` and `<=` can be negated or reified. Global constraints are decomposed by the MiniZinc compiler before
  this step.
- **G11** Warp-centric fixpoint: a warp propagates 32 contiguous constraints to a local fixpoint before moving on, which
  the paper reports as about +10% nodes per second; it is a fair schedule, so the fixpoint is unchanged.
- **G12** Table 2 (20 instances, one per problem class): the ternary form explores about 7 times more nodes per second
  than view-based propagators (103036 against 14623), needs 2.3 times more fixpoint iterations per node (13.9 against
  6.1), uses far less propagator memory (0.69 against 10.33 MB) and more variable memory (286.5 against 76.6 KB).
  `propagate` is 93% of GPU time on average. The authors' attempts at dynamic scheduling of propagators raised total time.
- **G13** Search is "dive and solve", a lazy form of embarrassingly parallel search: blocks take subproblems at a depth `D`
  given in the paper as `ceil(log2(blockDim.x * 300))` (ten times more subproblems than the usual 30 per thread; the
  paper's `blockDim.x` there seems to mean the number of blocks, which I did not confirm), reach them by a backtrack-free dive
  whose path is the bits of the subproblem index, skip a whole failed subtree by incrementing a prefix, share the best
  objective bound through one atomic minimum, and restore state by recomputation from the root. Diving costs 0.01% of
  the time. The dive must be deterministic, so adaptive branching such as weighted degree cannot be used while diving.
  Load balance is poor at the timeout: about 85% of blocks idle on average.
- **G14** Scaling (Table 4): nodes per second on the average of the instances, 94k on a Quadro RTX 5000 Max-Q, 207k on an
  RTX A5000, 212k on a V100, 458k on an H100. Their memory figures: a domain store of 56 MB for the largest
  `yumi-dynamic` instance, 2 MB on average, 110 KB median.

From the earlier LERIA talk (January 2024), which gives the model and the measurements behind G5 and G6:
- **G7** The propagator is a reductive, monotone function; a process is `x <- f(y1..yn)` joined into a store, with ask
  (`if b then P`), local variables and parallel composition, no recursion. Theorem on the slides: the fixpoints of a
  program run in parallel and of the same program run in sequence are the same, so the sequential CPU fixpoint loop and
  the GPU loop give one answer. The memory needs are three: atomic loads and stores, caches that eventually agree,
  and no values appearing from nowhere. The slides also name the properties that the program can be stopped and
  restarted on partial data, and that threads can be added.
- **G8** The ternary normal form on the slides is `x = y op z` with `op` in `+`, `-`, `/`, `*`, `%`, `min`, `max`,
  `<=`, `=`, held as 16 bytes (an operator and three variable ids), sorted by operator. The example given: `x + y != 2`
  becomes `t1 = x + y` and `ZERO = (t1 = TWO)` with two constant variables. Measured on 16 MiniZinc instances against a
  tree-shaped representation: fixpoint iterations per second +553%, nodes per second only +18%, fixpoint iterations per
  node +138% (40 instead of 17), propagator memory -90%, variable memory +718%. Growth for single problems (variables,
  constraints): team-assignment 2.2 and 1.8 times, generalized-peacable-queens 6.9 and 3.1, spot5 19.8 and 3.6, accap 5.2
  and 3, wordpress 139 and 4.
- **G9** Parallel propagation has not worked well on a CPU (the survey is cited), while parallel search over
  independent subproblems scales almost linearly there; on a GPU one subproblem per thread needs too much memory, so
  there is one per block. In progress on the slides: waking only the propagators whose inputs changed, using sparse
  matrix and scan operations, to avoid running every propagator each round; and a table domain that generalises global
  constraints.

For Party Saga: P1, P4 and P6 are sums and differences and fit the ternary form. P2 (a three-way disjunction with
travel and cooldown) and P3 (the cumulative) do not fit without decomposition, which G6 says can be large. G7 to G9
add a second reason for caution: the growth in variables and the slow convergence of the eventless loop (40 rounds per node
against 17) both hit a model with a many-way disjunction and a cumulative. A GPU worker
is only worth building if CPU results show propagation, not learning, is the cost. That is a measurement for the
frontier loop, not an assumption.

**Local Turbo experiment (parked).** Turbo was built here (outside the repository, in `/mnt/fire/6-datasource/turbo-build`, with its own
`PARKED.md` and a re-runnable `control/control.sh`). Its CPU mode solves two known-answer controls and our smallest test
correctly (objective 6, as CP-SAT and Gecode give). Its `hybrid` and `gpu` modes are compiled out in the branch used; `-arch barebones` is the GPU solver and
gives the same answers (objective 8 and 6) with `-timeout 30000`, at a fixed cost of 2.5 to 3.8 s per solve even for 12 variables (cause
untested). No GPU frontier exists yet. Turbo's source was read only for its driver code.

## Implementation outline (Lean 4, not started)

Modules under `repositories/Frontier/Solver/`: `Domain`, `Engine` (E1 to E4), `Propagators` (P1 to P7), `Learn`
(L1 to L5), `Search` (S1 to S3), `Workers` (W1 to W3), `Instance` (read the JSON the generator emits; it must
agree with the `.dzn` byte for byte in meaning), and an executable `frontier_solve`. Acceptance: it reproduces
the objective and status of every oracle result for the 21 hand-checked cases and for every level the frontier
loop proved, and `party_saga.exs frontier --solver ours` places its frontier next to CP-SAT's.

## What this page does not claim

It does not claim the design will beat CP-SAT, Chuffed or Gecode; the expected first result is a lower frontier.
It does not claim the choices marked "chosen here" or "this page's own" come from a paper. And it is only as complete
as the sources read: the two original lazy clause generation papers and Shaw's paper are closed access, and the
full Turbo 2026 paper is behind checks that were not bypassed.
