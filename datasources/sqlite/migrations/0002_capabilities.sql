CREATE TABLE capability (
  id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 16 AND hex(substr(id, 7, 1)) LIKE '7_' AND hex(substr(id, 9, 1)) BETWEEN '80' AND 'BF'),
  domain_id BLOB NOT NULL REFERENCES domain(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  UNIQUE (domain_id, name)
) STRICT;

CREATE TABLE action_capability (
  action_id BLOB NOT NULL REFERENCES action(id) ON DELETE CASCADE,
  capability_id BLOB NOT NULL REFERENCES capability(id) ON DELETE CASCADE,
  PRIMARY KEY (action_id, capability_id)
) STRICT;

CREATE TABLE entity_capability (
  problem_id BLOB NOT NULL REFERENCES problem(id) ON DELETE CASCADE,
  enumeration_id BLOB NOT NULL,
  entity TEXT NOT NULL,
  capability_id BLOB NOT NULL REFERENCES capability(id) ON DELETE CASCADE,
  PRIMARY KEY (problem_id, enumeration_id, entity, capability_id),
  FOREIGN KEY (enumeration_id, entity) REFERENCES enumeration_member(enumeration_id, name) ON DELETE CASCADE
) STRICT;
