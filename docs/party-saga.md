<!-- SPDX-License-Identifier: MIT -->

# Party Saga: our own RECTGTN problem in MiniZinc

A guild party of characters, each with a body, a controller, a role and a loadout, clears a board of tasks on a
world map. It is **our problem, not a MiniZinc Challenge problem**: no claim about the Challenge is made, and no
"best known" value exists. The reference is the proved optimum of a solver, labelled as such.

Files: `entities/fixtures/minizinc/party-saga/party-saga.mzn` (the model), `instances/tests/` (hand-checkable
cases), `tools/party_saga.exs` (generator, solver runner, tests, frontier loop), `frontier.json` and `traces.jsonl`.

## How each RECTGTN part appears

| Part | In the model | Idea borrowed from |
|------|--------------|--------------------|
| R Relationship | `terrain` per edge, `mode_terrain` in `speed`, zones with a capacity, role needs of duties, board prerequisites | multi-agent graph coverage; yumi zones |
| E Enabled | each character's day is a chain of moves, scouts and duties, ordered with travel time between stops | graph coverage |
| C Capability | controller modes, body measures (`arm_reach`, `stride`), `can_perform`, roles, arts from crystals | skill allocation; multi-skill project scheduling |
| T Temporal | leg times, durations, release windows, deadlines, duty cooldowns, `endtime` | graph coverage; precedence families |
| G Goal | every required task is cleared (`required[t] -> done[t]`) | graph coverage |
| T' Task | a scout is a quick look or a performance; a duty is a party encounter with a role mix | graph coverage; yumi (one arm or both) |
| N Network | any order, any character, with prerequisites and optional tasks | graph coverage |

The five layers: **body and arms and zones** (two arms, zone capacity counted in arms at work), **controller
locomotion** (stick, sprint, climb, teleport with a blink range), **party jobs** (roles, duties, cooldowns),
**loadout** (core slots and crystals that give arts a duty needs), **guild board** (points, rank gates, chapters as
release windows). One model, no switches: a layer is off when its data is empty.

Inspiration only: two game genres, an online party game and a role-playing game with equippable crystals. Names
here are generic (roles, duties, crystals, arts, board). No names, text or assets from either game are used, and
the mapping of their mechanics is from general knowledge, not from their rules.

Body numbers (`arm_reach`, `stride`) are a **table**, not output of `sinew-mocap/solve` or `measure`; the field
names follow `measure`. Nothing is copied from either repository.

## Rate of change

A character cannot change speed at once. Each locomotion mode has a **ramp**, in model seconds: stick 1, sprint 2,
climb 1, teleport 0. A leg over one edge takes `ceil(100 * length / speed) + ramp` seconds, where the speed is a
percentage of the character's stride. So the ramp is the time spent accelerating and braking, and a character
that stops at every node pays it on every edge. The speed profile of a leg is a trapezoid: accelerate for `a`
ticks, cruise, brake for `a` ticks, with `a = min(64 * ramp, N / 2)` for a leg of `N` ticks. The cruise speed never
exceeds the mode's nominal speed.

## Plan as packets

A solved level can be sent as 100-byte entity packets of
[contract-entity-packet](https://github.com/V-Sekai-fire/contract-entity-packet) (MIT, pinned in `lakefile.lean`).
`elixir tools/party_saga.exs packets saga 3` solves a level and encodes it; `frontier_packets` (Lean, module
`Frontier.PlanPackets`) encodes with the contract's own `encode`, decodes every packet and checks it.

Units: **64 ticks per second**, so a tick is 15.625 ms; one map length unit is 1 m (10^6 um); the `hlc` stamp is in
milliseconds (`tick * 1000 / 64`, floored). A speed of 1 m/s is 15 625 um per tick, about 1 000 of the 32 767
velocity codes (full scale is 32 m/s). One acceleration code is 30.5 um per tick squared, about 0.125 m/s squared:
coarse, and rounded **up** in magnitude by the contract's `accelCodeUp`, so a decoded value is never below the true one.

| Step of the plan | Packet |
|------------------|--------|
| a hop along one edge | a `command` packet (type 1, MOVE) and `persona` state packets at the ticks `0, a, N - a, N` |
| a scout | a `command` packet (type 2) |
| a duty | one `command` packet (type 3) for each member, with the party mask |
| a crystal equipped | a `command` packet (type 4) |

A command is class 128. Its `sub_index` holds the type in the low 16 bits and the bytes used in the high 16; its
data is a 78-byte run (bytes 4 to 39, then 56 to 97) of little-endian 32-bit integers, and `hlc` is the step start.
Command types 1 to 4 are ours and the contract says to append, never renumber: register them before another
producer uses these numbers. The command layout is in the contract's README and in its emitted Python constants but
not in `Codec.lean`, so `PlanPackets.lean` writes it from the codec's offsets; adding it to the Lean spec would
remove the duplicate.

A state packet gives the position, velocity and acceleration at a keyframe, so a receiver can dead-reckon between
keyframes. Position is one arc-length coordinate on x, because the map has distances and no coordinates. A teleport
is two packets with zero velocity. The check in `frontier_packets` compares each decoded field with its keyframe and,
between keyframes, the distance with the mean speed times the ticks, within the rounding of the codes. Velocity is
rounded to nearest, not up, because it is not a bound.

## The frontier loop

`entities/Frontier/Loop.lean` has levels, practice, experience and a gated learn step. This tool follows it.
The **quest-beater** is the generator: it builds the next quest at the edge of what the **quest-solver** can do.
The solver is MiniZinc (CP-SAT, Chuffed, Gecode) as black-box oracles; a clean-room solver and the planner are
later steps. A level is `(track, g, h)`: tracks `scout`, `arms`, `controller`, `party`, `loadout`, `board`, `saga`
add one layer each and `saga` uses all; `g` picks the scale (2, 4, 6, 8, 12, 16, 24, 32, 48, 64 tasks); `h` is the number of
tasks already cleared and removed (default 0 in every run below). A level is solved when the solver **proves
optimality** inside the limit. A retry builds a new instance (new seed). An unsatisfiable generated instance is a
**generator fault** and stops the run.

The learn gate rewrites `frontier.json` only if a positive control (test t01) passes and three planted faults
(no zone capacity, no role mix, no reach check) each change the answer of the test that exercises them.

## Run

```
elixir tools/party_saga.exs check              # hand-checkable tests and packet tests
elixir tools/party_saga.exs packets saga 3     # solve a level, encode it as packets
sudo systemctl start party-saga-frontier       # the frontier loop and the solver agreement, as a oneshot
elixir tools/party_saga.exs validate --g 4     # generated levels are satisfiable
elixir tools/party_saga.exs learn              # the gate
elixir tools/party_saga.exs frontier --steps 56 --limit 15
elixir tools/party_saga.exs solve FILE.dzn chuffed
```
MiniZinc is found through `MINIZINC_HOME` (default: the unpacked 2.11.0 bundle under `/mnt/fire/6-datasource`).
MiniZinc is MPL-2.0; its solvers run as oracles and their source is not read.

## Results

These are measurements of **CP-SAT 9.15 with a 15 s limit per level**, on the model with the ramp (rate of change).
Chuffed and Gecode are the agreement check. A level is "solved" when the solver proves the optimum inside the limit.
The ladder is 2, 4, 6, 8, 12, 16, 24, 32, 48 and 64 tasks, with `h = 0`. Every row is an edge, not a ceiling of the
problem: a different solver, limit or seed moves it. Unsolved levels were retried with new seeds, and the count of
attempts is shown.

| Track | Solved up to (tasks) | Slowest proved | Levels tried | Unsolved levels (tasks, attempts) |
|-------|----------------------|----------------|--------------|-----------------------------------|
| `scout` | 48 | 10.02 s | 17 | 64 (4) |
| `arms` | 16 | 2.56 s | 18 | 24 (12) |
| `controller` | 24 | 8.93 s | 22 | 32 (5) |
| `party` | 48 | 16.07 s | 14 | 64 (5) |
| `loadout` | 48 | 17.54 s | 14 | 64 (5) |
| `board` | 32 | 5.31 s | 17 | 48 (5) |
| `saga` | 32 | 15.64 s | 17 | 48 (5) |

Solver agreement: 63 of 63 proved levels agree; 27 proved by CP-SAT, Chuffed and Gecode.

Reading: the track with the most freedom, `arms` (free scouts with two arms and zone capacity), stops first, at 16
tasks: 12 attempts at 24 tasks were not proved in 15 s. Tracks with duties (`party`, `loadout`) reach 48 tasks,
because a duty fixes several characters at one place and time and so shrinks the search. `board` and `saga` stop at
32 tasks, `controller` at 24. Chuffed and Gecode never contradicted CP-SAT; on the larger levels they often found no
proof in the 15 s agreement limit, so "27 proved by all three" counts only the levels all three could prove.
The learn gate (a positive control and three planted faults) passed, and `frontier.json` holds its revision.
An earlier run on the model without ramps is not comparable and was discarded.

