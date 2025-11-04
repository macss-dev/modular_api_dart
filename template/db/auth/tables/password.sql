-- auth.password table
CREATE TABLE auth.password (
  id                  INTEGER GENERATED ALWAYS AS IDENTITY,
  id_user             INTEGER NOT NULL,
  password_hash       VARCHAR(255) NOT NULL,
  created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT password_id_user_fkey FOREIGN KEY (id_user) 
    REFERENCES auth.user(id) ON DELETE CASCADE,
  CONSTRAINT password_id_user_unique UNIQUE (id_user),
  CONSTRAINT password_pkey PRIMARY KEY (id)
);

-- Index for auth.password
CREATE INDEX ix_password_id_user ON auth.password(id_user);
