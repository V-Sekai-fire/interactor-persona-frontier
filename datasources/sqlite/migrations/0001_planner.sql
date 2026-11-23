CREATE TABLE domain (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  name TEXT NOT NULL UNIQUE,
  version TEXT NOT NULL
) STRICT;

CREATE TABLE domain_description (
  domain_id BLOB PRIMARY KEY REFERENCES domain(id) ON DELETE CASCADE,
  description TEXT NOT NULL
) STRICT;

CREATE TABLE domain_source (
  domain_id BLOB PRIMARY KEY REFERENCES domain(id) ON DELETE CASCADE,
  source TEXT NOT NULL
) STRICT;

CREATE TABLE enumeration (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  domain_id BLOB NOT NULL REFERENCES domain(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  UNIQUE (domain_id, name)
) STRICT;

CREATE TABLE enumeration_member (
  enumeration_id BLOB NOT NULL REFERENCES enumeration(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  value INTEGER NOT NULL,
  PRIMARY KEY (enumeration_id, name)
) STRICT;

CREATE TABLE action (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  domain_id BLOB NOT NULL REFERENCES domain(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  UNIQUE (domain_id, name)
) STRICT;

CREATE TABLE action_duration (
  action_id BLOB NOT NULL PRIMARY KEY REFERENCES action(id) ON DELETE CASCADE,
  duration TEXT NOT NULL CHECK (duration GLOB 'P*')
) STRICT;

CREATE TABLE action_description (
  action_id BLOB PRIMARY KEY REFERENCES action(id) ON DELETE CASCADE,
  description TEXT NOT NULL
) STRICT;

CREATE TABLE action_operation (
  action_id BLOB PRIMARY KEY REFERENCES action(id) ON DELETE CASCADE,
  operation TEXT NOT NULL
) STRICT;

CREATE TABLE action_duration_basis (
  action_id BLOB PRIMARY KEY REFERENCES action(id) ON DELETE CASCADE,
  basis TEXT NOT NULL
) STRICT;

CREATE TABLE action_parameter (
  action_id BLOB NOT NULL REFERENCES action(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  PRIMARY KEY (action_id, position),
  UNIQUE (action_id, name)
) STRICT;

CREATE TABLE action_parameter_enumeration (
  action_id BLOB NOT NULL,
  position INTEGER NOT NULL,
  enumeration_id BLOB NOT NULL REFERENCES enumeration(id) ON DELETE CASCADE,
  PRIMARY KEY (action_id, position),
  FOREIGN KEY (action_id, position) REFERENCES action_parameter(action_id, position) ON DELETE CASCADE
) STRICT;

CREATE TABLE action_step (
  action_id BLOB NOT NULL REFERENCES action(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  step TEXT NOT NULL CHECK (json_valid(step) AND json_type(step) = 'object' AND (json_type(step, '$.eval') IS NOT NULL OR json_type(step, '$."pointer/set"') IS NOT NULL)),
  PRIMARY KEY (action_id, position)
) STRICT;

CREATE TABLE method (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  domain_id BLOB NOT NULL REFERENCES domain(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  UNIQUE (domain_id, name)
) STRICT;

CREATE TABLE method_wraps (
  method_id BLOB PRIMARY KEY REFERENCES method(id) ON DELETE CASCADE,
  action_id BLOB NOT NULL REFERENCES action(id) ON DELETE CASCADE
) STRICT;

CREATE TABLE method_parameter (
  method_id BLOB NOT NULL REFERENCES method(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  PRIMARY KEY (method_id, position),
  UNIQUE (method_id, name)
) STRICT;

CREATE TABLE method_parameter_enumeration (
  method_id BLOB NOT NULL,
  position INTEGER NOT NULL,
  enumeration_id BLOB NOT NULL REFERENCES enumeration(id) ON DELETE CASCADE,
  PRIMARY KEY (method_id, position),
  FOREIGN KEY (method_id, position) REFERENCES method_parameter(method_id, position) ON DELETE CASCADE
) STRICT;

CREATE TABLE alternative (
  method_id BLOB NOT NULL REFERENCES method(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  body TEXT NOT NULL CHECK (json_valid(body) AND json_type(body) = 'object' AND coalesce(json_type(body, '$.check'), 'array') = 'array' AND coalesce(json_type(body, '$.subtasks'), 'array') = 'array'),
  PRIMARY KEY (method_id, position),
  UNIQUE (method_id, name)
) STRICT;

CREATE TABLE problem (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  domain_id BLOB NOT NULL REFERENCES domain(id) ON DELETE CASCADE,
  name TEXT NOT NULL UNIQUE,
  version TEXT NOT NULL
) STRICT;

CREATE TABLE problem_description (
  problem_id BLOB PRIMARY KEY REFERENCES problem(id) ON DELETE CASCADE,
  description TEXT NOT NULL
) STRICT;

CREATE TABLE problem_source (
  problem_id BLOB PRIMARY KEY REFERENCES problem(id) ON DELETE CASCADE,
  source TEXT NOT NULL
) STRICT;

CREATE TABLE problem_origin (
  problem_id BLOB PRIMARY KEY REFERENCES problem(id) ON DELETE CASCADE,
  origin TEXT NOT NULL
) STRICT;

CREATE TABLE problem_variable (
  problem_id BLOB NOT NULL REFERENCES problem(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  PRIMARY KEY (problem_id, name)
) STRICT;

CREATE TABLE variable_init (
  problem_id BLOB NOT NULL,
  variable TEXT NOT NULL,
  key TEXT NOT NULL,
  value INTEGER NOT NULL,
  PRIMARY KEY (problem_id, variable, key),
  FOREIGN KEY (problem_id, variable) REFERENCES problem_variable(problem_id, name) ON DELETE CASCADE
) STRICT;

CREATE TABLE problem_task (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  problem_id BLOB NOT NULL REFERENCES problem(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  UNIQUE (problem_id, position)
) STRICT;

CREATE TABLE task_call (
  task_id BLOB NOT NULL PRIMARY KEY REFERENCES problem_task(id) ON DELETE CASCADE,
  name TEXT NOT NULL
) STRICT;

CREATE TABLE task_call_argument (
  task_id BLOB NOT NULL REFERENCES task_call(task_id) ON DELETE CASCADE,
  argument_position INTEGER NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (task_id, argument_position)
) STRICT;

CREATE TABLE task_goal_binding (
  task_id BLOB NOT NULL REFERENCES problem_task(id) ON DELETE CASCADE,
  binding_position INTEGER NOT NULL,
  pointer TEXT NOT NULL CHECK (pointer GLOB '/*'),
  desired TEXT NOT NULL CHECK (json_valid(desired)),
  PRIMARY KEY (task_id, binding_position)
) STRICT;

CREATE TABLE task_multigoal_binding (
  task_id BLOB NOT NULL REFERENCES problem_task(id) ON DELETE CASCADE,
  variable TEXT NOT NULL,
  key TEXT NOT NULL,
  desired TEXT NOT NULL CHECK (json_valid(desired)),
  PRIMARY KEY (task_id, variable, key)
) STRICT;

CREATE TRIGGER task_call_not_task_goal_binding BEFORE INSERT ON task_call
WHEN EXISTS (SELECT 1 FROM task_goal_binding WHERE task_id = NEW.task_id)
BEGIN SELECT RAISE(ABORT, 'task has another kind'); END;

CREATE TRIGGER task_call_not_task_multigoal_binding BEFORE INSERT ON task_call
WHEN EXISTS (SELECT 1 FROM task_multigoal_binding WHERE task_id = NEW.task_id)
BEGIN SELECT RAISE(ABORT, 'task has another kind'); END;

CREATE TRIGGER task_goal_binding_not_task_call BEFORE INSERT ON task_goal_binding
WHEN EXISTS (SELECT 1 FROM task_call WHERE task_id = NEW.task_id)
BEGIN SELECT RAISE(ABORT, 'task has another kind'); END;

CREATE TRIGGER task_goal_binding_not_task_multigoal_binding BEFORE INSERT ON task_goal_binding
WHEN EXISTS (SELECT 1 FROM task_multigoal_binding WHERE task_id = NEW.task_id)
BEGIN SELECT RAISE(ABORT, 'task has another kind'); END;

CREATE TRIGGER task_multigoal_binding_not_task_call BEFORE INSERT ON task_multigoal_binding
WHEN EXISTS (SELECT 1 FROM task_call WHERE task_id = NEW.task_id)
BEGIN SELECT RAISE(ABORT, 'task has another kind'); END;

CREATE TRIGGER task_multigoal_binding_not_task_goal_binding BEFORE INSERT ON task_multigoal_binding
WHEN EXISTS (SELECT 1 FROM task_goal_binding WHERE task_id = NEW.task_id)
BEGIN SELECT RAISE(ABORT, 'task has another kind'); END;

CREATE TABLE problem_edge (
  problem_id BLOB NOT NULL REFERENCES problem(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  relation TEXT NOT NULL,
  object TEXT NOT NULL,
  PRIMARY KEY (problem_id, subject, relation, object)
) STRICT;

CREATE TABLE plan (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  problem_id BLOB NOT NULL REFERENCES problem(id) ON DELETE CASCADE
) STRICT;

CREATE TABLE plan_name (
  plan_id BLOB PRIMARY KEY REFERENCES plan(id) ON DELETE CASCADE,
  name TEXT NOT NULL UNIQUE
) STRICT;

CREATE TABLE plan_reached (
  plan_id BLOB PRIMARY KEY REFERENCES plan(id) ON DELETE CASCADE,
  consistent INTEGER NOT NULL CHECK (consistent IN (0, 1)),
  total TEXT NOT NULL CHECK (total GLOB 'P*')
) STRICT;

CREATE TABLE plan_refusal (
  plan_id BLOB PRIMARY KEY REFERENCES plan(id) ON DELETE CASCADE,
  reason TEXT NOT NULL
) STRICT;

CREATE TRIGGER plan_reached_not_refused BEFORE INSERT ON plan_reached
WHEN EXISTS (SELECT 1 FROM plan_refusal WHERE plan_id = NEW.plan_id)
BEGIN SELECT RAISE(ABORT, 'plan is refused'); END;

CREATE TRIGGER plan_refused_not_reached BEFORE INSERT ON plan_refusal
WHEN EXISTS (SELECT 1 FROM plan_reached WHERE plan_id = NEW.plan_id)
BEGIN SELECT RAISE(ABORT, 'plan is reached'); END;

CREATE TABLE plan_step (
  plan_id BLOB NOT NULL REFERENCES plan_reached(plan_id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  action_id BLOB NOT NULL REFERENCES action(id),
  duration TEXT NOT NULL CHECK (duration GLOB 'P*'),
  PRIMARY KEY (plan_id, position)
) STRICT;

CREATE TABLE plan_step_parameter (
  plan_id BLOB NOT NULL,
  position INTEGER NOT NULL,
  argument_position INTEGER NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (plan_id, position, argument_position),
  FOREIGN KEY (plan_id, position) REFERENCES plan_step(plan_id, position) ON DELETE CASCADE
) STRICT;

CREATE TRIGGER alternative_check_clause_is_eval BEFORE INSERT ON alternative
WHEN EXISTS (SELECT 1 FROM json_each(NEW.body, '$.check') WHERE json_type(value, '$.eval') IS NULL)
BEGIN SELECT RAISE(ABORT, 'a check clause must be an eval'); END;

CREATE VIEW problem_task_without_kind AS
SELECT t.id, t.problem_id, t.position FROM problem_task t
WHERE NOT EXISTS (SELECT 1 FROM task_call c WHERE c.task_id = t.id)
  AND NOT EXISTS (SELECT 1 FROM task_goal_binding g WHERE g.task_id = t.id)
  AND NOT EXISTS (SELECT 1 FROM task_multigoal_binding m WHERE m.task_id = t.id);
