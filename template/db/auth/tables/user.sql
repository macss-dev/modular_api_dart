-- auth.user table
CREATE TABLE auth.user (
  id               INTEGER GENERATED ALWAYS AS IDENTITY,
  username         VARCHAR(16)     NOT NULL,
  full_name        VARCHAR(250)    NOT NULL,
  created_at       TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

  -- Constraints
  CONSTRAINT user_username_key UNIQUE (username),
  CONSTRAINT user_pkey PRIMARY KEY (id)
);

-- Indexes for auth.user
CREATE INDEX ix_user_username   ON auth.user(username);
CREATE INDEX ix_user_full_name  ON auth.user(full_name);
