<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# RECTGTN: the planner model, stored in SQLite

**RECTGTN** stands for **R**elationship-**E**nabled **C**apability-**T**emporal
**G**oal-**T**ask-**N**etwork. It is the HTN (Hierarchical Task Network) planning model.

This page replaces `docs/rectgtn.md` of `contract-zone-backend` (commit `7858f2c`). Three things
changed:

1. The planner is the Lean `persona` package with the vendored `rectgtn-domain-c-abi` domain, not the
   C++ NIF `taskweft_nif`.
2. **SQLite is the canonical definition** of domains, problems and plans. Migrations in
   `datasources/sqlite/migrations/` define the schema. JSON-LD and YAML-LD are exchange formats, made
   from the tables and loaded into them. The `.dsl` files are no longer the source.
3. The validator error tables of the old page belong to the Elixir `Taskweft.JSONLD.Loader`. This page
   does not repeat them, because this repository does not run that validator. The database rejects
   some bad shapes instead (see "What the database rejects").

## What each letter means

| Letter | Concept | In the data |
|--------|---------|-------------|
| **R** | **Relationship**: a graph of `(subject, relation, object)` facts. Also the replan loop that recovers from a failed step. | table `problem_edge` |
| **E** | **Enabled**: a primitive action, a command that runs and can fail. | tables `action`, `action_parameter`, `action_step` |
| **C** | **Capability**: which capabilities an action needs, and which entities hold them. | tables `capability`, `action_capability`, `entity_capability` |
| **T** | **Temporal**: ISO 8601 durations, schedule consistency, plan timing. | `action_duration`, `plan_reached`, `plan_step.duration` |
| **G** | **Goal**: desired `(pointer, value)` bindings. | table `task_goal_binding` |
| **T** | **Task**: a compound call, decomposed through methods and alternatives. | tables `method`, `method_parameter`, `alternative`, `task_call`, `task_call_argument` |
| **N** | **Network**: a set of bindings the planner may satisfy in any order (a multigoal). | table `task_multigoal_binding` |

## The node kinds

The Lean planner (`Planner/Types.lean` in `rectgtn-domain-c-abi`) has three node kinds:
`RECTGTNNode.task`, `RECTGTNNode.goal_geq` and `RECTGTNNode.verify_goal`. The old page named the C++
variant `TwCall`, `TwGoal` and `TwMultiGoal`. The JSON-LD shapes are the same ones the old page showed:

- a **call array** `[name, argument, ...]` is a primitive action or a compound task, as `name` is in
  `actions` or `methods`;
- a **goal** is `{"pointer": "/var/key", "eq": value}`;
- a **multigoal** is `{"multigoal": {"<var>": {"<key>": value}}}`.

`Persona/Jsonld.lean` reads call arrays and goal pointers from `todo_list`. In the database each
`todo_list` item is one row of `problem_task` and has exactly one kind. A call is a row in `task_call`
with its arguments in `task_call_argument`. A goal has rows in `task_goal_binding`. A multigoal has rows
in `task_multigoal_binding`, one per `(variable, key)`. Triggers reject a task that has two kinds. The
desired value of a binding is a JSON scalar in a `desired` column.

## Where each part of a document lives

| JSON-LD | Table |
|---------|-------|
| domain `name`, `version` | `domain` |
| domain `description`, `source` | `domain_description`, `domain_source` (a satellite row only when present) |
| `enums` | `enumeration`, `enumeration_member` |
| `actions.<name>` | `action`, `action_duration` (absent means instantaneous), `action_description`, `action_operation`, `action_duration_basis` |
| action `params` | `action_parameter`; a parameter that names an enumeration also has a row in `action_parameter_enumeration` |
| action `body` | `action_step`, one JSON step per row, in order |
| `methods.<name>` | `method`, `method_parameter`, `method_parameter_enumeration`, `method_wraps` |
| method `alternatives` | `alternative` (`name`, JSON `body` with `check`, `subtasks`, optional `graph`) |
| `capabilities.actions` | `capability`, `action_capability`; the loader compiles each row to a guard step in the action body |
| `capabilities.entities` | `entity_capability`; the loader compiles each row to a `HAS_CAPABILITY` edge |
| `capabilities.graph.edges` | `problem_edge` |
| problem `name`, `version` | `problem` |
| problem `description`, `source`, `origin` | `problem_description`, `problem_source`, `problem_origin` |
| problem `variables` | `problem_variable`, `variable_init` |
| problem `todo_list` | `problem_task` (one row per item, in order), then the kind tables above |
| plan | `plan`, `plan_name`, then `plan_reached` with `plan_step` and `plan_step_parameter`, or `plan_refusal` |

The schema is in ETNF. Every column is `NOT NULL`. A fact that may be absent has its own table, so
the database never stores a NULL. Surrogate keys are UUIDv7 in a 16-byte `BLOB`; the application
creates them, because SQLite has no function for it. The SQL shim returns every value as text, so a
query reads a key as `hex(id)` and a write uses an `X'...'` literal. Names are written in full.

## Capabilities (R and C)

A capability guards an action. The planner applies an action to an agent, its first parameter, only
when the agent holds every capability the action needs. When it does not, the planner tries the next
alternative. With none left, the goal is `unreachable`.

The planner already enforces this through two things it reads. The tables hold the capabilities as
facts, and the loader compiles them into those two things when it builds the document:

1. An **action guard**: for each row of `action_capability`, the loader puts a step at the front of the
   action body: `{"eval": {"type": "rebac/check", "subject": "[agent]", "rel": "HAS_CAPABILITY",
   "object": "fly"}}`, where `[agent]` is the first parameter of the action.
2. A **holding edge**: for each row of `entity_capability`, the loader adds an edge to
   `capabilities.graph.edges`: `{"subject": "1", "rel": "HAS_CAPABILITY", "object": "fly"}`. The
   subject is the integer value of the entity in its enumeration, not its name.

An entity is a member of an enumeration. `entity_capability` points at `enumeration_member`, so an
entity that does not exist cannot hold a capability.

The planner was run on a one-action domain to confirm this. With the guard and the matching edge the
plan is the single move. With the guard and no edge, or with an edge that names the entity (`c1`)
instead of its value, the goal is `unreachable`. Without the guard, any entity can act.

The older `"capabilities": {"entities": ..., "actions": ...}` form of the original page is not read by
the planner. The importer maps it to the rows above, and the exporter writes `"entities": {}`.

**Status.** The loader is `repositories/Frontier/Store.lean`; `frontier_store plan PROBLEM` runs it.
It always writes both forms from the same rows, with no switch. On a test database, a problem whose
entity holds `fly` plans the move, and a problem whose entity does not hold it is `unreachable`. The
importer (JSON-LD into rows) is not written yet, so that test database was filled by hand.

## Temporal duration (T)

An action may have a duration, an ISO 8601 string such as `PT5S`, in `action_duration`. An action with no row is instantaneous, and the loader writes no `duration` key for it. A reached plan records `consistent` and
`total`, and each step records its own `duration`. A step's duration is a separate fact from the
action's. In the fixtures, 65 of 70 steps differ from the duration of their action.

## What is rejected, and by what

The old page listed rejected shapes with the error of the Elixir validator. Each row below says what
happens to the same shape now. **Database** means an `INSERT` fails. **Planner** means the document
loads and the planner refuses it. **Not storable** means the tables have no way to hold the shape, so
the importer cannot write it. Every **Database** row was run against the schema.

### Calls (E and T)

| Old rejected shape | Now |
|--------------------|-----|
| a task that is a bare string, not a call array | Not storable. A call is `task_call` plus `task_call_argument` rows. |
| a call with the wrong number of arguments (`do_a` takes 0, got 1) | Planner. `instAct` returns nothing when the count is wrong, so the goal is `unreachable`. |
| legacy `{"set": ...}` action step | Database. `action_step.step` must have `eval` or `pointer/set`. |
| an action step that is not an object | Database. Same check. |
| legacy `{"pointer": ..., "eq": ...}` check clause | Database. A trigger on `alternative` requires every `check` clause to have `eval`. |
| `subtasks` or `check` that is not an array | Database. Check on `alternative.body`. |
| a body that names a variable `{z}` that is not declared | **Not checked.** The planner treats it as a plain string. |

### Goals (G)

| Old rejected shape | Now |
|--------------------|-----|
| a binding with no `eq` | Database. `task_goal_binding.desired` is `NOT NULL`. |
| a binding with no `pointer` | Database. `pointer` is `NOT NULL`. |
| a `pointer` that is not a string | Database. A pointer must start with `/`, and a number stored as text does not. |
| a binding that is not an object, or `goals` that is neither object nor array | Not storable. |
| a `desired` value that is not JSON | Database. `json_valid`. |

### Multigoals (N)

| Old rejected shape | Now |
|--------------------|-----|
| `{"multigoal": {}}`, a multigoal with no variable | Not storable as a multigoal. A task with no rows of any kind appears in the view `problem_task_without_kind`, and the loader refuses it with `task <id> has no kind`. |
| `{"multigoal": {"pos": {}}}`, a variable with no key | Not storable. A variable exists only through its `(variable, key)` rows. |
| a variable bound to a non-object, or a multigoal that is not an object | Not storable. |
| `{"goal": {}}`, an object task that is not a multigoal | Not storable. |
| a task that is both a call and a goal or multigoal | Database. Triggers on the three kind tables. |

### Capabilities (R and C) and temporal duration (T)

The old page had no table for these, because the validator ignored a bad shape. The database now
checks them.

| Shape | Now |
|-------|-----|
| an entity that holds a capability but is not in its enumeration | Database. Foreign key from `entity_capability` to `enumeration_member`. |
| a capability that does not exist | Database. Foreign key to `capability`. |
| an action with a capability and no first parameter | Loader. It refuses with `an action with a capability needs a first parameter`. |
| a duration that does not start with `P` (`5 minutes`) | Database. Applies to `action_duration`, `plan_step.duration` and `plan_reached.total`. |
| a duration that starts with `P` but is not valid ISO 8601 (`PX`) | **Not checked** by the database. The planner decides. |

### Everywhere

- a surrogate key that is not a UUIDv7;
- a NULL in any column, and a value that cannot become the column type (`STRICT` tables);
- an action or method body that is not valid JSON;
- a plan that is both reached and refused, or a plan step on a plan that is not reached;
- a reference to a row that does not exist (the SQL shim turns foreign keys on for each connection).

The database does **not** check that the action of a plan step belongs to the domain of the plan's
problem.

## Soundness contract

A domain that plans must replan to completion: replanning the returned plan with `fail_step == -1`
reports every step complete. The checks for this repository are `lake build frontier` and the planner
replay (`elixir /mnt/fire/3-interactor/interactor-hair-cards-viewer/tools/serve.exs replay`, run from
the repository root with `FRONTIER_DB` set).

## See also

- `datasources/sqlite/migrations/0001_planner.sql`, `0002_capabilities.sql`: the schema.
- `repositories/Frontier/Db.lean`: the migration runner.
- `.lake/packages/persona/Persona/Jsonld.lean`: the loader for the JSON-LD shapes.
- `.lake/packages/persona/thirdparty/rectgtn-domain-c-abi/Planner/Types.lean`: `RECTGTNNode`.
- https://www.w3.org/TR/r2rml/: the mapping standard under evaluation for the RDF view.
