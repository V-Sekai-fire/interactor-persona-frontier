# Agent jobs: a resource model for the planner and the scheduler

Status: a design. Nothing here is encoded in a domain yet, and no plan has been run on it.
What the engine can say was read from `entities/domains/artifacts-mmo.yamlld`: an action has `eval` tests
(`math/eq`, `math/ge` over `pointer/get`), `pointer/set` effects with a literal value, a `duration`, and
`x-duration: measured|unmeasured`. There is no arithmetic, so a fact is set, never counted.

## 1. Two jobs for two parts

- The planner says what may run and in which order. It refuses a job that needs a resource that does not exist
  and a cycle among dependencies, by name. It carries the cost of each job on each resource it can use.
- The scheduler (`tools/steal.exs` in obs-webchat, work stealing) decides when, and runs jobs in parallel.
  It reads the same table, so the two cannot disagree about a resource.

## 2. Facts (all integers)

- `held/<lane>`: 0 when the lane is free, else the number of the job that holds it.
- `done/<job>`: 0 or 1.

A resource is one or more lanes. The 4090 is two lanes of 12 GB (`gpu-a`, `gpu-b`) plus the pair `gpu-full`.
Why lanes: the face job held 24 of 24.5 GB and stopped the policy run. Memory cannot be counted here, so it
is cut into fixed lanes, and a job takes a lane whose size is at least its need. `cpu` has one lane per
core group and `hailo` has one lane.

## 3. Actions, one pair per job and lane it can use

- `start-<job>-<lane>`: tests `done/<dep> = 1` for each dependency and `held/<lane> = 0`;
  sets `held/<lane> = <job number>`.
- `finish-<job>-<lane>`: tests `held/<lane> = <job number>`; sets `held/<lane> = 0` and `done/<job> = 1`.
  Its `duration` is the cost of the job on that lane.
- A job that needs `gpu-full` tests both lanes free and sets both.

## 4. Goals

`settle-<job>` is a method: settle each dependency, then start and finish on one lane. A job that can use
two resources has one alternative per lane, fastest first. The goal `all-jobs` lists every `settle`.

## 5. Costs

Only measured numbers go in, through the experience gate, never typed in as if known. Measured so far:
Kimodo matrix on the GPU, 980 s for 16 runs (23 to 57 s each); the retarget batch on the CPU, 3,901 s for 67 clips.
The Hailo compile has no measured cost yet (it stopped at 172 s in the optimizer with an error).
Everything else stays `unmeasured`.

## 6. What the plan does not give

A plan is a sequence. Overlap comes from the scheduler, which starts any job whose tests hold and whose lane
is free. Stealing: an idle lane takes a job from the back of another queue only when it would finish sooner
than the owner could.

## 7. Open

- The lanes are fixed in advance, so a job that would fit in 7 GB uses a 12 GB lane.
- Whether `persona_plan` takes `.yamlld` directly or needs the JSON form first has not been checked.
- The checks to write: a job is never planned onto a held lane; a plan with the lane test removed must fail.
