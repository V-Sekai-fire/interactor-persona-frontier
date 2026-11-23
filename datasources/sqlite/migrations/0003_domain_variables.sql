CREATE TABLE domain_variable (
  domain_id BLOB NOT NULL REFERENCES domain(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  PRIMARY KEY (domain_id, name)
) STRICT;

CREATE TABLE domain_variable_description (
  domain_id BLOB NOT NULL,
  variable TEXT NOT NULL,
  description TEXT NOT NULL,
  PRIMARY KEY (domain_id, variable),
  FOREIGN KEY (domain_id, variable) REFERENCES domain_variable(domain_id, name) ON DELETE CASCADE
) STRICT;

CREATE TABLE domain_variable_init (
  domain_id BLOB NOT NULL,
  variable TEXT NOT NULL,
  key TEXT NOT NULL,
  value INTEGER NOT NULL,
  PRIMARY KEY (domain_id, variable, key),
  FOREIGN KEY (domain_id, variable) REFERENCES domain_variable(domain_id, name) ON DELETE CASCADE
) STRICT;
