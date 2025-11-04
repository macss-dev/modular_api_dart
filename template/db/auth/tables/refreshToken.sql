-- auth.refresh_token table
CREATE TABLE auth.refresh_token (
  id               INTEGER GENERATED ALWAYS AS IDENTITY,
  id_user          INTEGER NOT NULL,
  token_hash       VARCHAR(255) NOT NULL,
  previous_id      INTEGER NULL,
  revoked          BOOLEAN DEFAULT FALSE,
  created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at       TIMESTAMP NOT NULL,
  
  CONSTRAINT refresh_token_id_user_fkey FOREIGN KEY (id_user) 
    REFERENCES auth.user(id) ON DELETE CASCADE,
  CONSTRAINT refresh_token_previous_id_fkey FOREIGN KEY (previous_id) 
    REFERENCES auth.refresh_token(id) ON DELETE SET NULL,
  CONSTRAINT refresh_token_pkey PRIMARY KEY (id)
);

-- Indexes for auth.refresh_token
CREATE INDEX ix_refresh_token_user ON auth.refresh_token(id_user);
CREATE INDEX ix_refresh_token_hash ON auth.refresh_token(token_hash);
CREATE INDEX ix_refresh_token_revoked ON auth.refresh_token(revoked);
